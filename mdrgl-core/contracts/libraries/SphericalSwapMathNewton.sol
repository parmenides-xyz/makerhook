// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './FixedPoint96.sol';
import './SphericalMath.sol';
import './LowGasSafeMath.sol';
import './SafeCast.sol';

/// @title Newton's method swap calculations for sphere AMM
/// @notice Computes swap outputs using Newton's method on toroidal invariant
/// @dev Solves f(Δ) = invariant(new_state) - r_int² = 0 iteratively
library SphericalSwapMathNewton {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;
    
    uint256 private constant MAX_ITERATIONS = 10;
    uint256 private constant CONVERGENCE_THRESHOLD = 1; // 1 wei precision
    
    // Error messages
    string constant NEWTON_CONVERGENCE_FAILED = "Newton method failed to converge";
    string constant INVALID_DERIVATIVE = "Zero derivative in Newton iteration";
    string constant INVALID_TOKEN = "Invalid token index";
    string constant ZERO_INPUT = "Zero input amount";
    string constant INSUFFICIENT_RESERVES = "Insufficient reserves";
    
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
    
    /// @notice Calculate swap output using Newton's method
    /// @param params Swap parameters
    /// @return amountOut The calculated output amount
    /// @return feeAmount The fee taken from input
    function calculateSwapOutput(
        SwapParams memory params
    ) internal pure returns (uint256 amountOut, uint256 feeAmount) {
        require(params.tokenIn < params.currentReserves.length, INVALID_TOKEN);
        require(params.tokenOut < params.currentReserves.length, INVALID_TOKEN);
        require(params.tokenIn != params.tokenOut, INVALID_TOKEN);
        require(params.amountIn > 0, ZERO_INPUT);
        
        // Apply fee to input
        uint256 amountInLessFee = params.amountIn * (1e6 - params.feePips) / 1e6;
        feeAmount = params.amountIn - amountInLessFee;
        
        // Initial guess: use constant product approximation
        uint256 delta = (params.currentReserves[params.tokenOut] * amountInLessFee) / 
                        (params.currentReserves[params.tokenIn] + amountInLessFee);
        
        // Ensure initial guess is reasonable
        if (delta > params.currentReserves[params.tokenOut] * 99 / 100) {
            delta = params.currentReserves[params.tokenOut] * 90 / 100;
        }
        
        // Newton iterations
        for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
            // Calculate new reserves
            uint256 newReserveIn = params.currentReserves[params.tokenIn] + amountInLessFee;
            uint256 newReserveOut = params.currentReserves[params.tokenOut] - delta;
            
            // Update sums efficiently
            (uint256 newSumReservesQ96, uint256 newSumSquaresQ96) = SphericalMath.updateSumsAfterTrade(
                params.sumReservesQ96,
                params.sumSquaresQ96,
                params.currentReserves[params.tokenIn],
                newReserveIn,
                params.currentReserves[params.tokenOut],
                newReserveOut
            );
            
            // Calculate invariant value and derivative
            (int256 f, int256 fPrime) = evaluateInvariantAndDerivative(
                params,
                newSumReservesQ96,
                newSumSquaresQ96,
                newReserveOut,
                delta
            );
            
            // Check convergence
            if (abs(f) < int256(CONVERGENCE_THRESHOLD * int256(FixedPoint96.Q96))) {
                amountOut = delta;
                break;
            }
            
            // Avoid division by zero
            if (fPrime == 0) {
                // Use bisection fallback if derivative is zero
                delta = delta * 99 / 100;
                continue;
            }
            
            // Newton update: delta_new = delta - f/f'
            int256 deltaUpdate = FullMath.mulDiv(
                uint256(abs(f)),
                FixedPoint96.Q96,
                uint256(abs(fPrime))
            );
            
            if (f * fPrime > 0) {
                // Same sign, subtract update
                if (uint256(deltaUpdate) > delta) {
                    delta = delta / 2; // Halve if update would make negative
                } else {
                    delta = delta - uint256(deltaUpdate);
                }
            } else {
                // Different sign, add update
                delta = delta + uint256(deltaUpdate);
            }
            
            // Bound delta to reasonable range
            if (delta > params.currentReserves[params.tokenOut] * 99 / 100) {
                delta = params.currentReserves[params.tokenOut] * 99 / 100;
            }
            
            amountOut = delta;
        }
        
        require(amountOut > 0, NEWTON_CONVERGENCE_FAILED);
        require(amountOut <= params.currentReserves[params.tokenOut], INSUFFICIENT_RESERVES);
    }
    
    /// @dev Evaluate toroidal invariant and its derivative at current delta
    function evaluateInvariantAndDerivative(
        SwapParams memory params,
        uint256 newSumReservesQ96,
        uint256 newSumSquaresQ96,
        uint256 newReserveOut,
        uint256 delta
    ) private pure returns (int256 f, int256 fPrime) {
        // Calculate projection onto equal-price vector
        uint256 sqrtN = sqrt(params.poolConstants.numAssets);
        uint256 projectionQ96 = FullMath.mulDiv(
            newSumReservesQ96,
            FixedPoint96.Q96,
            sqrtN
        ) - params.kBoundaryQ96 - FullMath.mulDiv(
            params.radiusInteriorQ96,
            sqrtN,
            1
        );
        
        // Calculate orthogonal component squared
        uint256 orthogonalSqQ96 = newSumSquaresQ96 - FullMath.mulDiv(
            newSumReservesQ96,
            newSumReservesQ96,
            params.poolConstants.numAssets
        );
        
        // Calculate boundary discriminant
        uint256 boundaryDiscriminantQ96 = FullMath.mulDiv(
            params.radiusBoundaryQ96,
            params.radiusBoundaryQ96,
            FixedPoint96.Q96
        ).sub(
            FullMath.mulDiv(
                params.kBoundaryQ96 - FullMath.mulDiv(params.radiusBoundaryQ96, sqrtN, 1),
                params.kBoundaryQ96 - FullMath.mulDiv(params.radiusBoundaryQ96, sqrtN, 1),
                FixedPoint96.Q96
            );
        
        // Toroidal invariant: f = projection² + (sqrt(orthogonal) - sqrt(boundary_disc))² - r_int²
        uint256 sqrtOrthogonal = SphericalMath.sqrt(orthogonalSqQ96);
        uint256 sqrtBoundaryDisc = SphericalMath.sqrt(boundaryDiscriminantQ96);
        
        int256 orthogonalDiff = int256(sqrtOrthogonal) - int256(sqrtBoundaryDisc);
        
        f = int256(FullMath.mulDiv(projectionQ96, projectionQ96, FixedPoint96.Q96)) +
            int256(FullMath.mulDiv(uint256(orthogonalDiff * orthogonalDiff), FixedPoint96.Q96, FixedPoint96.Q96)) -
            int256(FullMath.mulDiv(params.radiusInteriorQ96, params.radiusInteriorQ96, FixedPoint96.Q96));
        
        // Full derivative with respect to delta (output amount)
        // f = P² + (√W - √B)² - r_int²
        // where P = (S₀ + d - Δ)/√n - k_b - r_int*√n
        //       W = S₂ - S₀²/n (orthogonal component squared)
        
        // dP/dΔ = -1/√n
        int256 dP_dDelta = -int256(FixedPoint96.Q96) / int256(sqrtN);
        
        // df/dP = 2P
        int256 df_dP = 2 * int256(projectionQ96);
        
        // For orthogonal term: d/dΔ[(√W - √B)²]
        // W changes with Δ: W = S₂ - S₀²/n where S₀ = sum - Δ, S₂ = sum_squares - x_out² + (x_out - Δ)²
        
        // dW/dΔ = d/dΔ[S₂ - S₀²/n]
        // dS₀/dΔ = -1
        // dS₂/dΔ = -2(x_out - Δ) = -2*newReserveOut
        
        // dW/dΔ = -2*newReserveOut + 2*S₀/n = -2*newReserveOut + 2*newSumReserves/n
        int256 dW_dDelta = -2 * int256(newReserveOut) + 
                           2 * int256(FullMath.mulDiv(newSumReservesQ96, FixedPoint96.Q96, params.poolConstants.numAssets * FixedPoint96.Q96));
        
        // d/dΔ[(√W - √B)²] = 2(√W - √B) * d(√W)/dΔ
        // d(√W)/dΔ = (1/2√W) * dW/dΔ
        int256 dSqrtW_dDelta;
        if (sqrtOrthogonal > 0) {
            dSqrtW_dDelta = int256(FullMath.mulDiv(
                uint256(abs(dW_dDelta)),
                FixedPoint96.Q96,
                2 * sqrtOrthogonal
            ));
            if (dW_dDelta < 0) dSqrtW_dDelta = -dSqrtW_dDelta;
        } else {
            dSqrtW_dDelta = 0;
        }
        
        // df/d(orthogonal_term) = 2(√W - √B)
        int256 df_dOrthogonal = 2 * orthogonalDiff;
        
        // Combine using chain rule: df/dΔ = (df/dP)(dP/dΔ) + (df/dOrthogonal)(dOrthogonal/dΔ)
        fPrime = FullMath.mulDiv(uint256(abs(df_dP)), uint256(abs(dP_dDelta)), FixedPoint96.Q96);
        if (df_dP * dP_dDelta < 0) fPrime = -fPrime;
        
        int256 orthogonalContribution = FullMath.mulDiv(
            uint256(abs(df_dOrthogonal)), 
            uint256(abs(dSqrtW_dDelta)), 
            FixedPoint96.Q96
        );
        if (df_dOrthogonal * dSqrtW_dDelta < 0) orthogonalContribution = -orthogonalContribution;
        
        fPrime = fPrime + orthogonalContribution;
    }
    
    /// @dev Absolute value helper
    function abs(int256 x) private pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}