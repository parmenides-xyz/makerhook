// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Permissioned pool actions
/// @notice Contains pool methods that may only be called by the factory owner
interface ISphericalPoolOwnerActions {
    /// @notice Set the protocol fee
    /// @dev Can only be called by the factory owner
    /// @param feeProtocol The new protocol fee in basis points (max 100 = 1%)
    function setFeeProtocol(uint8 feeProtocol) external;

    /// @notice Collect the protocol fee accumulated
    /// @dev Can only be called by the factory owner
    /// @param recipient The address to receive the protocol fees
    /// @param amountRequested The maximum amounts to collect for each token
    /// @return amounts The amounts actually collected for each token
    function collectProtocol(
        address recipient,
        uint128[] calldata amountRequested
    ) external returns (uint128[] memory amounts);
}