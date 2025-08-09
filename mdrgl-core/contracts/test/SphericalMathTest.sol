// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import '../libraries/SphericalMathNew.sol';
import '../libraries/FixedPoint96.sol';

contract SphericalMathTest {
    function sqrt(uint256 x) external pure returns (uint256) {
        return SphericalMathNew.sqrt(x);
    }
    
    function computeOrthogonalComponent(
        uint256 sumSquaresQ96,
        uint256 sumReservesQ96,
        uint256 numAssets
    ) external pure returns (uint256) {
        return SphericalMathNew.computeOrthogonalComponent(sumSquaresQ96, sumReservesQ96, numAssets);
    }
    
    function calculatePriceRatio(
        uint256 reserveI,
        uint256 reserveJ,
        uint256 radiusQ96
    ) external pure returns (uint256) {
        return SphericalMathNew.calculatePriceRatio(reserveI, reserveJ, radiusQ96);
    }
    
    function updateSumsAfterTrade(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 oldReserveI,
        uint256 newReserveI,
        uint256 oldReserveJ,
        uint256 newReserveJ
    ) external pure returns (uint256 newSumReserves, uint256 newSumSquares) {
        return SphericalMathNew.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            oldReserveI,
            newReserveI,
            oldReserveJ,
            newReserveJ
        );
    }
    
    function validateConstraintFromSums(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96,
        uint256 epsilonQ96
    ) external pure returns (bool valid, uint256 deviationQ96) {
        return SphericalMathNew.validateConstraintFromSums(
            sumReservesQ96,
            sumSquaresQ96,
            radiusQ96,
            numAssets,
            sqrtNumAssetsQ96,
            epsilonQ96
        );
    }
    
    function validatePoolConstants(
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96,
        uint256 epsilonQ96
    ) external pure {
        SphericalMathNew.validatePoolConstants(
            radiusQ96,
            numAssets,
            sqrtNumAssetsQ96,
            epsilonQ96
        );
    }
}