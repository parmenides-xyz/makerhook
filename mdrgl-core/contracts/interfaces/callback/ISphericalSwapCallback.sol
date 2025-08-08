// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Callback for ISphericalPoolActions#swap
/// @notice Any contract that calls ISphericalPoolActions#swap must implement this interface
interface ISphericalSwapCallback {
    /// @notice Called to `msg.sender` after executing a swap
    /// @dev In the implementation you must pay the pool the input token owed for the swap.
    /// The caller of this method must be checked to be a SphericalPool deployed by the canonical SphericalFactory.
    /// @param tokenIndexIn The index of the input token
    /// @param amountIn The amount of input token owed to the pool
    /// @param data Any data passed through by the caller via the ISphericalPoolActions#swap call
    function sphericalSwapCallback(
        uint256 tokenIndexIn,
        uint256 amountIn,
        bytes calldata data
    ) external;
}