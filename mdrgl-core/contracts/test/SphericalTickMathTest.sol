// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import '../libraries/SphericalTickMath.sol';
import '../libraries/FixedPoint96.sol';

contract SphericalTickMathTest {
    int24 public constant MAX_TICK = 10000;
    int24 public constant TICK_SPACING = 1;
    
    function getKMin(
        uint256 radiusQ96,
        uint256 sqrtNQ96
    ) external pure returns (uint256) {
        return SphericalTickMath.getKMin(radiusQ96, sqrtNQ96);
    }
    
    function getKMax(
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (uint256) {
        return SphericalTickMath.getKMax(radiusQ96, n, sqrtNQ96);
    }
    
    function tickToPlaneConstant(
        int24 tick,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (uint256) {
        return SphericalTickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96);
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
    
    function planeConstantToTick(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 n,
        uint256 sqrtNQ96
    ) external pure returns (int24) {
        return SphericalTickMath.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96);
    }
    
    function isOnTickPlane(
        uint256[] memory reserves,
        uint256 kQ96,
        uint256 sqrtNQ96
    ) external pure returns (bool) {
        return SphericalTickMath.isOnTickPlane(reserves, kQ96, sqrtNQ96);
    }
}