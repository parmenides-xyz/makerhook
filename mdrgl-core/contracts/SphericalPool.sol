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
import './libraries/SphericalOracle.sol';
import './libraries/SphericalMath.sol';
import './libraries/FullMath.sol';
import './libraries/FixedPoint96.sol';
import './libraries/FixedPoint128.sol';
import './libraries/TransferHelper.sol';
import './NoDelegateCall.sol';

contract SphericalPool is ISphericalPool, NoDelegateCall {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SphericalTick for mapping(int24 => SphericalTick.Info);
    using SphericalPosition for mapping(int24 => SphericalPosition.Info);
    using SphericalOracle for SphericalOracle.Observation[65535];

    /// @notice The factory that deployed this pool
    address public immutable override factory;
    /// @dev Token addresses array
    address[] internal _tokens;
    /// @notice The pool's fee in hundredths of a bip
    uint24 public immutable override fee;
    /// @notice The pool's tick spacing
    int24 public immutable override tickSpacing;
    /// @notice The maximum liquidity per tick
    uint128 public immutable override maxLiquidityPerTick;
    /// @notice The number of assets in the pool
    uint256 public immutable override numAssets;
    /// @notice The pool's sphere radius in Q96 format
    uint256 public immutable override radiusQ96;
    /// @notice Square root of number of assets in Q96 format
    uint256 public immutable override sqrtNumAssetsQ96;

    struct Slot0 {
        // Current consolidated radius from interior ticks
        uint256 radiusInteriorQ96;
        // Current consolidated orthogonal radius from boundary ticks
        uint256 radiusBoundaryQ96;
        // Current consolidated k from boundary ticks
        uint256 kBoundaryQ96;
        // Whether the pool is initialized
        bool initialized;
        // The current protocol fee
        uint8 feeProtocol;
        // Whether the pool is locked
        bool unlocked;
    }

    /// @notice The pool's slot0 storage
    Slot0 public override slot0;

    /// @dev Current reserve amounts for each token
    uint256[] public currentReserves;
    
    /// @dev Fee growth per unit of liquidity for each token
    uint256[] internal _feeGrowthGlobalX128;

    /// @notice The pool's current liquidity
    uint128 public override liquidity;

    /// @dev Tick info by tick index
    mapping(int24 => SphericalTick.Info) internal _tickInfo;
    
    /// @dev Position info by tick index (single owner per tick)
    mapping(int24 => SphericalPosition.Info) public positions;

    /// @dev Mapping to track if a tick is active
    mapping(int24 => bool) public activeTicksMap;
    
    /// @dev Linked list of active ticks for iteration
    mapping(int24 => int24) public nextActiveTick;
    int24 public firstActiveTick = type(int24).max; // Sentinel value for empty list
    int24 public lastActiveTick;
    uint256 public activeTickCount;

    /// @dev Accumulated protocol fees per token
    uint256[] public protocolFees;

    /// @notice Oracle observations for tracking alpha over time
    SphericalOracle.Observation[65535] public override observations;
    
    /// @dev Current observation state
    uint16 public observationIndex;
    uint16 public observationCardinality;
    uint16 public observationCardinalityNext;

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
        address[] memory __tokens;
        int24 _tickSpacing;
        (factory, __tokens, fee, _tickSpacing, radiusQ96) = ISphericalPoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;
        
        _tokens = __tokens;
        uint256 _numAssets = __tokens.length;
        require(_numAssets >= 2, 'MIN_ASSETS');
        numAssets = _numAssets;
        
        // Calculate sqrt(n) in Q96 format
        sqrtNumAssetsQ96 = SphericalMath.sqrt(_numAssets * FixedPoint96.Q96);
        
        maxLiquidityPerTick = SphericalTick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
        
        // Initialize arrays
        currentReserves = new uint256[](_numAssets);
        _feeGrowthGlobalX128 = new uint256[](_numAssets);
        protocolFees = new uint256[](_numAssets);
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
        uint256 actualRadius = SphericalMath.sqrt(sumSquares);
        require(
            actualRadius >= radiusQ96.mul(99) / 100 && 
            actualRadius <= radiusQ96.mul(101) / 100,
            'OFF_SPHERE'
        );
        
        slot0.initialized = true;
        slot0.unlocked = true;
        
        // Calculate initial alpha (projection onto equal-price vector)
        uint256 alphaQ96 = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            alphaQ96 = alphaQ96.add(initialReserves[i]);
        }
        alphaQ96 = alphaQ96.mul(FixedPoint96.Q96) / numAssets;
        
        // Initialize oracle
        (observationCardinality, observationCardinalityNext) = observations.initialize(uint32(block.timestamp));
        observationIndex = 0;
        
        emit Initialize(initialReserves, alphaQ96);
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
        
        // Ensure single owner per tick
        if (position.owner == address(0)) {
            SphericalPosition.initialize(position, msg.sender, numAssets);
        } else {
            require(position.owner == msg.sender, 'NOT_OWNER');
        }
        
        // Update tick
        bool flipped = _tickInfo.update(
            tick,
            0, // Not used for spherical AMM
            int128(_liquidity),
            _feeGrowthGlobalX128,
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
            
            SphericalTick.initializeGeometry(_tickInfo[tick], tick, radiusQ96, geometry);
            
            // Initialize alpha tracking for this tick
            uint256 currentAlphaQ96 = 0;
            for (uint256 i = 0; i < numAssets; i++) {
                currentAlphaQ96 = currentAlphaQ96.add(currentReserves[i]);
            }
            currentAlphaQ96 = currentAlphaQ96.mul(FixedPoint96.Q96) / numAssets;
            
            (uint256 globalAlphaCumulative, ) = observations.observeSingle(
                uint32(block.timestamp),
                0,
                currentAlphaQ96,
                observationIndex,
                liquidity,
                observationCardinality
            );
            
            _tickInfo[tick].alphaCumulativeLastQ96 = globalAlphaCumulative;
            _tickInfo[tick].timestampLast = uint32(block.timestamp);
        }
        
        liquidity = uint128(uint256(liquidity).add(_liquidity));
        
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
            uint256 balance = IERC20Minimal(_tokens[i]).balanceOf(address(this));
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
        
        SphericalTick.Info storage tickData = _tickInfo[tick];
        require(tickData.liquidityGross >= _liquidity, 'INSUFFICIENT');
        
        // Update tick
        bool flipped = _tickInfo.update(
            tick,
            0, // Not used
            -int128(_liquidity),
            _feeGrowthGlobalX128,
            0, // secondsPerLiquidityCumulativeX128
            0, // tickCumulative
            uint32(block.timestamp),
            false, // upper
            maxLiquidityPerTick,
            numAssets
        );
        
        if (flipped) {
            _removeActiveTick(tick);
            _tickInfo.clear(tick, numAssets);
        }
        
        liquidity = uint128(uint256(liquidity).sub(_liquidity));
        
        // Calculate amounts to return
        amounts = new uint256[](numAssets);
        for (uint256 i = 0; i < numAssets; i++) {
            amounts[i] = FullMath.mulDiv(
                currentReserves[i],
                _liquidity,
                uint256(liquidity).add(_liquidity)
            );
            
            // Transfer tokens
            if (amounts[i] > 0) {
                currentReserves[i] = currentReserves[i].sub(amounts[i]);
                TransferHelper.safeTransfer(_tokens[i], msg.sender, amounts[i]);
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
                TransferHelper.safeTransfer(_tokens[i], recipient, amounts[i]);
            }
        }
        
        emit Collect(msg.sender, recipient, tick, amounts);
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
        
        {
            // Calculate swap using Newton's method
            // First calculate sums
            uint256 _sumReservesQ96 = 0;
            uint256 _sumSquaresQ96 = 0;
            for (uint256 i = 0; i < numAssets; i++) {
                _sumReservesQ96 = _sumReservesQ96.add(currentReserves[i].mul(FixedPoint96.Q96));
                uint256 squared = FullMath.mulDiv(
                    currentReserves[i],
                    currentReserves[i],
                    FixedPoint96.Q96
                );
                _sumSquaresQ96 = _sumSquaresQ96.add(squared);
            }
            
            SphericalSwapMath.SwapParams memory params = SphericalSwapMath.SwapParams({
                tokenIn: tokenIndexIn,
                tokenOut: tokenIndexOut,
                amountIn: amountIn,
                currentReserves: currentReserves,
                sumReservesQ96: _sumReservesQ96,
                sumSquaresQ96: _sumSquaresQ96,
                poolConstants: SphericalMath.PoolConstants({
                    radiusQ96: radiusQ96,
                    numAssets: numAssets,
                    sqrtNumAssetsQ96: sqrtNumAssetsQ96,
                    epsilonQ96: FixedPoint96.Q96 / 1000 // 0.1% tolerance
                }),
                feePips: fee,
                radiusInteriorQ96: slot0.radiusInteriorQ96,
                radiusBoundaryQ96: slot0.radiusBoundaryQ96,
                kBoundaryQ96: slot0.kBoundaryQ96
            });
            
            uint256 rawAmountOut;
            (rawAmountOut, ) = SphericalSwapMath.calculateSwapOutput(params);
            require(rawAmountOut >= amountOutMinimum, 'SLIPPAGE');
            
            // Apply fee
            uint256 feeAmount = FullMath.mulDiv(rawAmountOut, fee, 1000000);
            amountOut = rawAmountOut.sub(feeAmount);
            
            // Update reserves
            currentReserves[tokenIndexIn] = currentReserves[tokenIndexIn].add(amountIn);
            currentReserves[tokenIndexOut] = currentReserves[tokenIndexOut].sub(amountOut);
            
            // Update fee growth
            if (liquidity > 0) {
                _feeGrowthGlobalX128[tokenIndexOut] = _feeGrowthGlobalX128[tokenIndexOut].add(
                    FullMath.mulDiv(
                        feeAmount,
                        FixedPoint128.Q128,
                        liquidity
                    )
                );
                
                // Protocol fee
                if (slot0.feeProtocol > 0) {
                    protocolFees[tokenIndexOut] = protocolFees[tokenIndexOut].add(feeAmount / slot0.feeProtocol);
                }
            }
        }
        
        // Transfer output tokens
        TransferHelper.safeTransfer(_tokens[tokenIndexOut], recipient, amountOut);
        
        // Callback for input payment
        ISphericalSwapCallback(msg.sender).sphericalSwapCallback(tokenIndexIn, amountIn, data);
        
        // Verify payment
        require(
            IERC20Minimal(_tokens[tokenIndexIn]).balanceOf(address(this)) >= currentReserves[tokenIndexIn],
            'IIA'
        );
        
        // Calculate final alpha (projection onto equal-price vector)
        uint256 alphaQ96 = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            alphaQ96 = alphaQ96.add(currentReserves[i]);
        }
        alphaQ96 = alphaQ96.mul(FixedPoint96.Q96) / numAssets;
        
        // Write oracle observation
        (observationIndex, observationCardinality) = observations.write(
            observationIndex,
            uint32(block.timestamp),
            alphaQ96,
            liquidity,
            observationCardinality,
            observationCardinalityNext
        );
        
        emit Swap(
            msg.sender,
            recipient,
            tokenIndexIn,
            tokenIndexOut,
            amountIn,
            amountOut,
            alphaQ96
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
                uint256 balance = IERC20Minimal(_tokens[i]).balanceOf(address(this));
                require(amounts[i] <= balance, 'INSUFFICIENT');
                
                // Calculate fee (0.05% or as configured)
                fees[i] = FullMath.mulDiv(amounts[i], fee, 1000000);
                
                TransferHelper.safeTransfer(_tokens[i], recipient, amounts[i]);
            }
        }
        
        // Callback
        ISphericalFlashCallback(msg.sender).sphericalFlashCallback(fees, data);
        
        // Verify repayment with fees
        for (uint256 i = 0; i < numAssets; i++) {
            if (amounts[i] > 0) {
                uint256 balance = IERC20Minimal(_tokens[i]).balanceOf(address(this));
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
                    _feeGrowthGlobalX128[i] = _feeGrowthGlobalX128[i].add(feeGrowthDelta);
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
                TransferHelper.safeTransfer(_tokens[i], recipient, amount);
            }
        }
        
        emit CollectProtocol(msg.sender, recipient, amounts);
    }

    /// @dev Add a tick to the active ticks linked list for O(1) insertion
    function _addActiveTick(int24 tick) private {
        require(!activeTicksMap[tick], 'TICK_ALREADY_ACTIVE');
        
        activeTicksMap[tick] = true;
        activeTickCount++;
        
        if (firstActiveTick == type(int24).max) {
            // First tick being added
            firstActiveTick = tick;
            lastActiveTick = tick;
            nextActiveTick[tick] = type(int24).max; // Sentinel for end of list
        } else {
            // Add to end of list
            nextActiveTick[lastActiveTick] = tick;
            nextActiveTick[tick] = type(int24).max;
            lastActiveTick = tick;
        }
    }

    /// @dev Remove a tick from the active ticks linked list with O(n) search
    function _removeActiveTick(int24 tick) private {
        require(activeTicksMap[tick], 'TICK_NOT_ACTIVE');
        
        activeTicksMap[tick] = false;
        activeTickCount--;
        
        if (firstActiveTick == tick) {
            // Removing first element
            firstActiveTick = nextActiveTick[tick];
            if (firstActiveTick == type(int24).max) {
                // List is now empty
                lastActiveTick = 0;
            }
        } else {
            // Find previous tick
            int24 current = firstActiveTick;
            while (nextActiveTick[current] != tick) {
                current = nextActiveTick[current];
                require(current != type(int24).max, 'TICK_NOT_FOUND');
            }
            
            // Remove from list
            nextActiveTick[current] = nextActiveTick[tick];
            
            if (lastActiveTick == tick) {
                lastActiveTick = current;
            }
        }
        
        delete nextActiveTick[tick];
    }

    /// @notice Get the number of active ticks
    function getActiveTickCount() external view returns (uint256) {
        return activeTickCount;
    }

    /// @notice Check if a tick is active in O(1) time
    function isTickActive(int24 tick) external view returns (bool) {
        return activeTicksMap[tick];
    }

    /// @inheritdoc ISphericalPoolState
    function positionTokensOwed(int24 tick) external view override returns (uint128[] memory) {
        return positions[tick].tokensOwed;
    }

    /// @inheritdoc ISphericalPoolImmutables
    function getToken(uint256 index) external view override returns (address) {
        require(index < numAssets, 'INDEX');
        return _tokens[index];
    }

    /// @inheritdoc ISphericalPoolImmutables
    function tokens() external view override returns (address[] memory) {
        return _tokens;
    }

    /// @inheritdoc ISphericalPoolState
    function getReserves() external view override returns (uint256[] memory) {
        return currentReserves;
    }

    /// @inheritdoc ISphericalPoolState
    function getReserve(uint256 tokenIndex) external view override returns (uint256) {
        require(tokenIndex < numAssets, 'INDEX');
        return currentReserves[tokenIndex];
    }

    /// @inheritdoc ISphericalPoolState
    function feeGrowthGlobalX128() external view override returns (uint256[] memory) {
        return _feeGrowthGlobalX128;
    }

    /// @inheritdoc ISphericalPoolState
    function getActiveTicks() external view override returns (int24[] memory) {
        int24[] memory ticks = new int24[](activeTickCount);
        
        if (activeTickCount == 0) {
            return ticks;
        }
        
        int24 current = firstActiveTick;
        uint256 index = 0;
        
        while (current != type(int24).max && index < activeTickCount) {
            ticks[index] = current;
            current = nextActiveTick[current];
            index++;
        }
        
        return ticks;
    }

    /// @inheritdoc ISphericalPoolState
    function sumReservesQ96() external view override returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            sum = sum.add(currentReserves[i]);
        }
        return sum.mul(FixedPoint96.Q96) / numAssets;
    }

    /// @inheritdoc ISphericalPoolState
    function sumSquaresQ96() external view override returns (uint256) {
        uint256 sumSquares = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            uint256 squared = FullMath.mulDiv(
                currentReserves[i],
                currentReserves[i],
                FixedPoint96.Q96
            );
            sumSquares = sumSquares.add(squared);
        }
        return sumSquares;
    }

    /// @inheritdoc ISphericalPoolState
    function consolidatedTickParams()
        external
        view
        override
        returns (
            uint256 radiusInteriorQ96,
            uint256 radiusBoundaryQ96,
            uint256 kBoundaryQ96
        )
    {
        // Return current consolidated values from slot0
        // These are updated when ticks change state
        radiusInteriorQ96 = slot0.radiusInteriorQ96;
        radiusBoundaryQ96 = slot0.radiusBoundaryQ96;
        kBoundaryQ96 = slot0.kBoundaryQ96;
    }

    // observations() getter is auto-generated from public state variable

    /// @inheritdoc ISphericalPoolState
    function tickInfo(int24 tick)
        external
        view
        override
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            bool isAtBoundary,
            address owner
        )
    {
        SphericalTick.Info storage info = _tickInfo[tick];
        SphericalPosition.Info storage position = positions[tick];
        return (
            info.liquidityGross,
            info.liquidityNet,
            info.isAtBoundary,
            position.owner
        );
    }

    /// @inheritdoc ISphericalPoolActions
    function increaseObservationCardinalityNext(uint16 _observationCardinalityNext) external override lock {
        uint16 observationCardinalityNextOld = observationCardinalityNext;
        uint16 observationCardinalityNextNew = observations.grow(
            observationCardinalityNextOld,
            _observationCardinalityNext
        );
        observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew) {
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
        }
    }
    
    /// @inheritdoc ISphericalPoolState
    /// @param secondsAgos From how long ago each cumulative value should be returned
    /// @return alphaCumulatives The cumulative alpha values
    /// @return secondsPerLiquidityCumulativeX128s The cumulative seconds per liquidity values
    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        returns (uint256[] memory alphaCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        // Calculate current alpha (projection onto equal-price vector)
        uint256 alphaQ96 = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            alphaQ96 = alphaQ96.add(currentReserves[i]);
        }
        alphaQ96 = alphaQ96.mul(FixedPoint96.Q96) / numAssets;
        
        return
            observations.observe(
                uint32(block.timestamp),
                secondsAgos,
                alphaQ96,
                observationIndex,
                liquidity,
                observationCardinality
            );
    }
    
    /// @inheritdoc ISphericalPoolState
    /// @dev Since Orbital uses single-tick positions, this returns values for a specific tick
    /// @param tick The tick to get the snapshot for
    /// @return alphaCumulative The cumulative alpha value at the tick
    /// @return secondsPerLiquidityInsideX128 The seconds per liquidity for the tick
    /// @return secondsInside The seconds the tick has been active
    function snapshotCumulativesInside(int24 tick)
        external
        view
        override
        returns (
            uint256 alphaCumulative,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        SphericalTick.Info storage info = _tickInfo[tick];
        
        if (!activeTicksMap[tick]) {
            // Tick is not active
            return (0, 0, 0);
        }
        
        // Calculate current global alpha (average of reserves in Q96)
        uint256 sumReserves = 0;
        for (uint256 i = 0; i < numAssets; i++) {
            sumReserves = sumReserves.add(currentReserves[i]);
        }
        uint256 currentAlphaQ96 = sumReserves.mul(FixedPoint96.Q96) / numAssets;
        
        // Get current global cumulative from oracle
        (uint256 globalAlphaCumulative, ) = observations.observeSingle(
            uint32(block.timestamp),
            0, // current time
            currentAlphaQ96,
            observationIndex,
            liquidity,
            observationCardinality
        );
        
        // Calculate tick's contribution since last update
        uint32 timeDelta = uint32(block.timestamp) - info.timestampLast;
        if (timeDelta > 0 && info.liquidityGross > 0) {
            // Tick's alpha contribution is proportional to its liquidity share
            uint256 tickAlphaContribution = FullMath.mulDiv(
                globalAlphaCumulative - info.alphaCumulativeLastQ96,
                info.liquidityGross,
                liquidity > 0 ? liquidity : 1
            );
            alphaCumulative = info.alphaCumulativeLastQ96 + tickAlphaContribution;
        } else {
            alphaCumulative = info.alphaCumulativeLastQ96;
        }
        
        secondsPerLiquidityInsideX128 = info.secondsPerLiquidityOutsideX128;
        secondsInside = uint32(block.timestamp) - info.secondsOutside;
        
        return (alphaCumulative, secondsPerLiquidityInsideX128, secondsInside);
    }

    /// @inheritdoc ISphericalPoolActions
    function updateConsolidatedTickParams() external override {
        uint256 newRadiusInteriorQ96 = 0;
        uint256 newRadiusBoundaryQ96 = 0;
        uint256 newKBoundaryQ96 = 0;
        
        // Recalculate from all active ticks using linked list
        if (activeTickCount > 0) {
            int24 current = firstActiveTick;
            
            while (current != type(int24).max) {
                SphericalTick.Info storage info = _tickInfo[current];
                
                if (info.isAtBoundary) {
                    newKBoundaryQ96 = newKBoundaryQ96.add(info.kQ96);
                    // Calculate orthogonal radius component for boundary ticks
                    uint256 orthogonalRadius = SphericalTickMath.getOrthogonalRadius(
                        info.kQ96,
                        radiusQ96,
                        sqrtNumAssetsQ96
                    );
                    newRadiusBoundaryQ96 = newRadiusBoundaryQ96.add(orthogonalRadius);
                } else {
                    newRadiusInteriorQ96 = newRadiusInteriorQ96.add(info.radiusQ96);
                }
                
                current = nextActiveTick[current];
            }
        }
        
        slot0.radiusInteriorQ96 = newRadiusInteriorQ96;
        slot0.radiusBoundaryQ96 = newRadiusBoundaryQ96;
        slot0.kBoundaryQ96 = newKBoundaryQ96;
    }
}