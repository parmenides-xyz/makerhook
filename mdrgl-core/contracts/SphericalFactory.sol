// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/ISphericalFactory.sol';
import './SphericalPoolDeployer.sol';
import './NoDelegateCall.sol';
import './SphericalPool.sol';

/// @title Canonical Spherical AMM factory
/// @notice Deploys Spherical AMM pools and manages ownership and control over pool protocol fees
contract SphericalFactory is ISphericalFactory, SphericalPoolDeployer, NoDelegateCall {
    /// @inheritdoc ISphericalFactory
    address public override owner;

    /// @inheritdoc ISphericalFactory
    address public override feeProtocolSetter;

    /// @inheritdoc ISphericalFactory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    
    /// @dev Nested mapping to support n-dimensional pools
    /// Hash of sorted tokens => fee => pool address
    mapping(bytes32 => mapping(uint24 => address)) public poolByTokensAndFee;

    constructor() {
        owner = msg.sender;
        feeProtocolSetter = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
        emit FeeProtocolSetterChanged(address(0), msg.sender);

        // Initialize default fee tiers for stablecoin pools
        feeAmountTickSpacing[100] = 1;   // 0.01% fee, tick spacing 1 for tight ranges
        emit FeeAmountEnabled(100, 1);
        feeAmountTickSpacing[500] = 10;  // 0.05% fee
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60; // 0.30% fee
        emit FeeAmountEnabled(3000, 60);
    }

    /// @inheritdoc ISphericalFactory
    function getPool(
        address[] calldata tokens,
        uint24 fee
    ) external view override returns (address pool) {
        require(tokens.length >= 2, 'MIN_TOKENS');
        address[] memory sortedTokens = _sortTokens(tokens);
        bytes32 key = keccak256(abi.encode(sortedTokens));
        return poolByTokensAndFee[key][fee];
    }

    /// @inheritdoc ISphericalFactory
    function createPool(
        address[] calldata tokens,
        uint24 fee,
        uint256 radiusQ96
    ) external override noDelegateCall returns (address pool) {
        require(tokens.length >= 2 && tokens.length <= 8, 'INVALID_TOKEN_COUNT');
        require(radiusQ96 > 0, 'INVALID_RADIUS');
        
        // Sort tokens
        address[] memory sortedTokens = _sortTokens(tokens);
        
        // Verify no duplicates and no zero addresses
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            require(sortedTokens[i] != address(0), 'ZERO_ADDRESS');
            if (i > 0) {
                require(sortedTokens[i] > sortedTokens[i-1], 'DUPLICATE_TOKEN');
            }
        }
        
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0, 'INVALID_FEE');
        
        bytes32 key = keccak256(abi.encode(sortedTokens));
        require(poolByTokensAndFee[key][fee] == address(0), 'POOL_EXISTS');
        
        pool = deploy(address(this), sortedTokens, fee, tickSpacing, radiusQ96);
        poolByTokensAndFee[key][fee] = pool;
        
        emit PoolCreated(sortedTokens, fee, tickSpacing, pool);
    }

    /// @inheritdoc ISphericalFactory
    function setOwner(address _owner) external override {
        require(msg.sender == owner, 'FORBIDDEN');
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc ISphericalFactory
    function setFeeProtocolSetter(address _feeProtocolSetter) external override {
        require(msg.sender == owner, 'FORBIDDEN');
        emit FeeProtocolSetterChanged(feeProtocolSetter, _feeProtocolSetter);
        feeProtocolSetter = _feeProtocolSetter;
    }

    /// @inheritdoc ISphericalFactory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external override {
        require(msg.sender == owner, 'FORBIDDEN');
        require(fee < 1000000, 'FEE_TOO_LARGE');
        require(tickSpacing > 0 && tickSpacing < 16384, 'TICK_SPACING');
        require(feeAmountTickSpacing[fee] == 0, 'FEE_ENABLED');

        feeAmountTickSpacing[fee] = tickSpacing;
        emit FeeAmountEnabled(fee, tickSpacing);
    }

    /// @inheritdoc ISphericalFactory
    function setPoolFeeProtocol(address pool, uint8 feeProtocol) external override {
        require(msg.sender == feeProtocolSetter, 'FORBIDDEN');
        ISphericalPool(pool).setFeeProtocol(feeProtocol);
    }

    /// @inheritdoc ISphericalFactory
    function parameters()
        external
        view
        override
        returns (
            address factory,
            address[] memory tokens,
            uint24 fee,
            int24 tickSpacing,
            uint256 radiusQ96
        )
    {
        Parameters memory params = parameters;
        return (
            params.factory,
            params.tokens,
            params.fee,
            params.tickSpacing,
            params.radiusQ96
        );
    }

    /// @dev Sort an array of token addresses
    function _sortTokens(address[] calldata tokens) private pure returns (address[] memory sorted) {
        sorted = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            sorted[i] = tokens[i];
        }
        
        // Bubble sort for simplicity (pools have max 8 tokens)
        for (uint256 i = 0; i < sorted.length - 1; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (sorted[i] > sorted[j]) {
                    address temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }
    }
}