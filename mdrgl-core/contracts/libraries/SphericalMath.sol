// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';
import './FullMath.sol';
import './UnsafeMath.sol';
import './FixedPoint96.sol';

/// @title Spherical constraint mathematics for n-dimensional AMM
/// @notice Contains mathematical functions for validating sphere constraints and computing prices
/// @dev Uses Q96 fixed-point arithmetic and sum-tracking for O(1) complexity
library SphericalMath {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    // Custom error codes
    string constant CONSTRAINT_VIOLATION = "Sphere constraint violated";
    string constant INVALID_PARAMETERS = "Invalid parameters";
    string constant NEGATIVE_SQUARE_ROOT = "Negative square root";

    /// @notice Pool constants for sphere calculations
    /// @dev Pre-computed values to save gas during swaps
    struct PoolConstants {
        uint256 radiusQ96;          // Sphere radius in Q96
        uint256 numAssets;          // Number of assets (n)
        uint256 sqrtNumAssetsQ96;   // Pre-computed √n in Q96
        uint256 epsilonQ96;         // Tolerance for validation
    }

    /// @notice Validates sphere constraint using sum-tracking for O(1) complexity
    /// @dev Checks if ||r̄ - x̄||² = r² within epsilon tolerance
    /// @param sumReservesQ96 Sum of all reserves in Q96 format
    /// @param sumSquaresQ96 Sum of squared reserves in Q96 format
    /// @return valid "True" if constraint is satisfied within tolerance
    /// @return deviationQ96 Actual deviation from expected value
    function validateConstraintFromSums(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        PoolConstants memory constants
    ) internal pure returns (bool valid, uint256 deviationQ96) {
        // Compute α = Σxᵢ/√n (projection onto equal price vector)
        uint256 alphaQ96 = FullMath.mulDiv(
            sumReservesQ96,
            FixedPoint96.Q96,
            constants.sqrtNumAssetsQ96
        );

        // Compute r√n in Q96
        uint256 rSqrtNQ96 = FullMath.mulDiv(
            constants.radiusQ96,
            constants.sqrtNumAssetsQ96,
            FixedPoint96.Q96
        );

        // Compute (α - r√n)²
        uint256 diff;
        if (alphaQ96 > rSqrtNQ96) {
            diff = alphaQ96 - rSqrtNQ96;
        } else {
            diff = rSqrtNQ96 - alphaQ96;
        }
        uint256 diffSquared = FullMath.mulDiv(diff, diff, FixedPoint96.Q96);
    
        // Compute ||w||² = Σxᵢ² - (Σxᵢ)²/n
        uint256 wNormSquared = computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            constants.numAssets
        );

        // Sphere constraint: (α - r√n)² + ||w||² = r²
        uint256 leftSide = diffSquared.add(wNormSquared);
        uint256 rightSide = FullMath.mulDiv(
            constants.radiusQ96,
            constants.radiusQ96,
            FixedPoint96.Q96
        );

        // Check if within tolerance
        if (leftSide > rightSide) {
            deviationQ96 = leftSide - rightSide;
        } else {
            deviationQ96 = rightSide - leftSide;
        }

        valid = deviationQ96 <= constants.epsilonQ96;
    }

    /// @notice Validates pool constants
    /// @dev Ensures all constants lie within valid ranges
    /// @param constants The pool constants to validate
    function validatePoolConstants(PoolConstants memory constants) internal pure {
        require(constants.numAssets >= 2, "Invalid asset count");
        require(constants.radiusQ96 > 0, "Invalid radius");
        require(constants.epsilonQ96 > 0 && constants.epsilonQ96 < constants.radiusQ96, "Invalid epsilon");

        // Verify correct computation of sqrtNumAssetsQ96
        uint256 expectedSqrtQ96 = sqrt(constants.numAssets.mul(FixedPoint96.Q96));
        require(
            constants.sqrtNumAssetsQ96 == expectedSqrtQ96,
            "Incorrect sqrt computation"
        );

        // Check for potential overflow in constraint calculations
        require(
            constants.radiusQ96 <= type(uint256).max / constants.radiusQ96,
            "Radius overflow risk"
        );
    }

    /// @notice Computes the orthogonal component ||w||²
    /// @dev Calculates Σxᵢ² - (Σxᵢ)²/n with overflow protection
    /// @param sumSquaresQ96 Sum of squared reserves in Q96
    /// @param sumReservesQ96 Sum of reserves in Q96
    /// @param numAssets Number of assets in the pool
    /// @return wNormSquaredQ96 The squared norm of orthogonal component in Q96
    function computeOrthogonalComponent(
        uint256 sumSquaresQ96,
        uint256 sumReservesQ96,
        uint256 numAssets
    ) internal pure returns (uint256 wNormSquaredQ96) {
        // Input validation
        require(numAssets > 0, "Invalid asset count");
        require(sumSquaresQ96 >= 0 && sumReservesQ96 >= 0, "Invalid sums");

        // Compute (Σxᵢ)²/n in Q96
        uint256 sumSquared = FullMath.mulDiv(
            sumReservesQ96,
            sumReservesQ96,
            FixedPoint96.Q96
        );
        uint256 sumSquaredOverN = sumSquared / numAssets;

        // Ensure non-negative result (numerical safety)
        if (sumSquaresQ96 > sumSquaredOverN) {
            wNormSquaredQ96 = sumSquaresQ96 - sumSquaredOverN;
        } else {
            // This should not happen with correct reserves, but return 0 for safety
            wNormSquaredQ96 = 0;
        }
    }

    /// @notice Calculates price ratio between two assets on sphere
    /// @dev Price ratio pᵢ/pⱼ = (r - xⱼ)/(r - xᵢ)
    /// @param reserveI Reserve amount of asset i in Q96 format
    /// @param reserveJ Reserve amount of asset j in Q96 format
    /// @param radiusQ96 Sphere radius in Q96 format
    /// @return ratioQ96 Price ratio in Q96 format
    function calculatePriceRatio(
        uint256 reserveI,
        uint256 reserveJ,
        uint256 radiusQ96
    ) internal pure returns (uint256 ratioQ96) {
        require(reserveI < radiusQ96, "Reserve I exceeds radius");
        require(reserveJ < radiusQ96, "Reserve J exceeds radius");
        require(radiusQ96 > 0, "Invalid radius");
        
        // Ensure reserves are reasonable relative to radius
        require(reserveI <= radiusQ96 * 99 / 100, "Reserve I too close to radius");
        require(reserveJ <= radiusQ96 * 99 / 100, "Reserve J too close to radius");

        // Calculate (r - xⱼ)
        uint256 distanceJ = radiusQ96 - reserveJ;
        // Calculate (r - xᵢ)
        uint256 distanceI = radiusQ96 - reserveI;

        // Prevent division by zero and ensure meaningful distances
        require(distanceI > radiusQ96 / 10000, "Distance I too small");
        require(distanceJ > 0, "Distance J too small");

        // Price ratio = (r - xⱼ)/(r - xᵢ)
        ratioQ96 = FullMath.mulDiv(distanceJ, FixedPoint96.Q96, distanceI);
    }

    /// @notice Updates sum tracking after a trade for O(1) complexity
    /// @dev Updates both sum of reserves and sum of squares
    /// @param sumReservesQ96 Current sum of all reserves in Q96
    /// @param sumSquaresQ96 Current sum of squared reserves in Q96
    /// @param oldReserveI Old reserve amount of asset i (pre-trade)
    /// @param newReserveI New reserve amount of asset i (post-trade)
    /// @param oldReserveJ Old reserve amount of asset j (pre-trade)
    /// @param newReserveJ New reserve amount of asset j (post-trade)
    /// @return newSumReserves Updated sum of reserves in Q96
    /// @return newSumSquares Updated sum of squares in Q96
    function updateSumsAfterTrade(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 oldReserveI,
        uint256 newReserveI,
        uint256 oldReserveJ,
        uint256 newReserveJ
    ) internal pure returns (uint256 newSumReserves, uint256 newSumSquares) {
        // Update sum of reserves: Σx' = Σx - xᵢ - xⱼ + xᵢ' + xⱼ'
        // Convert delta to Q96 to match sumReservesQ96 units
        int256 deltaReserves = int256(newReserveI) + int256(newReserveJ) - int256(oldReserveI) - int256(oldReserveJ);
        if (deltaReserves >= 0) {
            newSumReserves = sumReservesQ96.add(FullMath.mulDiv(uint256(deltaReserves), FixedPoint96.Q96, 1));
        } else {
            newSumReserves = sumReservesQ96.sub(FullMath.mulDiv(uint256(-deltaReserves), FixedPoint96.Q96, 1));
        }

        // Update sum of squares: Σ(x')² = Σx² - xᵢ² - xⱼ² + (xᵢ')² + (xⱼ')²
        uint256 oneEther = 1e18;
        
        // First subtract old squares
        newSumSquares = sumSquaresQ96.sub(
            FullMath.mulDiv(FullMath.mulDiv(oldReserveI, oldReserveI, oneEther), FixedPoint96.Q96, 1)
        ).sub(
            FullMath.mulDiv(FullMath.mulDiv(oldReserveJ, oldReserveJ, oneEther), FixedPoint96.Q96, 1)
        );
        
        // Then add new squares
        newSumSquares = newSumSquares.add(
            FullMath.mulDiv(FullMath.mulDiv(newReserveI, newReserveI, oneEther), FixedPoint96.Q96, 1)
        ).add(
            FullMath.mulDiv(FullMath.mulDiv(newReserveJ, newReserveJ, oneEther), FixedPoint96.Q96, 1)
        );
    }

    /// @notice Helper that computes the square root of a Q96 number
    /// @dev Returns sqrt(x) in Q96 format where x is in Q96 format
    /// @param x The Q96 number to take the square root of
    /// @return result The square root in Q96 format
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        // For very small Q96 values (less than 2^96), handle specially
        // x in Q96 format represents actual_value * 2^96
        // sqrt(x) gives us sqrt(actual_value * 2^96) = sqrt(actual_value) * 2^48
        // To get Q96 output, we scale by another 2^48
        if (x < FixedPoint96.Q96) {
            if (x == 0) return 0;
            
            // Use babylonian method directly on x
            result = x;
            if (result > 1) {
                result = (result + 1) / 2;
            }
            
            // Iterations - continue until convergence
            uint256 lastResult;
            do {
                lastResult = result;
                result = (result + x / result) / 2;
            } while (result < lastResult);
            
            // result is now sqrt(x) which is in Q48 scale
            // Scale up by 2^48 to get Q96 format
            return result << 48;
        }
        
        // For normal Q96 values: sqrt(x * 2^96) = sqrt(x) * 2^48
        // We need sqrt(x/2^96) * 2^96 = sqrt(x) * 2^48
        // Use Babylonian method with better precision
        uint256 xScaled = x >> 96; // Scale down to raw number
        
        // If x is very close to Q96, use higher precision
        if (x < (FixedPoint96.Q96 * 2)) {
            // For values close to Q96, use Babylonian directly
            // Initial guess: slightly more than Q96
            result = FixedPoint96.Q96;
            
            // Babylonian iterations on Q96 value
            uint256 lastResult;
            for (uint256 i = 0; i < 10; i++) {
                lastResult = result;
                // result = (result + x/result) / 2
                // To avoid overflow: result = result/2 + x/(2*result)
                uint256 newResult = (result >> 1) + FullMath.mulDiv(x, FixedPoint96.Q96, result << 1);
                
                // If we're oscillating, always pick the smaller value
                // This ensures monotonicity across different x values
                if (newResult > result && i > 0) {
                    // We're going up after going down, stop with smaller value
                    break;
                }
                result = newResult;
                if (result == lastResult) break;
            }
            return result;
        }
        
        // Initial guess (using bit length)
        result = xScaled;
        uint256 xAux = xScaled;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result = xAux + 0x10000000000000000;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result = (result + xAux) >> 1;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result = (result + xAux) >> 1;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result = (result + xAux) >> 1;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result = (result + xAux) >> 1;
        }
        if (xAux >= 0x10) {
            result = (result + xAux) >> 1;
        }

        // Babylonian method iterations on scaled value
        result = (result + xScaled / result) >> 1;
        result = (result + xScaled / result) >> 1;
        result = (result + xScaled / result) >> 1;
        result = (result + xScaled / result) >> 1;
        result = (result + xScaled / result) >> 1;
        result = (result + xScaled / result) >> 1;
        result = (result + xScaled / result) >> 1;

        // Final adjustment
        uint256 roundedDownResult = xScaled / result;
        if (result > roundedDownResult) {
            result = roundedDownResult;
        }
        
        // Scale back up by 2^96 to get Q96 result
        return result << 96;
    }
}