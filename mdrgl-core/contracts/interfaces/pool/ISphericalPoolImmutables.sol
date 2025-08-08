// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Pool state that never changes
/// @notice These parameters are fixed for a spherical AMM pool forever
interface ISphericalPoolImmutables {
    /// @notice The contract that deployed the pool
    /// @return The factory contract address
    function factory() external view returns (address);

    /// @notice The tokens in the pool
    /// @return tokens Array of token addresses in the pool
    function tokens() external view returns (address[] memory);
    
    /// @notice Get a specific token address by index
    /// @param index The index of the token
    /// @return The token address at the given index
    function getToken(uint256 index) external view returns (address);

    /// @notice The number of assets in the pool
    /// @return The number of tokens
    function numAssets() external view returns (uint256);

    /// @notice The pool's fee in hundredths of a bip, i.e. 1e-6
    /// @return The fee
    function fee() external view returns (uint24);

    /// @notice The pool tick spacing
    /// @dev Fixed at 1 for maximum precision in stablecoin pools
    /// @return The tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice The radius of the n-dimensional sphere in Q96 format
    /// @dev This defines the total liquidity geometry
    /// @return The sphere radius in Q96
    function radiusQ96() external view returns (uint256);

    /// @notice The square root of the number of assets in Q96 format
    /// @dev Pre-computed for gas efficiency
    /// @return sqrt(n) in Q96 format
    function sqrtNumAssetsQ96() external view returns (uint256);

    /// @notice The maximum amount of liquidity that can use any tick
    /// @dev Prevents liquidity overflow at any single tick
    /// @return The max liquidity per tick
    function maxLiquidityPerTick() external view returns (uint128);
}