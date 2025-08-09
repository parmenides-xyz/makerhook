// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import '../libraries/SphericalTick.sol';

contract SphericalTickTest {
    using SphericalTick for mapping(int24 => SphericalTick.Info);

    mapping(int24 => SphericalTick.Info) public ticks;

    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) external pure returns (uint128) {
        return SphericalTick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
    }

    function update(
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256[] memory feeGrowthGlobal,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity,
        uint256 numAssets
    ) external returns (bool flipped) {
        return ticks.update(
            tick,
            tickCurrent,
            liquidityDelta,
            feeGrowthGlobal,
            secondsPerLiquidityCumulativeX128,
            tickCumulative,
            time,
            upper,
            maxLiquidity,
            numAssets
        );
    }

    function clear(int24 tick, uint256 numAssets) external {
        ticks.clear(tick, numAssets);
    }

    function initializeGeometry(
        int24 tick,
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96
    ) external {
        SphericalTick.PoolGeometry memory geometry = SphericalTick.PoolGeometry({
            radiusQ96: radiusQ96,
            n: numAssets,
            sqrtNQ96: sqrtNumAssetsQ96
        });
        SphericalTick.initializeGeometry(ticks[tick], tick, radiusQ96, geometry);
    }

    // Set individual tick fields for testing
    function setTickLiquidity(
        int24 tick,
        uint128 liquidityGross,
        int128 liquidityNet
    ) external {
        ticks[tick].liquidityGross = liquidityGross;
        ticks[tick].liquidityNet = liquidityNet;
    }
    
    function setTickState(
        int24 tick,
        bool initialized,
        bool isAtBoundary
    ) external {
        ticks[tick].initialized = initialized;
        ticks[tick].isAtBoundary = isAtBoundary;
    }
    
    function setTickAccumulators(
        int24 tick,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside
    ) external {
        ticks[tick].tickCumulativeOutside = tickCumulativeOutside;
        ticks[tick].secondsPerLiquidityOutsideX128 = secondsPerLiquidityOutsideX128;
        ticks[tick].secondsOutside = secondsOutside;
    }
    
    function setTickGeometry(
        int24 tick,
        uint256 radiusQ96,
        uint256 kQ96,
        uint256 kNormQ96
    ) external {
        ticks[tick].radiusQ96 = radiusQ96;
        ticks[tick].kQ96 = kQ96;
        ticks[tick].kNormQ96 = kNormQ96;
    }
    
    function setTickAlpha(
        int24 tick,
        uint256 alphaCumulativeLastQ96,
        uint32 timestampLast
    ) external {
        ticks[tick].alphaCumulativeLastQ96 = alphaCumulativeLastQ96;
        ticks[tick].timestampLast = timestampLast;
    }
    
    // Get tick info (excluding mappings)
    function getTickInfo(int24 tick) external view returns (
        uint128 liquidityGross,
        int128 liquidityNet,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized,
        bool isAtBoundary
    ) {
        SphericalTick.Info storage info = ticks[tick];
        return (
            info.liquidityGross,
            info.liquidityNet,
            info.tickCumulativeOutside,
            info.secondsPerLiquidityOutsideX128,
            info.secondsOutside,
            info.initialized,
            info.isAtBoundary
        );
    }
    
    function getTickGeometry(int24 tick) external view returns (
        uint256 radiusQ96,
        uint256 kQ96,
        uint256 kNormQ96,
        uint256 alphaCumulativeLastQ96,
        uint32 timestampLast
    ) {
        SphericalTick.Info storage info = ticks[tick];
        return (
            info.radiusQ96,
            info.kQ96,
            info.kNormQ96,
            info.alphaCumulativeLastQ96,
            info.timestampLast
        );
    }

    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256[] memory feeGrowthGlobalX128,
        uint256 numAssets
    ) external view returns (uint256[] memory feeGrowthInsideX128) {
        return ticks.getFeeGrowthInside(
            tickLower,
            tickUpper,
            tickCurrent,
            feeGrowthGlobalX128,
            numAssets
        );
    }

    function cross(
        int24 tick,
        uint256[] memory feeGrowthGlobalX128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        uint256 numAssets
    ) external returns (int128 liquidityNet) {
        return ticks.cross(
            tick,
            feeGrowthGlobalX128,
            secondsPerLiquidityCumulativeX128,
            tickCumulative,
            time,
            numAssets
        );
    }

    function updateBoundaryStatus(
        int24 tick,
        bool isAtBoundary
    ) external {
        ticks.updateBoundaryStatus(tick, isAtBoundary);
    }

    function validateLiquidityAtTick(
        int24 tick,
        int128 liquidityDelta,
        uint128 currentLiquidity,
        uint256 radiusQ96,
        uint256 numAssets,
        uint256 sqrtNumAssetsQ96
    ) external pure returns (bool valid, string memory reason) {
        SphericalTick.PoolGeometry memory geometry = SphericalTick.PoolGeometry({
            radiusQ96: radiusQ96,
            n: numAssets,
            sqrtNQ96: sqrtNumAssetsQ96
        });
        return SphericalTick.validateLiquidityAtTick(
            tick,
            liquidityDelta,
            currentLiquidity,
            geometry
        );
    }

    // Helper function to set individual fee growth for a token
    function setFeeGrowthOutside(int24 tick, uint256 tokenIndex, uint256 feeGrowth) external {
        ticks[tick].feeGrowthOutsideX128[tokenIndex] = feeGrowth;
    }

    // Helper function to get individual fee growth for a token
    function getFeeGrowthOutside(int24 tick, uint256 tokenIndex) external view returns (uint256) {
        return ticks[tick].feeGrowthOutsideX128[tokenIndex];
    }
}