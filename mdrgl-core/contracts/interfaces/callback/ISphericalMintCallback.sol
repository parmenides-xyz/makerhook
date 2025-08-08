// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Callback for ISphericalPoolActions#mint
/// @notice Any contract that calls ISphericalPoolActions#mint must implement this interface
interface ISphericalMintCallback {
    /// @notice Called to `msg.sender` after minting liquidity to a tick
    /// @dev In the implementation you must pay the pool tokens owed for the minted liquidity.
    /// The caller of this method must be checked to be a SphericalPool deployed by the canonical SphericalFactory.
    /// @param amounts The amounts of each token owed to the pool for the minted liquidity
    /// @param data Any data passed through by the caller via the ISphericalPoolActions#mint call
    function sphericalMintCallback(
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}