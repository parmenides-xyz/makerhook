// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title The interface for the Spherical AMM Factory
/// @notice The factory facilitates creation of Spherical AMM pools and control over protocol fees
interface ISphericalFactory {
    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the change
    /// @param newOwner The owner after the change
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /// @notice Emitted when a pool is created
    /// @param tokens The tokens in the pool (sorted)
    /// @param fee The fee collected upon every swap in the pool
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    /// @param pool The address of the created pool
    event PoolCreated(
        address[] tokens,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    /// @notice Emitted when a new fee amount is enabled for pool creation
    /// @param fee The enabled fee
    /// @param tickSpacing The minimum number of ticks between initialized ticks
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    /// @notice Emitted when the protocol fee setter is changed
    /// @param oldFeeProtocolSetter The previous setter
    /// @param newFeeProtocolSetter The new setter
    event FeeProtocolSetterChanged(address indexed oldFeeProtocolSetter, address indexed newFeeProtocolSetter);

    /// @notice Returns the current owner of the factory
    /// @return The address of the factory owner
    function owner() external view returns (address);

    /// @notice Returns the address allowed to set protocol fees
    /// @return The address of the fee protocol setter
    function feeProtocolSetter() external view returns (address);

    /// @notice Returns the tick spacing for a given fee amount
    /// @param fee The fee amount
    /// @return The tick spacing
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    /// @notice Returns the pool address for a given set of tokens and fee
    /// @dev The tokens array should be sorted by address
    /// @param tokens The array of token addresses
    /// @param fee The fee tier
    /// @return pool The pool address (or address(0) if not deployed)
    function getPool(
        address[] calldata tokens,
        uint24 fee
    ) external view returns (address pool);

    /// @notice Creates a pool for the given tokens and fee
    /// @dev The tokens will be automatically sorted by address
    /// @param tokens Array of token addresses for the pool
    /// @param fee The desired fee for the pool
    /// @param radiusQ96 The initial sphere radius in Q96 format
    /// @return pool The address of the newly created pool
    function createPool(
        address[] calldata tokens,
        uint24 fee,
        uint256 radiusQ96
    ) external returns (address pool);

    /// @notice Updates the owner of the factory
    /// @dev Must be called by the current owner
    /// @param _owner The new owner
    function setOwner(address _owner) external;

    /// @notice Updates the protocol fee setter
    /// @dev Must be called by the current owner
    /// @param _feeProtocolSetter The new protocol fee setter
    function setFeeProtocolSetter(address _feeProtocolSetter) external;

    /// @notice Enables a fee amount with the given tick spacing
    /// @dev Fee amounts may never be removed once enabled
    /// @param fee The fee amount to enable
    /// @param tickSpacing The spacing between ticks
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;

    /// @notice Sets the protocol fee for a specific pool
    /// @dev Can only be called by the fee protocol setter
    /// @param pool The pool address
    /// @param feeProtocol The new protocol fee
    function setPoolFeeProtocol(address pool, uint8 feeProtocol) external;

    /// @notice Returns parameters needed for pool deployment
    /// @dev Used by the pool deployer contract
    /// @return factory The factory address
    /// @return tokens The tokens for the pool
    /// @return fee The fee tier
    /// @return tickSpacing The tick spacing
    /// @return radiusQ96 The sphere radius
    function parameters()
        external
        view
        returns (
            address factory,
            address[] memory tokens,
            uint24 fee,
            int24 tickSpacing,
            uint256 radiusQ96
        );
}