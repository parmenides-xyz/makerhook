// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './FixedPoint96.sol';
import './SphericalMath.sol';

/// @title Tick math for spherical AMM
/// @notice Converts between tick indices and plane constants for n-dimensional sphere AMM
/// @dev Ticks represent nested spherical caps defined by planes x̄ · v̄ = k
/// @dev Optimized for stablecoin pools with fixed tick spacing of 1 for maximum precision
library SphericalTickMath {
    // Fixed tick spacing for stablecoin pools
    // Using 1 for maximum precision since all assets are stable
    int24 internal constant TICK_SPACING = 1;
    
    // Maximum tick value - provides 0.01% precision for LP positioning
    int24 internal constant MAX_TICK = 10000;
    
    /// @notice Get the minimum plane constant (equal price point)
    /// @dev k_min = r(√n - 1)
    /// @param radiusQ96 The sphere radius in Q96
    /// @param sqrtNQ96 Square root of number of assets in Q96
    /// @return kMinQ96 Minimum plane constant in Q96
    function getKMin(
        uint256 radiusQ96,
        uint256 sqrtNQ96
    ) internal pure returns (uint256 kMinQ96) {
        require(sqrtNQ96 > FixedPoint96.Q96, "sqrt(n) must be > 1");
        
        // kMinQ96 = radiusQ96 * (sqrtNQ96 - Q96) / Q96
        kMinQ96 = FullMath.mulDiv(
            radiusQ96,
            sqrtNQ96 - FixedPoint96.Q96,
            FixedPoint96.Q96
        );
    }
    
    /// @notice Get the maximum plane constant (maximum imbalance)
    /// @dev k_max = r(n-1)/√n
    /// @param radiusQ96 The sphere radius in Q96
    /// @param n Number of assets (raw number, not Q96)
    /// @param sqrtNQ96 Square root of number of assets in Q96
    /// @return kMaxQ96 Maximum plane constant in Q96
    function getKMax(
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) internal pure returns (uint256 kMaxQ96) {
        require(n > 1, "n must be > 1");
        require(sqrtNQ96 > 0, "sqrtN must be > 0");
        
        // kMaxQ96 = radiusQ96 * (n - 1) / sqrtNQ96
        uint256 nMinus1Q96 = (n - 1) * FixedPoint96.Q96;
        kMaxQ96 = FullMath.mulDiv(
            radiusQ96,
            nMinus1Q96,
            sqrtNQ96
        );
    }
    
    /// @notice Convert tick to plane constant k
    /// @dev Linear mapping from tick to k-range
    /// @param tick The tick index
    /// @param radiusQ96 The sphere radius in Q96
    /// @param n Number of assets
    /// @param sqrtNQ96 Square root of n in Q96
    /// @return kQ96 The plane constant k in Q96
    function tickToPlaneConstant(
        int24 tick,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) internal pure returns (uint256 kQ96) {
        uint256 kMinQ96 = getKMin(radiusQ96, sqrtNQ96);
        uint256 kMaxQ96 = getKMax(radiusQ96, n, sqrtNQ96);
        
        require(tick >= 0 && tick <= MAX_TICK, "Tick out of range");
        
        if (tick == 0) {
            return kMinQ96; // Equal price point
        }
        
        // Linear interpolation from 0 to MAX_TICK
        uint256 progress = FullMath.mulDiv(
            uint256(int256(tick)),
            FixedPoint96.Q96,
            uint256(int256(MAX_TICK))
        );
        
        // k = k_min + (k_max - k_min) * progress
        uint256 kRange = kMaxQ96 - kMinQ96;
        kQ96 = kMinQ96 + FullMath.mulDiv(kRange, progress, FixedPoint96.Q96);
    }
    
    /// @notice Get tick from plane constant
    /// @dev Inverse of tickToPlaneConstant
    /// @param kQ96 The plane constant in Q96
    /// @param radiusQ96 The sphere radius in Q96
    /// @param n Number of assets
    /// @param sqrtNQ96 Square root of n in Q96
    /// @return tick The tick index
    function planeConstantToTick(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) internal pure returns (int24 tick) {
        uint256 kMinQ96 = getKMin(radiusQ96, sqrtNQ96);
        uint256 kMaxQ96 = getKMax(radiusQ96, n, sqrtNQ96);
        
        require(kQ96 >= kMinQ96 && kQ96 <= kMaxQ96, "k out of range");
        
        if (kQ96 == kMinQ96) return 0;
        
        // Calculate progress in k-range
        uint256 progress = FullMath.mulDiv(
            kQ96 - kMinQ96,
            FixedPoint96.Q96,
            kMaxQ96 - kMinQ96
        );
        
        // Convert to tick
        tick = int24(int256(FullMath.mulDiv(progress, uint256(int256(MAX_TICK)), FixedPoint96.Q96)));
    }
    
    /// @notice Calculate reduced radius in orthogonal subspace
    /// @dev s = √(r² - (k - r√n)²)
    /// @param kQ96 The plane constant in Q96
    /// @param radiusQ96 The sphere radius in Q96
    /// @param sqrtNQ96 Square root of n in Q96
    /// @return sQ96 The reduced radius in orthogonal subspace
    function getOrthogonalRadius(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 sqrtNQ96
    ) internal pure returns (uint256 sQ96) {
        // Calculate r√n
        uint256 rSqrtN = FullMath.mulDiv(radiusQ96, sqrtNQ96, FixedPoint96.Q96);
        
        // Calculate |k - r√n|
        uint256 diff;
        if (kQ96 >= rSqrtN) {
            diff = kQ96 - rSqrtN;
        } else {
            diff = rSqrtN - kQ96;
        }
        
        // Calculate (k - r√n)²
        uint256 diffSquared = FullMath.mulDiv(diff, diff, FixedPoint96.Q96);
        
        // Calculate r²
        uint256 rSquared = FullMath.mulDiv(radiusQ96, radiusQ96, FixedPoint96.Q96);
        
        // Ensure we don't underflow
        require(rSquared >= diffSquared, "Invalid k for radius");
        
        // Calculate r² - (k - r√n)²
        uint256 sSquared = rSquared - diffSquared;
        
        // Take square root
        sQ96 = SphericalMath.sqrt(sSquared);
    }
    
    /// @notice Calculate virtual reserves at tick boundary
    /// @dev From paper: x_min = (k√n - √(k²n - n((n-1)r - k√n)²))/n
    /// @param kQ96 The plane constant in Q96
    /// @param radiusQ96 The sphere radius in Q96
    /// @param n Number of assets
    /// @param sqrtNQ96 Square root of n in Q96
    /// @return xMinQ96 Minimum virtual reserve in Q96
    /// @return xMaxQ96 Maximum virtual reserve in Q96
    function getVirtualReserves(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) internal pure returns (uint256 xMinQ96, uint256 xMaxQ96) {
        // Calculate k√n
        uint256 kSqrtN = FullMath.mulDiv(kQ96, sqrtNQ96, FixedPoint96.Q96);
        
        // Calculate (n-1)r
        uint256 nMinus1R = FullMath.mulDiv(
            (n - 1) * FixedPoint96.Q96,
            radiusQ96,
            FixedPoint96.Q96
        );
        
        // Calculate |(n-1)r - k√n|
        uint256 innerTerm;
        if (nMinus1R >= kSqrtN) {
            innerTerm = nMinus1R - kSqrtN;
        } else {
            innerTerm = kSqrtN - nMinus1R;
        }
        
        // Calculate ((n-1)r - k√n)²
        uint256 innerTermSquared = FullMath.mulDiv(
            innerTerm,
            innerTerm,
            FixedPoint96.Q96
        );
        
        // Calculate k²
        uint256 kSquared = FullMath.mulDiv(kQ96, kQ96, FixedPoint96.Q96);
        
        // Calculate k²n
        uint256 kSquaredN = FullMath.mulDiv(
            kSquared,
            n * FixedPoint96.Q96,
            FixedPoint96.Q96
        );
        
        // Calculate n((n-1)r - k√n)²
        uint256 nInnerTermSquared = FullMath.mulDiv(
            n * FixedPoint96.Q96,
            innerTermSquared,
            FixedPoint96.Q96
        );
        
        // Calculate discriminant: k²n - n((n-1)r - k√n)²
        require(kSquaredN >= nInnerTermSquared, "Invalid tick parameters");
        uint256 discriminant = kSquaredN - nInnerTermSquared;
        
        // Take square root of discriminant
        uint256 sqrtDiscriminant = SphericalMath.sqrt(discriminant);
        
        // Calculate x_min = (k√n - √discriminant)/n
        require(kSqrtN >= sqrtDiscriminant, "Invalid x_min");
        xMinQ96 = (kSqrtN - sqrtDiscriminant) / n;
        
        // Calculate x_max = min(r, (k√n + √discriminant)/n)
        uint256 xMaxCandidate = (kSqrtN + sqrtDiscriminant) / n;
        xMaxQ96 = xMaxCandidate > radiusQ96 ? radiusQ96 : xMaxCandidate;
    }
    
    /// @notice Check if reserves satisfy tick plane constraint
    /// @dev Verifies that x̄ · v̄ = k
    /// @param reserves Array of reserve amounts in Q96
    /// @param kQ96 The plane constant in Q96
    /// @param sqrtNQ96 Square root of n in Q96
    /// @return isValid True if reserves lie on the tick plane
    function isOnTickPlane(
        uint256[] memory reserves,
        uint256 kQ96,
        uint256 sqrtNQ96
    ) internal pure returns (bool isValid) {
        uint256 n = reserves.length;
        require(n > 0, "Empty reserves");
        
        // Calculate x̄ · v̄ = (Σxᵢ)/√n
        uint256 sumReserves = 0;
        for (uint256 i = 0; i < n; i++) {
            sumReserves = sumReserves + reserves[i];
        }
        
        // Calculate dot product with v̄
        uint256 dotProduct = FullMath.mulDiv(
            sumReserves,
            FixedPoint96.Q96,
            sqrtNQ96
        );
        
        // Check if equal to k (with small tolerance for rounding)
        uint256 tolerance = FixedPoint96.Q96 / 1000; // 0.1% tolerance
        if (dotProduct >= kQ96) {
            isValid = (dotProduct - kQ96) <= tolerance;
        } else {
            isValid = (kQ96 - dotProduct) <= tolerance;
        }
    }
}