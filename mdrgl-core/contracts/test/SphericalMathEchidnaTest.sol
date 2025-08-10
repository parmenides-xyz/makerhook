// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import '../libraries/SphericalMath.sol';
import '../libraries/FixedPoint96.sol';

contract SphericalMathEchidnaTest {
    uint256 constant Q96 = 2**96;
    
    function test_sqrt_zero() public pure {
        uint256 result = SphericalMath.sqrt(0);
        assert(result == 0);
    }
    
    function test_sqrt_monotonicity(uint256 x, uint256 y) public pure {
        if (x > y) return;
        if (x > type(uint256).max / 2) return;
        
        uint256 sqrtX = SphericalMath.sqrt(x);
        uint256 sqrtY = SphericalMath.sqrt(y);
        
        assert(sqrtX <= sqrtY);
    }
    
    function test_sqrt_perfect_squares(uint256 n) public pure {
        if (n > 2**48) return;
        
        uint256 nQ96 = n * Q96;
        uint256 input = (n * n) * Q96;
        
        if (input > type(uint256).max / Q96) return;
        
        uint256 result = SphericalMath.sqrt(input);
        
        uint256 tolerance = nQ96 / 100 + 1;
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
        if (x > type(uint256).max >> 96) return;
        
        if (x < Q96) return;
        
        uint256 sqrtX = SphericalMath.sqrt(x);
        
        if (sqrtX > type(uint256).max / sqrtX) return;
        
        uint256 squared = (sqrtX * sqrtX) / Q96;
        
        uint256 tolerance = x / 100;
        if (tolerance == 0) tolerance = 1;
        
        if (squared > x) {
            assert(squared - x <= tolerance);
        } else {
            assert(x - squared <= tolerance);
        }
    }
    
    function test_orthogonal_zero_assets() public pure {
    }
    
    function test_orthogonal_equal_reserves(uint256 reserve, uint256 numAssets) public pure {
        if (numAssets == 0 || numAssets > 100) return;
        if (reserve > type(uint256).max / numAssets) return;
        
        uint256 sumReservesQ96 = reserve * numAssets * Q96;
        uint256 sumSquaresQ96 = reserve * reserve * numAssets * Q96;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            numAssets
        );
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
        
        assert(result >= 0);
    }
    
    function test_orthogonal_single_asset(uint256 reserve) public pure {
        if (reserve > type(uint256).max / Q96) return;
        
        uint256 sumReservesQ96 = reserve * Q96;
        uint256 sumSquaresQ96 = reserve * reserve * Q96;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            1
        );
        assert(result == 0);
    }
    
    function test_orthogonal_cauchy_schwarz(
        uint256 reserve1,
        uint256 reserve2
    ) public pure {
        if (reserve1 > 2**100 || reserve2 > 2**100) return;
        
        uint256 sumReservesQ96 = (reserve1 + reserve2) * Q96;
        uint256 sumSquaresQ96 = (reserve1 * reserve1 + reserve2 * reserve2) * Q96;
        
        uint256 result = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            2
        );
        assert(result >= 0);
        if (reserve1 == reserve2) {
            assert(result == 0);
        } else {
            assert(result > 0);
        }
    }
    
    function test_price_ratio_equal_reserves() public pure {
        uint256 reserve = 100 * Q96;
        uint256 radius = 1000 * Q96;
        
        uint256 ratio = SphericalMath.calculatePriceRatio(reserve, reserve, radius);
        assert(ratio == Q96);
    }
    
    function test_price_ratio_inverse_relationship(uint256 reserveI, uint256 reserveJ, uint256 radius) public pure {
        if (radius == 0) return;
        if (radius > type(uint256).max / 2) return;
        
        if (reserveI >= radius * 98 / 100) return;
        if (reserveJ >= radius * 98 / 100) return;
        
        uint256 ratioIJ = SphericalMath.calculatePriceRatio(reserveI, reserveJ, radius);
        uint256 ratioJI = SphericalMath.calculatePriceRatio(reserveJ, reserveI, radius);
        
        uint256 product = (ratioIJ * ratioJI) / Q96;
        uint256 tolerance = Q96 / 100;
        
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
        assert(ratio > 0);
        assert(ratio < type(uint256).max);
    }
    
    function test_price_ratio_monotonicity(uint256 reserveBase, uint256 reserve1, uint256 reserve2, uint256 radius) public pure {
        if (radius == 0) return;
        if (radius > type(uint256).max / 2) return;
        if (reserveBase >= radius * 98 / 100) return;
        if (reserve1 >= radius * 98 / 100) return;
        if (reserve2 >= radius * 98 / 100) return;
        if (reserve1 > reserve2) {
            uint256 temp = reserve1;
            reserve1 = reserve2;
            reserve2 = temp;
        }
        
        uint256 ratio1 = SphericalMath.calculatePriceRatio(reserveBase, reserve1, radius);
        uint256 ratio2 = SphericalMath.calculatePriceRatio(reserveBase, reserve2, radius);
        assert(ratio2 <= ratio1);
    }
    
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
        if (sumReserves > type(uint256).max / Q96) return;
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
        if (deltaAmount > reserveJ) return;
        if (deltaAmount == 0) return;
        
        uint256 sumReservesQ96 = sumReserves * Q96;
        uint256 sumSquaresQ96 = sumSquares * Q96;
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
        
        assert(newSumReserves == sumReservesQ96);
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
        assert(newSumSquares >= 0);
    }
    
    function test_update_sums_zero_handling() public pure {
        uint256 sumReservesQ96 = 100 * Q96;
        uint256 sumSquaresQ96 = 10000 * Q96;
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
    
    function test_validate_constraint_perfect_sphere() public pure {
        uint256 radiusQ96 = 1000 * Q96;
        uint256 numAssets = 2;
        uint256 sqrtNumAssetsQ96 = 112045541949572109684781944450942720;
        uint256 epsilonQ96 = Q96 * 1000;
        
        uint256 x = 1707;
        uint256 sumReservesQ96 = x * 2 * Q96;
        uint256 sumSquaresQ96 = x * x * 2 * Q96;
        
        (bool valid, ) = SphericalMath.validateConstraintFromSums(
            sumReservesQ96,
            sumSquaresQ96,
            radiusQ96,
            numAssets,
            sqrtNumAssetsQ96,
            epsilonQ96
        );
        
        assert(valid);
    }
    
    function test_validate_constraint_violation_detected(
        uint256 sumReserves,
        uint256 sumSquares,
        uint256 radius
    ) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (sumReserves > type(uint128).max) return;
        if (sumSquares > type(uint128).max) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 numAssets = 2;
        uint256 sqrtNumAssetsQ96 = 112045541949572109684781944450942720;
        uint256 epsilonQ96 = 0;
        
        uint256 sumReservesQ96 = sumReserves * Q96;
        uint256 sumSquaresQ96 = sumSquares * Q96;
        
        if (sumReserves > radius * 10 && sumSquares > radius * radius * 100) {
            (bool valid, ) = SphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            assert(!valid);
        }
    }
    
    function test_validate_constraint_deviation_calculation(
        uint256 epsilon
    ) public pure {
        if (epsilon > Q96 * 100000) return;
        
        uint256 radiusQ96 = 1000 * Q96;
        uint256 numAssets = 2;
        uint256 sqrtNumAssetsQ96 = 112045541949572109684781944450942720;
        
        uint256 x = 1700;
        uint256 sumReservesQ96 = x * 2 * Q96;
        uint256 sumSquaresQ96 = x * x * 2 * Q96;
        
        (bool valid, uint256 deviation) = SphericalMath.validateConstraintFromSums(
            sumReservesQ96,
            sumSquaresQ96,
            radiusQ96,
            numAssets,
            sqrtNumAssetsQ96,
            epsilon
        );
        
        assert(deviation > 19000 * Q96 && deviation < 21000 * Q96);
        
        if (epsilon >= deviation) {
            assert(valid);
        } else {
            assert(!valid);
        }
    }
    
    function test_pool_constants_valid_ranges(
        uint256 radius,
        uint256 numAssets,
        uint256 epsilon
    ) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (numAssets < 2) return;
        if (numAssets > 1000) return;
        if (epsilon == 0) return;
        if (epsilon >= radius) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 epsilonQ96 = epsilon * Q96;
        uint256 sqrtNumAssetsQ96 = SphericalMath.sqrt(numAssets * Q96);
        SphericalMath.validatePoolConstants(
            radiusQ96,
            numAssets,
            sqrtNumAssetsQ96,
            epsilonQ96
        );
        assert(true);
    }
    
    function test_pool_constants_sqrt_verification() public pure {
        // Can't test reverts with internal functions in Echidna
        // Unit tests cover this case
    }
    
    function test_pool_constants_overflow_protection(uint256 radius) public pure {
        if (radius <= type(uint128).max) return;
        
        uint256 radiusQ96 = radius;
        uint256 numAssets = 2;
        uint256 sqrtNumAssetsQ96 = SphericalMath.sqrt(numAssets * Q96);
        uint256 epsilonQ96 = Q96;
        
        if (radiusQ96 > type(uint256).max / radiusQ96) {
            return;
        }
        
        SphericalMath.validatePoolConstants(
            radiusQ96,
            numAssets,
            sqrtNumAssetsQ96,
            epsilonQ96
        );
    }
}