// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './FixedPoint96.sol';
import './SphericalMath.sol';

/// @title Swap calculations for sphere AMM
/// @notice Orchestrates swap amount calculations using quartic solver
/// @dev Computes coefficients from toroidal invariant and solves for output
library SphericalSwapMath {
    /// @notice Parameters for swap calculation
    struct SwapParams {
        uint256 tokenIn;              // Index of input token
        uint256 tokenOut;             // Index of output token
        uint256 amountIn;             // Amount of input token
        uint256[] currentReserves;    // Current reserves for all tokens
        uint256 sumReservesQ96;       // Sum of all reserves in Q96
        uint256 sumSquaresQ96;        // Sum of squared reserves in Q96
        SphericalMath.PoolConstants poolConstants; // Pool configuration
        uint24 feePips;               // Fee in hundredths of a bip (1e-6)
        // Active tick parameters
        uint256 radiusInteriorQ96;    // Interior tick radius
        uint256 radiusBoundaryQ96;    // Boundary tick radius
        uint256 kBoundaryQ96;         // Boundary constant
    }

    /// @notice Helper to update sum tracking after a swap
    /// @param params Original swap parameters
    /// @param amountInLessFee Fee-adjusted input amount
    /// @param amountOut Calculated output amount
    /// @return newSumReservesQ96 Updated sum of reserves
    /// @return newSumSquaresQ96 Updated sum of squared reserves
    function updateSumsAfterSwap(
        SwapParams memory params,
        uint256 amountInLessFee,
        uint256 amountOut
    ) internal pure returns (uint256 newSumReservesQ96, uint256 newSumSquaresQ96) {
        // Calculate new reserves
        uint256 newReserveIn = params.currentReserves[params.tokenIn] + amountInLessFee;
        uint256 newReserveOut = params.currentReserves[params.tokenOut] - amountOut;

        // Update sums
        return SphericalMath.updateSumsAfterTrade(
            params.sumReservesQ96,
            params.sumSquaresQ96,
            params.currentReserves[params.tokenIn],
            newReserveIn,
            params.currentReserves[params.tokenOut],
            newReserveOut
        );
    }
}