// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title An interface for a contract that is capable of deploying Spherical AMM Pools
/// @notice A contract that constructs pools must implement this to pass arguments to the pool
interface ISphericalPoolDeployer {
    /// @notice Get the parameters to be used in constructing the pool
    /// @dev Called by the pool constructor to fetch the parameters
    /// @return factory The factory address
    /// @return tokens The tokens in the pool
    /// @return fee The fee tier
    /// @return tickSpacing The tick spacing
    /// @return radiusQ96 The sphere radius in Q96 format
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