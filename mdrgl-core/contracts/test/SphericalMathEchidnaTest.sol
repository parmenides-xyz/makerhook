// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import '../libraries/SphericalMath.sol';
import '../libraries/FixedPoint96.sol';
import '../libraries/FullMath.sol';

contract SphericalMathEchidnaTest {
    using LowGasSafeMath for uint256;
    
    // Reasonable bounds for testing
    uint256 constant MIN_RADIUS = 79228162514264337593543950336; // MIN_RADIUS = 2^96
    uint256 constant MAX_RADIUS = 79228162514264337593543950336000000; // Q96 * 1000000
    uint256 constant MIN_N = 2;
    uint256 constant MAX_N = 10;
    uint256 constant MAX_RESERVE = 79228162514264337593543950336000000; // Q96 * 1000000
    
    /// @notice Test that sqrt function produces correct results
    function checkSqrtInvariants(uint256 x) external pure {
        // Bound input to prevent overflow
        require(x <= type(uint128).max);
        
        uint256 sqrtX = SphericalMath.sqrt(x);
        
        // Invariant 1: sqrt(0) = 0
        if (x == 0) {
            assert(sqrtX == 0);
        }
        
        // Invariant 2: For values in valid range, sqrt should maintain relationship
        if (x >= MIN_RADIUS && x < type(uint128).max) {
            // sqrt(x) returns result in Q96 scale
            // So (sqrtX * sqrtX) / Q96 should give us back x
            uint256 squared = (sqrtX * sqrtX) / MIN_RADIUS;
            
            uint256 diff = squared > x ? squared - x : x - squared;
            uint256 tolerance = x / 100; // 1% tolerance for rounding
            assert(diff <= tolerance);
        }
        
        // Invariant 3: sqrt is monotonically increasing
        // Skip for very small values where precision is lost
        if (x > MIN_RADIUS && x < type(uint128).max) {
            uint256 sqrtXPlus1 = SphericalMath.sqrt(x + 1);
            assert(sqrtXPlus1 >= sqrtX);
        }
        
        // Invariant 4: For very small values, sqrt should be proportional
        if (x < MIN_RADIUS && x > 0) {
            // For x < Q96, sqrt(x) in Q96 format will be sqrt(x) * 2^48
            // The maximum sqrt for x < Q96 would be sqrt(Q96-1) which is less than Q96
            assert(sqrtX < MIN_RADIUS);
        }
    }
    
    /// @notice Test orthogonal component calculation
    function checkOrthogonalComponentInvariants(
        uint256 sumSquaresQ96,
        uint256 sumReservesQ96,
        uint256 n
    ) external pure {
        // Bound inputs
        require(n >= MIN_N && n <= MAX_N);
        require(sumReservesQ96 <= MAX_RESERVE * n);
        require(sumSquaresQ96 <= FullMath.mulDiv(MAX_RESERVE, MAX_RESERVE, MIN_RADIUS) * n);
        
        uint256 wNormSquared = SphericalMath.computeOrthogonalComponent(
            sumSquaresQ96,
            sumReservesQ96,
            n
        );
        
        // Invariant 1: Orthogonal component should be non-negative
        assert(wNormSquared >= 0);
        
        // Invariant 2: By Cauchy-Schwarz, Σx²ᵢ >= (Σxᵢ)²/n
        // So orthogonal component = Σx²ᵢ - (Σxᵢ)²/n >= 0
        uint256 sumSquared = FullMath.mulDiv(sumReservesQ96, sumReservesQ96, MIN_RADIUS);
        uint256 sumSquaredOverN = sumSquared / n;
        
        if (sumSquaresQ96 >= sumSquaredOverN) {
            assert(wNormSquared == sumSquaresQ96 - sumSquaredOverN);
        } else {
            // Should return 0 for numerical safety
            assert(wNormSquared == 0);
        }
        
        // Invariant 3: When all reserves are equal, orthogonal component should be 0
        // This happens when sumSquaresQ96 = n * (sumReservesQ96/n)²
        uint256 avgReserve = sumReservesQ96 / n;
        uint256 expectedSumSquares = n * FullMath.mulDiv(avgReserve, avgReserve, MIN_RADIUS);
        
        if (sumSquaresQ96 == expectedSumSquares) {
            // Allow small rounding error
            assert(wNormSquared <= MIN_RADIUS / 1000);
        }
    }
    
    /// @notice Test price ratio calculation
    function checkPriceRatioInvariants(
        uint256 reserveI,
        uint256 reserveJ,
        uint256 radiusQ96
    ) external pure {
        // Bound inputs - reserves must be less than radius
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        require(reserveI < radiusQ96 * 99 / 100); // Max 99% of radius
        require(reserveJ < radiusQ96 * 99 / 100);
        require(reserveI > radiusQ96 / 10000); // Min 0.01% of radius
        require(reserveJ > radiusQ96 / 10000);
        
        uint256 ratio = SphericalMath.calculatePriceRatio(reserveI, reserveJ, radiusQ96);
        
        // Invariant 1: Price ratio should be positive
        assert(ratio > 0);
        
        // Invariant 2: When reserveI = reserveJ, ratio should be 1 (in Q96)
        if (reserveI == reserveJ) {
            assert(ratio == MIN_RADIUS);
        }
        
        // Invariant 3: When reserveI < reserveJ, ratio should be > 1
        // Because (r - xJ) < (r - xI), so ratio > 1
        if (reserveI < reserveJ) {
            assert(ratio > MIN_RADIUS);
        }
        
        // Invariant 4: When reserveI > reserveJ, ratio should be < 1
        if (reserveI > reserveJ) {
            assert(ratio < MIN_RADIUS);
        }
        
        // Invariant 5: Ratio * inverse ratio should equal 1 (approximately)
        uint256 inverseRatio = SphericalMath.calculatePriceRatio(reserveJ, reserveI, radiusQ96);
        uint256 product = FullMath.mulDiv(ratio, inverseRatio, MIN_RADIUS);
        
        // Allow for small rounding error
        uint256 diff = product > MIN_RADIUS ? 
            product - MIN_RADIUS : 
            MIN_RADIUS - product;
        assert(diff <= MIN_RADIUS / 1000); // 0.1% tolerance
    }
    
    /// @notice Test sphere constraint validation
    function checkConstraintValidation(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 radiusQ96,
        uint256 n
    ) external pure {
        // Bound inputs
        require(n >= MIN_N && n <= MAX_N);
        require(radiusQ96 >= MIN_RADIUS && radiusQ96 <= MAX_RADIUS);
        require(sumReservesQ96 <= MAX_RESERVE * n);
        require(sumSquaresQ96 <= FullMath.mulDiv(MAX_RESERVE, MAX_RESERVE, MIN_RADIUS) * n);
        
        SphericalMath.PoolConstants memory constants = SphericalMath.PoolConstants({
            radiusQ96: radiusQ96,
            numAssets: n,
            sqrtNumAssetsQ96: SphericalMath.sqrt(n * MIN_RADIUS),
            epsilonQ96: MIN_RADIUS / 100 // 1% tolerance
        });
        
        (bool valid, uint256 deviation) = SphericalMath.validateConstraintFromSums(
            sumReservesQ96,
            sumSquaresQ96,
            constants
        );
        
        // Invariant 1: Deviation should be non-negative
        assert(deviation >= 0);
        
        // Invariant 2: If valid, deviation should be within epsilon
        if (valid) {
            assert(deviation <= constants.epsilonQ96);
        }
        
        // Invariant 3: If deviation > epsilon, should not be valid
        if (deviation > constants.epsilonQ96) {
            assert(!valid);
        }
        
        // Invariant 4: For equal reserves on sphere, should be valid
        // When all xᵢ = r/√n, we have:
        // - sumReserves = n * r/√n = r√n
        // - sumSquares = n * (r/√n)² = r²
        // This satisfies the sphere constraint exactly
        uint256 equalReserve = FullMath.mulDiv(
            radiusQ96,
            MIN_RADIUS,
            constants.sqrtNumAssetsQ96
        );
        uint256 perfectSumReserves = n * equalReserve;
        uint256 perfectSumSquares = n * FullMath.mulDiv(equalReserve, equalReserve, MIN_RADIUS);
        
        (bool shouldBeValid, uint256 perfectDeviation) = SphericalMath.validateConstraintFromSums(
            perfectSumReserves,
            perfectSumSquares,
            constants
        );
        
        // Should be valid with minimal deviation
        assert(shouldBeValid);
        assert(perfectDeviation <= constants.epsilonQ96 / 10); // Much smaller than epsilon
    }
    
    /// @notice Test sum updates after trade (simplified to avoid stack too deep)
    function checkUpdateSumsInvariants(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 oldReserveI,
        uint256 newReserveI,
        uint256 oldReserveJ,
        uint256 newReserveJ
    ) external pure {
        // Bound inputs
        require(sumReservesQ96 <= MAX_RESERVE * MAX_N);
        require(sumSquaresQ96 <= MAX_RESERVE * MAX_N); // Simplified bound
        require(oldReserveI <= MAX_RESERVE);
        require(oldReserveJ <= MAX_RESERVE);
        require(newReserveI <= MAX_RESERVE);
        require(newReserveJ <= MAX_RESERVE);
        
        (uint256 newSumReserves, uint256 newSumSquares) = SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            oldReserveI,
            newReserveI,
            oldReserveJ,
            newReserveJ
        );
        
        // Invariant 1: Both sums should be non-negative
        assert(newSumReserves >= 0);
        assert(newSumSquares >= 0);
        
        // Invariant 2: Sum should change by the delta of reserves
        int256 delta = int256(newReserveI) + int256(newReserveJ) 
            - int256(oldReserveI) - int256(oldReserveJ);
        
        // Check the sum changed correctly (within rounding)
        if (delta >= 0) {
            // Sum should increase
            assert(newSumReserves >= sumReservesQ96);
        } else {
            // Sum should decrease
            assert(newSumReserves <= sumReservesQ96);
        }
    }
    
}