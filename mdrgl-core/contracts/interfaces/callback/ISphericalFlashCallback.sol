// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Callback for ISphericalPoolActions#flash
/// @notice Any contract that calls ISphericalPoolActions#flash must implement this interface
interface ISphericalFlashCallback {
    /// @notice Called to `msg.sender` after transferring tokens for flash loan
    /// @dev In the implementation you must repay the pool the tokens plus fees.
    /// The caller of this method must be checked to be a SphericalPool deployed by the canonical SphericalFactory.
    /// @param fees The fees for each token owed to the pool
    /// @param data Any data passed through by the caller via the ISphericalPoolActions#flash call
    function sphericalFlashCallback(
        uint256[] calldata fees,
        bytes calldata data
    ) external;
}