// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../libraries/SphericalTickMath.sol';

contract SphericalTickMathTest {
    // Expose all internal functions for testing
    
    function getKMin(
        uint256 radiusQ96,
        uint256 sqrtNQ96
    ) external pure returns (uint256 kMinQ96) {
        return SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
    }
    
    function getKMax(
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (uint256 kMaxQ96) {
        return SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
    }
    
    function tickToPlaneConstant(
        int24 tick,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (uint256 kQ96) {
        return SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
    }
    
    function planeConstantToTick(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (int24 tick) {
        return SphericalTickMath.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96);
    }
    
    function getOrthogonalRadius(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 sqrtNQ96
    ) external pure returns (uint256 sQ96) {
        return SphericalTickMath.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96);
    }
    
    function getVirtualReserves(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (uint256 xMinQ96, uint256 xMaxQ96) {
        return SphericalTickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96);
    }
    
    function isOnTickPlane(
        uint256[] memory reserves,
        uint256 kQ96,
        uint256 sqrtNQ96
    ) external pure returns (bool isValid) {
        return SphericalTickMath.isOnTickPlane(reserves, kQ96, sqrtNQ96);
    }
    
    // Helper to expose constants
    function MAX_TICK() external pure returns (int24) {
        return SphericalTickMath.MAX_TICK;
    }
    
    function TICK_SPACING() external pure returns (int24) {
        return SphericalTickMath.TICK_SPACING;
    }
}