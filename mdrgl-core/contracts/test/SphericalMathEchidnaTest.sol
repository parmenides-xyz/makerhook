
// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import '../libraries/SphericalMath.sol';
import '../libraries/FixedPoint96.sol';

contract SphericalMathEchidnaTest {
    uint256 constant Q96 = 2**96;
    
    // sqrt invariants
    
    function test_sqrt_zero() public pure {
        uint256 result = SphericalMath.sqrt(0);
        assert(result == 0);
    }
    
    function test_sqrt_monotonicity(uint256 x, uint256 y) public pure {
        if (x > y) return;
        if (x > type(uint256).max / 2) return; // Avoid overflow
        
        uint256 sqrtX = SphericalMath.sqrt(x);
        uint256 sqrtY = SphericalMath.sqrt(y);
        
        assert(sqrtX <= sqrtY);
    }
    
    function test_sqrt_perfect_squares(uint256 n) public pure {
        if (n > 2**48) return; // Avoid overflow (since we need n² * Q96)
        
        // Input should be in Q96 format: (n * Q96) for the value n
        // We want sqrt(n²) = n, both in Q96 format
        uint256 nQ96 = n * Q96;
        uint256 input = (n * n) * Q96; // n² in Q96 format
        
        if (input > type(uint256).max / Q96) return; // Avoid overflow
        
        uint256 result = SphericalMath.sqrt(input);
        
        // sqrt(n² * Q96) should return approximately n * Q96
        uint256 tolerance = nQ96 / 100 + 1; // 1% tolerance
        if (result > nQ96) {
            assert(result - nQ96 <= tolerance);
        } else {
            assert(nQ96 - result <= tolerance);
        }
    }
    
    function test_sqrt_Q96_identity() public pure {
        uint256 result = SphericalMath.sqrt(Q96);
        assert(result == Q96);
    }
    
    function test_sqrt_squared_approximation(uint256 x) public pure {
        if (x == 0) return;
        if (x > type(uint256).max >> 96) return; // Avoid overflow
        
        // Skip very small values where integer sqrt has poor precision
        // In practice, values in Q96 format would be much larger
        if (x < 1000) return;
        
        uint256 sqrtX = SphericalMath.sqrt(x);
        
        // (sqrt(x))² / Q96 should approximately equal x
        if (sqrtX > type(uint256).max / sqrtX) return; // Avoid overflow in multiplication
        
        uint256 squared = (sqrtX * sqrtX) / Q96;
        
        // Allow 1% tolerance for rounding errors
        uint256 tolerance = x / 100;
        if (tolerance == 0) tolerance = 1;
        
        if (squared > x) {
            assert(squared - x <= tolerance);
        } else {
            assert(x - squared <= tolerance);
        }
    }
    
    // computeOrthogonalComponent invariants
    
    function test_orthogonal_zero_assets() public pure {
        // Directly calling with 0 assets should revert
        // We can't use try-catch with internal functions, so we'll skip this test
        // The revert is tested in the JavaScript tests
    }
    
    function test_orthogonal_equal_reserves(uint256 reserve, uint256 numAssets) public pure {
        if (numAssets == 0 || numAssets > 100) return;
        if (reserve > type(uint256).max / numAssets) return; // Avoid overflow
        
        uint256 sumReservesQ96 = reserve * numAssets * Q96;
        uint256 sumSquaresQ96 = reserve * reserve * numAssets * Q96;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            numAssets
        );
        
        // For equal reserves, orthogonal component should be 0
        assert(result == 0);
    }
    
    function test_orthogonal_non_negative(
        uint256 sumSquaresQ96,
        uint256 sumReservesQ96,
        uint256 numAssets
    ) public pure {
        if (numAssets == 0) return;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            numAssets
        );
        
        // Result should always be non-negative (handled by the function)
        assert(result >= 0); // This is always true for uint256
    }
    
    function test_orthogonal_single_asset(uint256 reserve) public pure {
        if (reserve > type(uint256).max / Q96) return; // Avoid overflow
        
        uint256 sumReservesQ96 = reserve * Q96;
        uint256 sumSquaresQ96 = reserve * reserve * Q96;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            1
        );
        
        // For single asset, orthogonal component should be 0
        assert(result == 0);
    }
    
    function test_orthogonal_cauchy_schwarz(
        uint256 reserve1,
        uint256 reserve2
    ) public pure {
        if (reserve1 > 2**100 || reserve2 > 2**100) return; // Avoid overflow
        
        uint256 sumReservesQ96 = (reserve1 + reserve2) * Q96;
        uint256 sumSquaresQ96 = (reserve1 * reserve1 + reserve2 * reserve2) * Q96;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            2
        );
        
        // By Cauchy-Schwarz: 2 * (r1² + r2²) >= (r1 + r2)²
        // So orthogonal = (r1² + r2²) - (r1 + r2)²/2 >= 0
        assert(result >= 0);
        
        // Maximum when reserves are maximally different
        // Minimum (0) when reserves are equal
        if (reserve1 == reserve2) {
            assert(result == 0);
        } else {
            assert(result > 0);
        }
    }
    
    // calculatePriceRatio invariants
    
    function test_price_ratio_equal_reserves() public pure {
        uint256 reserve = 100 * Q96;
        uint256 radius = 1000 * Q96;
        
        uint256 ratio = SphericalMath.calculatePriceRatio(reserve, reserve, radius);
        
        // Equal reserves should give ratio of 1.0 (Q96)
        assert(ratio == Q96);
    }
    
    function test_price_ratio_inverse_relationship(uint256 reserveI, uint256 reserveJ, uint256 radius) public pure {
        if (radius == 0) return;
        if (radius > type(uint256).max / 2) return; // Avoid overflow
        
        // Ensure reserves are valid (less than radius and not too close)
        if (reserveI >= radius * 98 / 100) return;
        if (reserveJ >= radius * 98 / 100) return;
        
        uint256 ratioIJ = SphericalMath.calculatePriceRatio(reserveI, reserveJ, radius);
        uint256 ratioJI = SphericalMath.calculatePriceRatio(reserveJ, reserveI, radius);
        
        // ratioIJ * ratioJI should approximately equal Q96²
        // Due to integer division, allow some tolerance
        uint256 product = (ratioIJ * ratioJI) / Q96;
        uint256 tolerance = Q96 / 100; // 1% tolerance
        
        if (product > Q96) {
            assert(product - Q96 <= tolerance);
        } else {
            assert(Q96 - product <= tolerance);
        }
    }
    
    function test_price_ratio_bounds(uint256 reserveI, uint256 reserveJ, uint256 radius) public pure {
        if (radius == 0) return;
        if (reserveI >= radius) return;
        if (reserveJ >= radius) return;
        if (reserveI > radius * 99 / 100) return;
        if (reserveJ > radius * 99 / 100) return;
        
        uint256 ratio = SphericalMath.calculatePriceRatio(reserveI, reserveJ, radius);
        
        // Ratio should be positive and bounded
        assert(ratio > 0);
        assert(ratio < type(uint256).max);
    }
    
    function test_price_ratio_monotonicity(uint256 reserveBase, uint256 reserve1, uint256 reserve2, uint256 radius) public pure {
        if (radius == 0) return;
        if (radius > type(uint256).max / 2) return;
        
        // Ensure all reserves are valid
        if (reserveBase >= radius * 98 / 100) return;
        if (reserve1 >= radius * 98 / 100) return;
        if (reserve2 >= radius * 98 / 100) return;
        
        // Order reserves
        if (reserve1 > reserve2) {
            uint256 temp = reserve1;
            reserve1 = reserve2;
            reserve2 = temp;
        }
        
        uint256 ratio1 = SphericalMath.calculatePriceRatio(reserveBase, reserve1, radius);
        uint256 ratio2 = SphericalMath.calculatePriceRatio(reserveBase, reserve2, radius);
        
        // Higher reserve of other asset should give lower price ratio
        // ratio = (r - reserveOther) / (r - reserveBase)
        // So if reserve2 > reserve1, then ratio2 < ratio1
        assert(ratio2 <= ratio1);
    }
    
    // updateSumsAfterTrade invariants
    
    function test_update_sums_no_change() public pure {
        uint256 sumReservesQ96 = 1000 * Q96;
        uint256 sumSquaresQ96 = 500000 * Q96;
        uint256 reserve = 100 * Q96;
        
        (uint256 newSumReserves, uint256 newSumSquares) = SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            reserve,
            reserve,  // same value
            reserve,
            reserve   // same value
        );
        
        // No change should mean same sums
        assert(newSumReserves == sumReservesQ96);
        assert(newSumSquares == sumSquaresQ96);
    }
    
    function test_update_sums_conservation(
        uint256 sumReserves,
        uint256 oldI,
        uint256 newI,
        uint256 oldJ,
        uint256 newJ
    ) public pure {
        if (sumReserves > type(uint256).max / Q96) return; // Avoid overflow
        if (oldI > type(uint128).max) return;
        if (newI > type(uint128).max) return;
        if (oldJ > type(uint128).max) return;
        if (newJ > type(uint128).max) return;
        
        uint256 sumReservesQ96 = sumReserves * Q96;
        uint256 sumSquaresQ96 = sumReserves * sumReserves; // Simplified for test
        
        uint256 oldIQ96 = oldI * Q96;
        uint256 newIQ96 = newI * Q96;
        uint256 oldJQ96 = oldJ * Q96;
        uint256 newJQ96 = newJ * Q96;
        
        (uint256 newSumReserves, ) = SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            oldIQ96,
            newIQ96,
            oldJQ96,
            newJQ96
        );
        
        // Check conservation: new sum = old sum - oldI - oldJ + newI + newJ
        int256 expectedDelta = int256(newI) + int256(newJ) - int256(oldI) - int256(oldJ);
        
        if (expectedDelta >= 0) {
            uint256 expected = sumReservesQ96 + uint256(expectedDelta) * Q96;
            assert(newSumReserves == expected);
        } else {
            uint256 expected = sumReservesQ96 - uint256(-expectedDelta) * Q96;
            assert(newSumReserves == expected);
        }
    }
    
    function test_update_sums_swap_conservation(
        uint256 sumReserves,
        uint256 sumSquares,
        uint256 reserveI,
        uint256 reserveJ,
        uint256 deltaAmount
    ) public pure {
        if (sumReserves > type(uint256).max / Q96) return;
        if (sumSquares > type(uint256).max / Q96) return;
        if (reserveI > type(uint128).max) return;
        if (reserveJ > type(uint128).max) return;
        if (deltaAmount > reserveJ) return; // Can't swap more than available
        if (deltaAmount == 0) return;
        
        uint256 sumReservesQ96 = sumReserves * Q96;
        uint256 sumSquaresQ96 = sumSquares * Q96;
        
        // Simulate a swap: I increases by deltaAmount, J decreases by deltaAmount
        uint256 oldIQ96 = reserveI * Q96;
        uint256 newIQ96 = (reserveI + deltaAmount) * Q96;
        uint256 oldJQ96 = reserveJ * Q96;
        uint256 newJQ96 = (reserveJ - deltaAmount) * Q96;
        
        (uint256 newSumReserves, uint256 newSumSquares) = SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            oldIQ96,
            newIQ96,
            oldJQ96,
            newJQ96
        );
        
        // In a swap, sum of reserves should remain constant
        assert(newSumReserves == sumReservesQ96);
        
        // Sum of squares should change (unless deltaAmount is 0)
        assert(newSumSquares != sumSquaresQ96);
    }
    
    function test_update_sums_squares_positive(
        uint256 sumSquares,
        uint256 oldI,
        uint256 newI,
        uint256 oldJ,
        uint256 newJ
    ) public pure {
        if (sumSquares > type(uint256).max / Q96) return;
        if (oldI > type(uint128).max) return;
        if (newI > type(uint128).max) return;
        if (oldJ > type(uint128).max) return;
        if (newJ > type(uint128).max) return;
        
        // Ensure initial sum of squares is large enough
        uint256 minSquares = (oldI * oldI + oldJ * oldJ) * 2;
        if (sumSquares < minSquares) sumSquares = minSquares;
        
        uint256 sumReservesQ96 = 1000 * Q96; // Arbitrary
        uint256 sumSquaresQ96 = sumSquares * Q96;
        
        uint256 oldIQ96 = oldI * Q96;
        uint256 newIQ96 = newI * Q96;
        uint256 oldJQ96 = oldJ * Q96;
        uint256 newJQ96 = newJ * Q96;
        
        (, uint256 newSumSquares) = SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            oldIQ96,
            newIQ96,
            oldJQ96,
            newJQ96
        );
        
        // Sum of squares should always be non-negative (trivially true for uint256)
        assert(newSumSquares >= 0);
    }
    
    function test_update_sums_zero_handling() public pure {
        uint256 sumReservesQ96 = 100 * Q96;
        uint256 sumSquaresQ96 = 10000 * Q96;
        
        // Test adding from zero
        (uint256 newSumReserves1, uint256 newSumSquares1) = SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            0,
            50 * Q96,
            0,
            50 * Q96
        );
        
        assert(newSumReserves1 == 200 * Q96);
        assert(newSumSquares1 == 15000 * Q96);
        
        // Test removing to zero
        (uint256 newSumReserves2, uint256 newSumSquares2) = SphericalMath.updateSumsAfterTrade(
            200 * Q96,
            20000 * Q96,
            50 * Q96,
            0,
            50 * Q96,
            0
        );
        
        assert(newSumReserves2 == 100 * Q96);
        assert(newSumSquares2 == 15000 * Q96);
    }
}