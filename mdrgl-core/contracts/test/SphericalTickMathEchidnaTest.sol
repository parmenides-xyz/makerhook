// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../libraries/SphericalTickMath.sol';
import '../libraries/FixedPoint96.sol';

contract SphericalTickMathEchidnaTest {
    // Test bounds for reasonable values
    uint256 constant MIN_RADIUS = 79228162514264337593543950336; // MIN_RADIUS = 2^96
    uint256 constant MAX_RADIUS = 79228162514264337593543950336000000; // Q96 * 1000000
    uint256 constant MIN_N = 2;
    uint256 constant MAX_N = 10;
    
    /// @notice Check that k_min < k_max always holds
    function checkKMinLessThanKMax(
        uint256 radiusQ96,
        uint256 n
    ) external pure {
        // Bound inputs to reasonable ranges
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        require(n >= MIN_N && n <= MAX_N);
        
        // Calculate sqrt(n) in Q96
        uint256 sqrtNQ96 = sqrt(n * MIN_RADIUS); // MIN_RADIUS = Q96
        
        uint256 kMin = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        uint256 kMax = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        
        // Invariant: k_min should always be less than k_max
        assert(kMin < kMax);
    }
    
    /// @notice Check tick to plane constant monotonicity and bounds
    function checkTickToPlaneConstantInvariants(
        int24 tick,
        uint256 radiusQ96,
        uint256 n
    ) external pure {
        // Bound inputs
        require(tick >= 0 && tick <= SphericalTickMath.MAX_TICK);
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        require(n >= MIN_N && n <= MAX_N);
        
        uint256 sqrtNQ96 = sqrt(n * MIN_RADIUS);
        
        uint256 k = SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
        uint256 kMin = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        uint256 kMax = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        
        // Invariant 1: k should always be within [k_min, k_max]
        assert(k >= kMin);
        assert(k <= kMax);
        
        // Invariant 2: tick 0 should map to k_min
        if (tick == 0) {
            assert(k == kMin);
        }
        
        // Invariant 3: MAX_TICK should map close to k_max (within rounding)
        if (tick == SphericalTickMath.MAX_TICK) {
            // Allow for small rounding error (0.01%)
            assert(k >= kMax - kMax / 10000);
            assert(k <= kMax);
        }
        
        // Invariant 4: Monotonicity - higher tick means higher k
        if (tick > 0) {
            uint256 kPrev = SphericalTickMath.tickToPlaneConstant(tick - 1, radiusQ96, n, sqrtNQ96);
            assert(k > kPrev);
        }
        if (tick < SphericalTickMath.MAX_TICK) {
            uint256 kNext = SphericalTickMath.tickToPlaneConstant(tick + 1, radiusQ96, n, sqrtNQ96);
            assert(k < kNext);
        }
    }
    
    /// @notice Check that planeConstantToTick is inverse of tickToPlaneConstant
    function checkTickConversionInverse(
        int24 tick,
        uint256 radiusQ96,
        uint256 n
    ) external pure {
        require(tick >= 0 && tick <= SphericalTickMath.MAX_TICK);
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        require(n >= MIN_N && n <= MAX_N);
        
        uint256 sqrtNQ96 = sqrt(n * MIN_RADIUS);
        
        // Convert tick to k
        uint256 k = SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
        
        // Convert k back to tick
        int24 recoveredTick = SphericalTickMath.planeConstantToTick(k, radiusQ96, n, sqrtNQ96);
        
        // Should recover the same tick (allowing for rounding error of ±1)
        assert(recoveredTick >= tick - 1 && recoveredTick <= tick + 1);
    }
    
    /// @notice Check orthogonal radius calculation invariants
    function checkOrthogonalRadiusInvariants(
        uint256 kQ96,
        uint256 radiusQ96
    ) external pure {
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        
        // Use n=3 for testing
        uint256 n = 3;
        uint256 sqrtNQ96 = sqrt(n * MIN_RADIUS);
        
        // k must be in valid range
        uint256 kMin = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        uint256 kMax = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        require(kQ96 >= kMin && kQ96 <= kMax);
        
        uint256 s = SphericalTickMath.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96);
        
        // Invariant 1: Orthogonal radius should never exceed the sphere radius
        assert(s <= radiusQ96);
        
        // Invariant 2: Orthogonal radius should be non-negative
        assert(s >= 0);
        
        // Invariant 3: At k = r√n (center), s should be minimal (near 0)
        uint256 center = (radiusQ96 * sqrtNQ96) / MIN_RADIUS;
        if (kQ96 == center) {
            // Allow small rounding error
            assert(s <= MIN_RADIUS / 1000); // Less than 0.001
        }
    }
    
    /// @notice Check virtual reserves calculation invariants
    function checkVirtualReservesInvariants(
        int24 tick,
        uint256 radiusQ96,
        uint256 n
    ) external pure {
        require(tick >= 100 && tick <= SphericalTickMath.MAX_TICK - 100); // Avoid edge cases
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        require(n >= MIN_N && n <= MAX_N);
        
        uint256 sqrtNQ96 = sqrt(n * MIN_RADIUS);
        uint256 k = SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
        
        (uint256 xMin, uint256 xMax) = SphericalTickMath.getVirtualReserves(k, radiusQ96, n, sqrtNQ96);
        
        // Invariant 1: xMin should be less than xMax
        assert(xMin < xMax);
        
        // Invariant 2: xMax should not exceed radius
        assert(xMax <= radiusQ96);
        
        // Invariant 3: xMin should be non-negative
        assert(xMin >= 0);
        
        // Invariant 4: At higher ticks, spread (xMax - xMin) should be smaller
        if (tick < SphericalTickMath.MAX_TICK - 100) {
            uint256 kNext = SphericalTickMath.tickToPlaneConstant(tick + 100, radiusQ96, n, sqrtNQ96);
            (uint256 xMinNext, uint256 xMaxNext) = SphericalTickMath.getVirtualReserves(kNext, radiusQ96, n, sqrtNQ96);
            
            uint256 spread = xMax - xMin;
            uint256 spreadNext = xMaxNext - xMinNext;
            
            // Higher ticks should have smaller spread (more concentrated liquidity)
            assert(spreadNext <= spread);
        }
    }
    
    /// @notice Check that reserves validation works correctly
    function checkIsOnTickPlane(
        uint256 reserve1,
        uint256 reserve2,
        uint256 reserve3,
        int24 tick,
        uint256 radiusQ96
    ) external pure {
        require(tick >= 0 && tick <= SphericalTickMath.MAX_TICK);
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        
        uint256 n = 3;
        uint256 sqrtNQ96 = sqrt(n * MIN_RADIUS);
        
        // Bound reserves to reasonable values
        require(reserve1 <= radiusQ96);
        require(reserve2 <= radiusQ96);
        require(reserve3 <= radiusQ96);
        
        // Create dynamic array for the function call
        uint256[] memory reserves = new uint256[](3);
        reserves[0] = reserve1;
        reserves[1] = reserve2;
        reserves[2] = reserve3;
        
        uint256 k = SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
        
        // Calculate actual dot product
        uint256 sumReserves = reserve1 + reserve2 + reserve3;
        uint256 actualK = (sumReserves * MIN_RADIUS) / sqrtNQ96;
        
        bool isOnPlane = SphericalTickMath.isOnTickPlane(reserves, k, sqrtNQ96);
        
        // If reserves exactly satisfy the equation (within tolerance), should return true
        uint256 tolerance = MIN_RADIUS / 1000; // 0.1% tolerance
        uint256 diff = actualK > k ? actualK - k : k - actualK;
        
        if (diff <= tolerance) {
            assert(isOnPlane == true);
        }
        // If far from plane, should return false
        else if (diff > tolerance * 10) {
            assert(isOnPlane == false);
        }
    }
    
    // Helper function to compute integer square root
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}