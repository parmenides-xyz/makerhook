// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/ISphericalPoolDeployer.sol';
import './SphericalPool.sol';

contract SphericalPoolDeployer is ISphericalPoolDeployer {
    struct Parameters {
        address factory;
        address[] tokens;
        uint24 fee;
        int24 tickSpacing;
        uint256 radiusQ96;
    }

    /// @inheritdoc ISphericalPoolDeployer
    Parameters public override parameters;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Spherical factory
    /// @param tokens The sorted array of token addresses for the pool
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    /// @param radiusQ96 The initial sphere radius in Q96 format
    function deploy(
        address factory,
        address[] memory tokens,
        uint24 fee,
        int24 tickSpacing,
        uint256 radiusQ96
    ) internal returns (address pool) {
        parameters = Parameters({
            factory: factory,
            tokens: tokens,
            fee: fee,
            tickSpacing: tickSpacing,
            radiusQ96: radiusQ96
        });
        
        // Create deterministic salt from tokens and fee
        bytes32 salt = keccak256(abi.encode(tokens, fee));
        pool = address(new SphericalPool{salt: salt}());
        delete parameters;
    }
}