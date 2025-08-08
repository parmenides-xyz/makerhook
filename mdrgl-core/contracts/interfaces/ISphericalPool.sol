// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './pool/ISphericalPoolImmutables.sol';
import './pool/ISphericalPoolState.sol';
import './pool/ISphericalPoolActions.sol';
import './pool/ISphericalPoolOwnerActions.sol';
import './pool/ISphericalPoolEvents.sol';

/// @title The interface for a Spherical AMM Pool
/// @notice A spherical pool facilitates swapping and automated market making between n assets
/// using a toroidal invariant for concentrated liquidity
/// @dev The pool interface is broken into many smaller pieces
interface ISphericalPool is
    ISphericalPoolImmutables,
    ISphericalPoolState,
    ISphericalPoolActions,
    ISphericalPoolOwnerActions,
    ISphericalPoolEvents
{

}