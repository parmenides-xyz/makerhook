// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/ISphericalPool.sol';
import './interfaces/ISphericalPoolDeployer.sol';
import './interfaces/ISphericalFactory.sol';
import './interfaces/callback/ISphericalMintCallback.sol';
import './interfaces/callback/ISphericalSwapCallback.sol';
import './interfaces/callback/ISphericalFlashCallback.sol';

import './libraries/LowGasSafeMath.sol';
import './libraries/SafeCast.sol';
import './libraries/SphericalTick.sol';
import './libraries/SphericalPosition.sol';
import './libraries/SphericalTickMath.sol';
import './libraries/SphericalSwapMath.sol';
import './libraries/FullMath.sol';
import './libraries/FixedPoint96.sol';
import './libraries/FixedPoint128.sol';
import './libraries/TransferHelper.sol';

contract SphericalPool is ISphericalPool {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SphericalTick for mapping(int24 => SphericalTick.Info);
    using SphericalPosition for mapping(int24 => SphericalPosition.Info);

    /// @inheritdoc ISphericalPoolImmutables
    address public immutable override factory;
    /// @inheritdoc ISphericalPoolImmutables
    address[] public override tokens;
    /// @inheritdoc ISphericalPoolImmutables
    uint24 public immutable override fee;
    /// @inheritdoc ISphericalPoolImmutables
    int24 public immutable override tickSpacing;
    /// @inheritdoc ISphericalPoolImmutables
    uint128 public immutable override maxLiquidityPerTick;
    /// @inheritdoc ISphericalPoolImmutables
    uint256 public immutable override numAssets;
    /// @inheritdoc ISphericalPoolImmutables
    uint256 public immutable override radiusQ96;
    /// @inheritdoc ISphericalPoolImmutables
    uint256 public immutable override sqrtNumAssetsQ96;

    struct Slot0 {
        // Current consolidated radius from interior ticks
        uint256 radiusInteriorQ96;
        // Current consolidated k from boundary ticks
        uint256 kBoundaryQ96;
        // Whether the pool is initialized
        bool initialized;
        // The current protocol fee
        uint8 feeProtocol;
        // Whether the pool is locked
        bool unlocked;
    }

    /// @inheritdoc ISphericalPoolState
    Slot0 public override slot0;

    /// @inheritdoc ISphericalPoolState
    uint256[] public override currentReserves;
    
    /// @inheritdoc ISphericalPoolState
    uint256[] public override feeGrowthGlobalX128;

    /// @inheritdoc ISphericalPoolState
    uint128 public override liquidity;

    /// @dev Tick info by tick index
    mapping(int24 => SphericalTick.Info) public override tickInfo;
    
    /// @dev Position info by tick index (single owner per tick)
    mapping(int24 => SphericalPosition.Info) public override positions;

    /// @dev Active tick indices
    int24[] public activeTicks;

    /// @dev Accumulated protocol fees per token
    uint256[] public override protocolFees;

    modifier lock() {
        require(slot0.unlocked, 'LOK');
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    modifier onlyFactoryOwner() {
        require(msg.sender == ISphericalFactory(factory).owner(), 'OO');
        _;
    }

    constructor() {
        (factory, tokens, fee, tickSpacing, radiusQ96) = ISphericalPoolDeployer(msg.sender).parameters();
        
        numAssets = tokens.length;
        require(numAssets >= 2, 'MIN_ASSETS');
        
        // Calculate sqrt(n) in Q96 format
        sqrtNumAssetsQ96 = FullMath.sqrt(numAssets * FixedPoint96.Q96 * FixedPoint96.Q96);
        
        maxLiquidityPerTick = SphericalTick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
        
        // Initialize arrays
        currentReserves = new uint256[](numAssets);
        feeGrowthGlobalX128 = new uint256[](numAssets);
        protocolFees = new uint256[](numAssets);
    }

    /// @inheritdoc ISphericalPoolActions
    function initialize(uint256[] calldata initialReserves) external override {
        require(!slot0.initialized, 'AI');
        require(initialReserves.length == numAssets, 'INVALID_LENGTH');
        
        // Verify reserves lie on the sphere
        uint256 sumSquares = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            require(initialReserves[i] > 0, 'ZERO_RESERVE');
            currentReserves[i] = initialReserves[i];
            
            // Calculate sum of squares
            uint256 squared = FullMath.mulDiv(
                initialReserves[i],
                initialReserves[i],
                FixedPoint96.Q96
            );
            sumSquares = sumSquares.add(squared);
        }
        
        // Verify √(sum of squares) ≈ radius
        uint256 actualRadius = FullMath.sqrt(sumSquares * FixedPoint96.Q96);
        require(
            actualRadius >= radiusQ96.mul(99).div(100) && 
            actualRadius <= radiusQ96.mul(101).div(100),
            'OFF_SPHERE'
        );
        
        slot0.initialized = true;
        slot0.unlocked = true;
        
        emit Initialize(initialReserves);
    }

    /// @inheritdoc ISphericalPoolActions
    function mint(
        int24 tick,
        uint128 _liquidity,
        bytes calldata data
    ) external override lock returns (uint256[] memory amounts) {
        require(_liquidity > 0, 'LIQ');
        require(tick >= 0 && tick <= SphericalTickMath.MAX_TICK, 'TI');
        
        SphericalPosition.Info storage position = positions[tick];
        SphericalTick.Info storage tickData = tickInfo[tick];
        
        // Ensure single owner per tick
        if (position.owner == address(0)) {
            position.initialize(msg.sender, numAssets);
        } else {
            require(position.owner == msg.sender, 'NOT_OWNER');
        }
        
        // Update tick
        bool flipped = tickInfo.update(
            tick,
            0, // Not used for spherical AMM
            int128(_liquidity),
            feeGrowthGlobalX128,
            0, // secondsPerLiquidityCumulativeX128
            0, // tickCumulative
            uint32(block.timestamp),
            false, // upper
            maxLiquidityPerTick,
            numAssets
        );
        
        if (flipped) {
            _addActiveTick(tick);
            
            // Initialize tick geometry
            SphericalTick.PoolGeometry memory geometry = SphericalTick.PoolGeometry({
                radiusQ96: radiusQ96,
                n: numAssets,
                sqrtNQ96: sqrtNumAssetsQ96
            });
            
            tickInfo.initializeGeometry(tick, radiusQ96, geometry);
        }
        
        liquidity = liquidity.add(_liquidity);
        
        // Calculate amounts needed based on current reserves
        amounts = new uint256[](numAssets);
        for (uint256 i = 0; i < numAssets; i++) {
            amounts[i] = FullMath.mulDiv(
                currentReserves[i],
                _liquidity,
                liquidity
            );
        }
        
        // Callback for payment
        ISphericalMintCallback(msg.sender).sphericalMintCallback(amounts, data);
        
        // Verify payment
        for (uint256 i = 0; i < numAssets; i++) {
            uint256 balance = IERC20Minimal(tokens[i]).balanceOf(address(this));
            require(balance >= currentReserves[i].add(amounts[i]), 'M0');
            currentReserves[i] = balance;
        }
        
        emit Mint(msg.sender, tick, _liquidity, amounts);
    }

    /// @inheritdoc ISphericalPoolActions
    function burn(
        int24 tick,
        uint128 _liquidity
    ) external override lock returns (uint256[] memory amounts) {
        SphericalPosition.Info storage position = positions[tick];
        require(position.owner == msg.sender, 'NOT_OWNER');
        require(_liquidity > 0, 'LIQ');
        
        SphericalTick.Info storage tickData = tickInfo[tick];
        require(tickData.liquidityGross >= _liquidity, 'INSUFFICIENT');
        
        // Update tick
        bool flipped = tickInfo.update(
            tick,
            0, // Not used
            -int128(_liquidity),
            feeGrowthGlobalX128,
            0, // secondsPerLiquidityCumulativeX128
            0, // tickCumulative
            uint32(block.timestamp),
            false, // upper
            maxLiquidityPerTick,
            numAssets
        );
        
        if (flipped) {
            _removeActiveTick(tick);
            tickInfo.clear(tick);
        }
        
        liquidity = liquidity.sub(_liquidity);
        
        // Calculate amounts to return
        amounts = new uint256[](numAssets);
        for (uint256 i = 0; i < numAssets; i++) {
            amounts[i] = FullMath.mulDiv(
                currentReserves[i],
                _liquidity,
                liquidity.add(_liquidity)
            );
            
            // Transfer tokens
            if (amounts[i] > 0) {
                currentReserves[i] = currentReserves[i].sub(amounts[i]);
                TransferHelper.safeTransfer(tokens[i], msg.sender, amounts[i]);
            }
        }
        
        emit Burn(msg.sender, tick, _liquidity, amounts);
    }

    /// @inheritdoc ISphericalPoolActions
    function collect(
        int24 tick,
        address recipient,
        uint128[] calldata amountRequested
    ) external override lock returns (uint128[] memory amounts) {
        require(amountRequested.length == numAssets, 'INVALID_LENGTH');
        
        SphericalPosition.Info storage position = positions[tick];
        require(position.owner == msg.sender, 'NOT_OWNER');
        
        amounts = new uint128[](numAssets);
        
        for (uint256 i = 0; i < numAssets; i++) {
            uint128 owed = position.tokensOwed[i];
            
            if (amountRequested[i] > owed) {
                amounts[i] = owed;
            } else {
                amounts[i] = amountRequested[i];
            }
            
            if (amounts[i] > 0) {
                position.tokensOwed[i] = owed - amounts[i];
                TransferHelper.safeTransfer(tokens[i], recipient, amounts[i]);
            }
        }
        
        emit Collect(msg.sender, tick, recipient, amounts);
    }

    /// @inheritdoc ISphericalPoolActions
    function swap(
        address recipient,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata data
    ) external override lock returns (uint256 amountOut) {
        require(tokenIndexIn < numAssets && tokenIndexOut < numAssets, 'INVALID_TOKEN');
        require(tokenIndexIn != tokenIndexOut, 'SAME_TOKEN');
        require(amountIn > 0, 'ZERO_INPUT');
        
        // Store initial reserves
        uint256 reserveInBefore = currentReserves[tokenIndexIn];
        uint256 reserveOutBefore = currentReserves[tokenIndexOut];
        
        // Calculate swap using Newton's method
        SphericalSwapMath.SwapParams memory params = SphericalSwapMath.SwapParams({
            tokenIn: tokenIndexIn,
            tokenOut: tokenIndexOut,
            amountIn: amountIn,
            currentReserves: currentReserves,
            radiusQ96: radiusQ96,
            sqrtNumAssetsQ96: sqrtNumAssetsQ96
        });
        
        (amountOut, ) = SphericalSwapMath.calculateSwapOutput(params);
        require(amountOut >= amountOutMinimum, 'SLIPPAGE');
        
        // Apply fee
        uint256 feeAmount = FullMath.mulDiv(amountOut, fee, 1000000);
        amountOut = amountOut.sub(feeAmount);
        
        // Update reserves
        currentReserves[tokenIndexIn] = reserveInBefore.add(amountIn);
        currentReserves[tokenIndexOut] = reserveOutBefore.sub(amountOut);
        
        // Update fee growth
        if (liquidity > 0) {
            uint256 feeGrowthDelta = FullMath.mulDiv(
                feeAmount,
                FixedPoint128.Q128,
                liquidity
            );
            feeGrowthGlobalX128[tokenIndexOut] = feeGrowthGlobalX128[tokenIndexOut].add(feeGrowthDelta);
            
            // Protocol fee
            if (slot0.feeProtocol > 0) {
                uint256 protocolFeeAmount = feeAmount / slot0.feeProtocol;
                protocolFees[tokenIndexOut] = protocolFees[tokenIndexOut].add(protocolFeeAmount);
            }
        }
        
        // Transfer output tokens
        TransferHelper.safeTransfer(tokens[tokenIndexOut], recipient, amountOut);
        
        // Callback for input payment
        ISphericalSwapCallback(msg.sender).sphericalSwapCallback(tokenIndexIn, amountIn, data);
        
        // Verify payment
        uint256 balanceIn = IERC20Minimal(tokens[tokenIndexIn]).balanceOf(address(this));
        require(balanceIn >= currentReserves[tokenIndexIn], 'IIA');
        
        emit Swap(
            msg.sender,
            recipient,
            tokenIndexIn,
            tokenIndexOut,
            amountIn,
            amountOut,
            currentReserves
        );
    }

    /// @inheritdoc ISphericalPoolActions
    function flash(
        address recipient,
        uint256[] calldata amounts,
        bytes calldata data
    ) external override lock {
        require(amounts.length == numAssets, 'INVALID_LENGTH');
        
        uint256[] memory fees = new uint256[](numAssets);
        
        // Transfer requested amounts
        for (uint256 i = 0; i < numAssets; i++) {
            if (amounts[i] > 0) {
                uint256 balance = IERC20Minimal(tokens[i]).balanceOf(address(this));
                require(amounts[i] <= balance, 'INSUFFICIENT');
                
                // Calculate fee (0.05% or as configured)
                fees[i] = FullMath.mulDiv(amounts[i], fee, 1000000);
                
                TransferHelper.safeTransfer(tokens[i], recipient, amounts[i]);
            }
        }
        
        // Callback
        ISphericalFlashCallback(msg.sender).sphericalFlashCallback(fees, data);
        
        // Verify repayment with fees
        for (uint256 i = 0; i < numAssets; i++) {
            if (amounts[i] > 0) {
                uint256 balance = IERC20Minimal(tokens[i]).balanceOf(address(this));
                require(
                    balance >= currentReserves[i].add(fees[i]),
                    'FLASH_NOT_PAID'
                );
                
                currentReserves[i] = balance;
                
                // Update fee growth
                if (liquidity > 0 && fees[i] > 0) {
                    uint256 feeGrowthDelta = FullMath.mulDiv(
                        fees[i],
                        FixedPoint128.Q128,
                        liquidity
                    );
                    feeGrowthGlobalX128[i] = feeGrowthGlobalX128[i].add(feeGrowthDelta);
                }
            }
        }
        
        emit Flash(msg.sender, recipient, amounts, fees);
    }

    /// @inheritdoc ISphericalPoolOwnerActions
    function setFeeProtocol(uint8 _feeProtocol) external override onlyFactoryOwner {
        require(_feeProtocol == 0 || (_feeProtocol >= 4 && _feeProtocol <= 10), 'FP');
        uint8 oldFeeProtocol = slot0.feeProtocol;
        slot0.feeProtocol = _feeProtocol;
        emit SetFeeProtocol(oldFeeProtocol, _feeProtocol);
    }

    /// @inheritdoc ISphericalPoolOwnerActions
    function collectProtocol(
        address recipient,
        uint128[] calldata amountRequested
    ) external override onlyFactoryOwner returns (uint128[] memory amounts) {
        require(amountRequested.length == numAssets, 'INVALID_LENGTH');
        
        amounts = new uint128[](numAssets);
        
        for (uint256 i = 0; i < numAssets; i++) {
            uint256 protocolFee = protocolFees[i];
            uint128 amount = amountRequested[i] > protocolFee ? uint128(protocolFee) : amountRequested[i];
            
            if (amount > 0) {
                amounts[i] = amount;
                protocolFees[i] = protocolFee - amount;
                TransferHelper.safeTransfer(tokens[i], recipient, amount);
            }
        }
        
        emit CollectProtocol(msg.sender, recipient, amounts);
    }

    /// @dev Add a tick to the active ticks array
    function _addActiveTick(int24 tick) private {
        activeTicks.push(tick);
    }

    /// @dev Remove a tick from the active ticks array
    function _removeActiveTick(int24 tick) private {
        for (uint256 i = 0; i < activeTicks.length; i++) {
            if (activeTicks[i] == tick) {
                activeTicks[i] = activeTicks[activeTicks.length - 1];
                activeTicks.pop();
                break;
            }
        }
    }

    /// @inheritdoc ISphericalPoolState
    function getActiveTickCount() external view override returns (uint256) {
        return activeTicks.length;
    }

    /// @inheritdoc ISphericalPoolState
    function getActiveTick(uint256 index) external view override returns (int24) {
        require(index < activeTicks.length, 'INDEX');
        return activeTicks[index];
    }

    /// @inheritdoc ISphericalPoolState
    function positionTokensOwed(int24 tick) external view override returns (uint128[] memory) {
        return positions[tick].tokensOwed;
    }

    /// @notice Get a specific token address
    function getToken(uint256 index) external view returns (address) {
        require(index < numAssets, 'INDEX');
        return tokens[index];
    }
}