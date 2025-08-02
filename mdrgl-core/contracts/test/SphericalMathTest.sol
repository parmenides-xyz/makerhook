// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import '../libraries/SphericalMath.sol';
import '../libraries/FixedPoint96.sol';
import '../libraries/FullMath.sol';

/// @title SphericalMath Test Contract
/// @notice Exposes SphericalMath library functions for testing
contract SphericalMathTest {
    using SphericalMath for SphericalMath.PoolConstants;

    function validateConstraintFromSums(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96,
        uint256 epsilonQ96
    ) external pure returns (bool valid, uint256 deviationQ96) {
        SphericalMath.PoolConstants memory constants = SphericalMath.PoolConstants({
            radiusQ96: radiusQ96,
            numAssets: numAssets,
            sqrtNumAssetsQ96: sqrtNumAssetsQ96,
            epsilonQ96: epsilonQ96
        });
        
        return SphericalMath.validateConstraintFromSums(sumReservesQ96, sumSquaresQ96, constants);
    }

    function computeOrthogonalComponent(
        uint256 sumSquaresQ96,
        uint256 sumReservesQ96,
        uint256 numAssets
    ) external pure returns (uint256 wQ96) {
        return SphericalMath.computeOrthogonalComponent(sumSquaresQ96, sumReservesQ96, numAssets);
    }

    function calculatePriceRatio(
        uint256 reserveI,
        uint256 reserveJ,
        uint256 radiusQ96
    ) external pure returns (uint256 priceQ96) {
        return SphericalMath.calculatePriceRatio(reserveI, reserveJ, radiusQ96);
    }

    // Test the full updateSumsAfterTrade function
    function updateSumsAfterTrade(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 oldReserveI,
        uint256 newReserveI,
        uint256 oldReserveJ,
        uint256 newReserveJ
    ) external pure returns (uint256 newSumReservesQ96, uint256 newSumSquaresQ96) {
        return SphericalMath.updateSumsAfterTrade(
            sumReservesQ96,
            sumSquaresQ96,
            oldReserveI,
            newReserveI,
            oldReserveJ,
            newReserveJ
        );
    }

    function sqrt(uint256 x) external pure returns (uint256) {
        return SphericalMath.sqrt(x);
    }

    // Helper function to compute sums from reserves array
    function computeSums(uint256[] memory reserves) 
        external 
        pure 
        returns (uint256 sumReservesQ96, uint256 sumSquaresQ96) 
    {
        for (uint256 i = 0; i < reserves.length; i++) {
            sumReservesQ96 = sumReservesQ96 + reserves[i];
            sumSquaresQ96 = sumSquaresQ96 + FullMath.mulDiv(reserves[i], reserves[i], FixedPoint96.Q96);
        }
        sumReservesQ96 = FullMath.mulDiv(sumReservesQ96, FixedPoint96.Q96, 1);
    }
}