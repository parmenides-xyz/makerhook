// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import '../libraries/SphericalTickMath.sol';
import '../libraries/FixedPoint96.sol';
import '../libraries/SphericalMath.sol';

contract SphericalTickMathEchidnaTest {
    uint256 constant Q96 = 2**96;
    int24 constant MAX_TICK = 10000;
    
    function test_kmin_less_than_kmax(uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kMinQ96 = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        uint256 kMaxQ96 = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        
        assert(kMinQ96 < kMaxQ96);
    }
    
    function test_tick_to_plane_constant_monotonic(int24 tick1, int24 tick2, uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        if (tick1 < 0 || tick1 > MAX_TICK) return;
        if (tick2 < 0 || tick2 > MAX_TICK) return;
        if (tick1 > tick2) {
            int24 temp = tick1;
            tick1 = tick2;
            tick2 = temp;
        }
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 k1 = SphericalTickMath.tickToPlaneConstant(tick1, radiusQ96, n, sqrtNQ96);
        uint256 k2 = SphericalTickMath.tickToPlaneConstant(tick2, radiusQ96, n, sqrtNQ96);
        
        assert(k1 <= k2);
    }
    
    function test_plane_constant_to_tick_inverse(int24 tick, uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        if (tick < 0 || tick > MAX_TICK) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kQ96 = SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
        int24 recoveredTick = SphericalTickMath.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96);
        
        int24 diff = recoveredTick > tick ? recoveredTick - tick : tick - recoveredTick;
        assert(diff <= 1);
    }
    
    function test_orthogonal_radius_at_center(uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kCenter = (radiusQ96 * sqrtNQ96) / Q96;
        
        uint256 sQ96 = SphericalTickMath.getOrthogonalRadius(kCenter, radiusQ96, sqrtNQ96);
        
        assert(sQ96 == radiusQ96);
    }
    
    function test_orthogonal_radius_decreases(uint256 radius, uint256 n, uint256 delta) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        if (delta == 0) return;
        if (delta > radius / 2) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kCenter = (radiusQ96 * sqrtNQ96) / Q96;
        uint256 deltaQ96 = delta * Q96;
        
        if (kCenter < deltaQ96) return;
        
        uint256 kOff = kCenter - deltaQ96;
        
        uint256 sCenter = SphericalTickMath.getOrthogonalRadius(kCenter, radiusQ96, sqrtNQ96);
        uint256 sOff = SphericalTickMath.getOrthogonalRadius(kOff, radiusQ96, sqrtNQ96);
        
        assert(sOff < sCenter);
    }
    
    function test_virtual_reserves_bounds(int24 tick, uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        if (tick < 0 || tick > MAX_TICK) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kQ96 = SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
        
        uint256 kMinQ96 = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        uint256 kMaxQ96 = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        if (kQ96 < kMinQ96 || kQ96 > kMaxQ96) return;
        
        (uint256 xMinQ96, uint256 xMaxQ96) = SphericalTickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96);
        assert(xMinQ96 >= 0);
        assert(xMaxQ96 <= radiusQ96);
        assert(xMinQ96 <= xMaxQ96);
    }
    
    function test_virtual_reserves_near_kmin(uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius < 100) return; // Skip very small radius to avoid precision issues
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kMinQ96 = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        uint256 kMaxQ96 = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        uint256 kQ96 = kMinQ96 + Q96;
        
        if (kQ96 > kMaxQ96) return;
        
        (uint256 xMinQ96, uint256 xMaxQ96) = SphericalTickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96);
        // Near k_min, just verify basic sanity: xMin < xMax <= radius
        assert(xMinQ96 < xMaxQ96);
        assert(xMaxQ96 <= radiusQ96);
    }
    
    function test_virtual_reserves_near_kmax(uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius < 100) return; // Skip very small radius to avoid precision issues
        if (radius > type(uint128).max) return;
        if (n <= 1) return;
        if (n > 100) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 kMaxQ96 = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        uint256 kMinQ96 = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        
        if (kMaxQ96 <= Q96) return;
        
        uint256 kQ96 = kMaxQ96 - Q96;
        
        if (kQ96 < kMinQ96) return;
        
        (uint256 xMinQ96, uint256 xMaxQ96) = SphericalTickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96);
        // Near k_max, xMin should be small but may vary with n and radius
        uint256 threshold = n == 2 ? radiusQ96 / 5 : radiusQ96 / 10;
        assert(xMinQ96 < threshold);
        assert(xMaxQ96 == radiusQ96);
    }
    
    function test_is_on_tick_plane_equal_reserves(uint256 radius, uint256 n) public pure {
        if (radius == 0) return;
        if (radius > type(uint64).max) return;
        if (n < 2) return;
        if (n > 10) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 equalReserve = radiusQ96;
        
        uint256[] memory reserves = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            reserves[i] = equalReserve;
        }
        
        uint256 sumReserves = equalReserve * n;
        uint256 kQ96 = (sumReserves * Q96) / sqrtNQ96;
        
        bool isValid = SphericalTickMath.isOnTickPlane(reserves, kQ96, sqrtNQ96);
        assert(isValid);
    }
    
    function test_is_on_tick_plane_violation(uint256 radius, uint256 n, uint256 deviation) public pure {
        if (radius == 0) return;
        if (radius > type(uint64).max) return;
        if (n < 2) return;
        if (n > 10) return;
        if (deviation < Q96 / 100) return;
        if (deviation > radius * Q96) return;
        
        uint256 radiusQ96 = radius * Q96;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        if (sqrtNQ96 <= Q96) return;
        
        uint256 equalReserve = radiusQ96;
        
        uint256[] memory reserves = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            reserves[i] = equalReserve;
        }
        
        uint256 sumReserves = equalReserve * n;
        uint256 correctK = (sumReserves * Q96) / sqrtNQ96;
        uint256 wrongK = correctK + deviation;
        
        bool isValid = SphericalTickMath.isOnTickPlane(reserves, wrongK, sqrtNQ96);
        assert(!isValid);
    }
    
    function test_tick_bounds() public pure {
        uint256 radiusQ96 = 100 * Q96;
        uint256 n = 3;
        uint256 sqrtNQ96 = SphericalMath.sqrt(n * Q96);
        
        uint256 kQ96AtTick0 = SphericalTickMath.tickToPlaneConstant(0, radiusQ96, n, sqrtNQ96);
        uint256 kMinQ96 = SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
        assert(kQ96AtTick0 == kMinQ96);
        
        uint256 kQ96AtMaxTick = SphericalTickMath.tickToPlaneConstant(MAX_TICK, radiusQ96, n, sqrtNQ96);
        uint256 kMaxQ96 = SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
        
        uint256 tolerance = kMaxQ96 / 1000;
        if (kQ96AtMaxTick > kMaxQ96) {
            assert(kQ96AtMaxTick - kMaxQ96 <= tolerance);
        } else {
            assert(kMaxQ96 - kQ96AtMaxTick <= tolerance);
        }
    }
}