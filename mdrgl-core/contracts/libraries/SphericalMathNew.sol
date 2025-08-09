// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FixedPoint96.sol';

/// @title Square root function for Q96 fixed-point arithmetic
/// @notice Implements sqrt for Q96 format numbers
library SphericalMathNew {
    
    /// @notice Computes the square root of a Q96 number
    /// @dev Input x is in Q96 format (represents value * 2^96)
    /// @dev Output is also in Q96 format
    /// @dev Uses the Babylonian method for integer square root
    /// @param x The Q96 number to take the square root of
    /// @return result The square root in Q96 format
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) return 0;
        
        // For Q96 arithmetic:
        // Input: x = value * 2^96
        // Standard sqrt(x) = sqrt(value * 2^96) = sqrt(value) * 2^48
        // We want: sqrt(value) * 2^96
        // So we compute sqrt(x) * 2^48
        
        // First compute standard integer square root
        uint256 xAux = x;
        result = 1;
        
        // Calculate initial approximation with binary search
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x8) {
            result <<= 1;
        }
        
        // Seven Babylonian iterations
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        result = (result + x / result) >> 1;
        
        // Round down
        uint256 roundedDownResult = x / result;
        if (result > roundedDownResult) {
            result = roundedDownResult;
        }
        
        // Now result = sqrt(x) = sqrt(value * 2^96) = sqrt(value) * 2^48
        // Scale up by 2^48 to get Q96 output
        return result << 48;
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
        require(numAssets > 0, "Invalid asset count");
        
        uint256 sumSquared = (sumReservesQ96 * sumReservesQ96) / FixedPoint96.Q96;
        uint256 sumSquaredOverN = sumSquared / numAssets;
        
        if (sumSquaresQ96 > sumSquaredOverN) {
            wNormSquaredQ96 = sumSquaresQ96 - sumSquaredOverN;
        } else {
            wNormSquaredQ96 = 0;
        }
        
        return wNormSquaredQ96;
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
        require(radiusQ96 > 0, "Invalid radius");
        require(reserveI < radiusQ96, "Reserve I exceeds radius");
        require(reserveJ < radiusQ96, "Reserve J exceeds radius");
        
        require(reserveI <= radiusQ96 * 99 / 100, "Reserve I too close to radius");
        require(reserveJ <= radiusQ96 * 99 / 100, "Reserve J too close to radius");
        
        uint256 distanceJ = radiusQ96 - reserveJ;
        uint256 distanceI = radiusQ96 - reserveI;
        
        ratioQ96 = (distanceJ * FixedPoint96.Q96) / distanceI;
    }
    
    /// @notice Updates sum tracking after a trade for O(1) complexity
    /// @dev Updates both sum of reserves and sum of squares
    /// @param sumReservesQ96 Current sum of all reserves in Q96
    /// @param sumSquaresQ96 Current sum of squared reserves in Q96
    /// @param oldReserveI Old reserve amount of asset i in Q96
    /// @param newReserveI New reserve amount of asset i in Q96
    /// @param oldReserveJ Old reserve amount of asset j in Q96
    /// @param newReserveJ New reserve amount of asset j in Q96
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
        int256 deltaReserves = int256(newReserveI) + int256(newReserveJ) - int256(oldReserveI) - int256(oldReserveJ);
        
        if (deltaReserves >= 0) {
            newSumReserves = sumReservesQ96 + uint256(deltaReserves);
        } else {
            newSumReserves = sumReservesQ96 - uint256(-deltaReserves);
        }
        
        // Update sum of squares: Σ(x')² = Σx² - xᵢ² - xⱼ² + (xᵢ')² + (xⱼ')²
        // All reserves are already in Q96, so we need to handle squaring carefully
        // (x * Q96)² = x² * Q192, so we need to divide by Q96 to get back to Q96
        
        // Calculate old squares contribution
        uint256 oldSquaresI = (oldReserveI * oldReserveI) / FixedPoint96.Q96;
        uint256 oldSquaresJ = (oldReserveJ * oldReserveJ) / FixedPoint96.Q96;
        
        // Calculate new squares contribution  
        uint256 newSquaresI = (newReserveI * newReserveI) / FixedPoint96.Q96;
        uint256 newSquaresJ = (newReserveJ * newReserveJ) / FixedPoint96.Q96;
        
        // Update sum of squares
        newSumSquares = sumSquaresQ96 - oldSquaresI - oldSquaresJ + newSquaresI + newSquaresJ;
    }
    
    /// @notice Validates sphere constraint using sum-tracking for O(1) complexity
    /// @dev Checks if Σ(r - xᵢ)² = r² within epsilon tolerance
    /// @param sumReservesQ96 Sum of all reserves in Q96 format
    /// @param sumSquaresQ96 Sum of squared reserves in Q96 format
    /// @param radiusQ96 Sphere radius in Q96 format
    /// @param numAssets Number of assets in the pool
    /// @param sqrtNumAssetsQ96 Pre-computed √n in Q96 format (unused in this formulation)
    /// @param epsilonQ96 Tolerance for validation in Q96 format
    /// @return valid True if constraint is satisfied within tolerance
    /// @return deviationQ96 Actual deviation from expected value
    function validateConstraintFromSums(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96,
        uint256 epsilonQ96
    ) internal pure returns (bool valid, uint256 deviationQ96) {
        // Sphere constraint: Σ(r - xᵢ)² = r²
        // Expanding: Σ(r² - 2rxᵢ + xᵢ²) = r²
        // = n·r² - 2r·Σxᵢ + Σxᵢ² = r²
        // = Σxᵢ² - 2r·Σxᵢ + n·r² = r²
        // = Σxᵢ² - 2r·Σxᵢ + (n-1)·r² = 0
        
        // Left side of equation: Σxᵢ² - 2r·Σxᵢ + n·r²
        uint256 leftSide;
        {
            // Term 1: Σxᵢ² (already in Q96)
            uint256 term1 = sumSquaresQ96;
            
            // Term 2: 2r·Σxᵢ (both in Q96, need to scale result back to Q96)
            uint256 term2 = 2 * ((radiusQ96 * sumReservesQ96) / FixedPoint96.Q96);
            
            // Term 3: n·r² (r in Q96, need r² in Q96)
            uint256 rSquaredQ96 = (radiusQ96 * radiusQ96) / FixedPoint96.Q96;
            uint256 term3 = numAssets * rSquaredQ96;
            
            // leftSide = term1 - term2 + term3
            leftSide = term1 + term3 - term2;
        }
        
        // Right side: r²
        uint256 rightSide = (radiusQ96 * radiusQ96) / FixedPoint96.Q96;
        
        // Calculate deviation
        if (leftSide > rightSide) {
            deviationQ96 = leftSide - rightSide;
        } else {
            deviationQ96 = rightSide - leftSide;
        }
        
        valid = deviationQ96 <= epsilonQ96;
    }
    
    /// @notice Validates pool constants
    /// @dev Ensures all constants lie within valid ranges
    /// @param radiusQ96 Sphere radius in Q96 format
    /// @param numAssets Number of assets in the pool
    /// @param sqrtNumAssetsQ96 Pre-computed √n in Q96 format
    /// @param epsilonQ96 Tolerance for validation in Q96 format
    function validatePoolConstants(
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96,
        uint256 epsilonQ96
    ) internal pure {
        require(numAssets >= 2, "Invalid asset count");
        require(radiusQ96 > 0, "Invalid radius");
        require(epsilonQ96 > 0 && epsilonQ96 < radiusQ96, "Invalid epsilon");
        
        // Verify correct computation of sqrtNumAssetsQ96
        uint256 expectedSqrtQ96 = sqrt(numAssets * FixedPoint96.Q96);
        require(
            sqrtNumAssetsQ96 == expectedSqrtQ96,
            "Incorrect sqrt computation"
        );
        
        // Check for potential overflow in constraint calculations
        require(
            radiusQ96 <= type(uint256).max / radiusQ96,
            "Radius overflow risk"
        );
    }
}