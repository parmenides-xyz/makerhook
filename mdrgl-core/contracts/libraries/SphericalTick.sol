// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';
import './SphericalTickMath.sol';
import './LiquidityMath.sol';
import './FullMath.sol';
import './FixedPoint96.sol';

/// @title SphericalTick
/// @notice Contains functions for managing tick processes in n-dimensional sphere AMM
/// @dev Adapted from Uniswap V3's Tick library for multi-asset pools with plane boundaries
library SphericalTick {
    using LowGasSafeMath for int256;
    using SafeCast for int256;

    /// @notice Pool geometry parameters needed for tick calculations
    struct PoolGeometry {
        uint256 radiusQ96;
        uint256 n;  // number of assets
        uint256 sqrtNQ96;
    }

    // info stored for each initialized individual tick
    struct Info {
        // the total position liquidity that references this tick
        uint128 liquidityGross;
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
        int128 liquidityNet;
        // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        // Maps tokenId => feeGrowthOutside for n-asset support
        mapping(uint256 => uint256) feeGrowthOutsideX128;
        // the cumulative tick value on the other side of the tick
        int56 tickCumulativeOutside;
        // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint160 secondsPerLiquidityOutsideX128;
        // the seconds spent on the other side of the tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint32 secondsOutside;
        // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
        // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
        bool initialized;
        // tracks if this tick's reserves are currently at the plane boundary
        bool isAtBoundary;
        // Tick-specific geometric parameters
        uint256 radiusQ96;         // The tick's sphere radius
        uint256 kQ96;              // Plane constant x̄ · v̄ = k
        uint256 kNormQ96;          // Normalized k value (k/r) for efficient comparison
        // Alpha tracking for this tick
        uint256 alphaCumulativeLastQ96;  // Last recorded cumulative alpha when tick was updated
        uint32 timestampLast;            // Timestamp of last update
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed within the pool constructor
    /// @param tickSpacing The amount of required tick separation (fixed at 1 for sphere AMM)
    /// @return The max liquidity per tick
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        // For sphere AMM: ticks range from 0 to MAX_TICK (10000)
        require(tickSpacing > 0, 'TICK_SPACING');
        
        // Calculate based on SphericalTickMath constants
        int24 minTick = 0;
        int24 maxTick = SphericalTickMath.MAX_TICK;
        
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        return type(uint128).max / numTicks;
    }

    /// @notice Retrieves fee growth data for n assets
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @param tickCurrent The current tick
    /// @param feeGrowthGlobalX128 Array of all-time global fee growth per unit of liquidity for each token
    /// @param numAssets Number of tokens in the pool
    /// @return feeGrowthInsideX128 Array of all-time fee growth per unit of liquidity inside the position's tick boundaries
    function getFeeGrowthInside(
        mapping(int24 => Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256[] memory feeGrowthGlobalX128,
        uint256 numAssets
    ) internal view returns (uint256[] memory feeGrowthInsideX128) {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];
        
        feeGrowthInsideX128 = new uint256[](numAssets);
        
        // Calculate fee growth for each token
        for (uint256 i = 0; i < numAssets; i++) {
            uint256 feeGrowthBelowX128;
            uint256 feeGrowthAboveX128;
            
            // calculate fee growth below
            if (tickCurrent >= tickLower) {
                feeGrowthBelowX128 = lower.feeGrowthOutsideX128[i];
            } else {
                feeGrowthBelowX128 = feeGrowthGlobalX128[i] - lower.feeGrowthOutsideX128[i];
            }
            
            // calculate fee growth above
            if (tickCurrent < tickUpper) {
                feeGrowthAboveX128 = upper.feeGrowthOutsideX128[i];
            } else {
                feeGrowthAboveX128 = feeGrowthGlobalX128[i] - upper.feeGrowthOutsideX128[i];
            }
            
            feeGrowthInsideX128[i] = feeGrowthGlobalX128[i] - feeGrowthBelowX128 - feeGrowthAboveX128;
        }
    }

    /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tick The tick that will be updated
    /// @param tickCurrent The current tick
    /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
    /// @param feeGrowthGlobalX128 Array of all-time global fee growth per unit of liquidity for each token
    /// @param secondsPerLiquidityCumulativeX128 The all-time seconds per max(1, liquidity) of the pool
    /// @param tickCumulative The tick * time elapsed since the pool was first initialized
    /// @param time The current block timestamp cast to a uint32
    /// @param upper true for updating a position's upper tick, or false for updating a position's lower tick
    /// @param maxLiquidity The maximum liquidity allocation for a single tick
    /// @param numAssets Number of tokens in the pool
    /// @return flipped Whether the tick was flipped from initialized to uninitialized, or vice versa
    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256[] memory feeGrowthGlobalX128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity,
        uint256 numAssets
    ) internal returns (bool flipped) {
        Info storage info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, 'LO');

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= tickCurrent) {
                for (uint256 i = 0; i < numAssets; i++) {
                    info.feeGrowthOutsideX128[i] = feeGrowthGlobalX128[i];
                }
                info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
                info.tickCumulativeOutside = tickCumulative;
                info.secondsOutside = time;
            }
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // when the lower (upper) tick is crossed left to right (right to left), liquidity must be added (removed)
        info.liquidityNet = upper
            ? int256(info.liquidityNet).sub(liquidityDelta).toInt128()
            : int256(info.liquidityNet).add(liquidityDelta).toInt128();
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clear(mapping(int24 => Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    /// @notice Transitions to next tick as needed by price movement
    /// @param self The mapping containing all tick information for initialized ticks
    /// @param tick The destination tick of the transition
    /// @param feeGrowthGlobalX128 Array of all-time global fee growth per unit of liquidity for each token
    /// @param secondsPerLiquidityCumulativeX128 The current seconds per liquidity
    /// @param tickCumulative The tick * time elapsed since the pool was first initialized
    /// @param time The current block.timestamp
    /// @param numAssets Number of tokens in the pool
    /// @return liquidityNet The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
    function cross(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint256[] memory feeGrowthGlobalX128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        uint256 numAssets
    ) internal returns (int128 liquidityNet) {
        Info storage info = self[tick];
        
        // Update fee growth for each token
        for (uint256 i = 0; i < numAssets; i++) {
            info.feeGrowthOutsideX128[i] = feeGrowthGlobalX128[i] - info.feeGrowthOutsideX128[i];
        }
        
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
        info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
        info.secondsOutside = time - info.secondsOutside;
        liquidityNet = info.liquidityNet;
    }

    /// @notice Updates the boundary status of a tick
    /// @dev Called by the pool when reserves hit or leave the plane boundary
    /// @param self The mapping containing all tick information
    /// @param tick The tick to update
    /// @param isAtBoundary Whether the tick is now at its boundary
    function updateBoundaryStatus(
        mapping(int24 => Info) storage self,
        int24 tick,
        bool isAtBoundary
    ) internal {
        Info storage info = self[tick];
        info.isAtBoundary = isAtBoundary;
    }

    /// @notice Validates if liquidity can be provided at a tick given virtual reserve constraints
    /// @param tick The tick to validate
    /// @param liquidityDelta The liquidity change to validate
    /// @param currentLiquidity Current liquidity at the tick
    /// @param geometry Pool geometry parameters
    /// @return valid Whether the liquidity can be provided
    /// @return reason Validation failure reason if not valid
    function validateLiquidityAtTick(
        int24 tick,
        int128 liquidityDelta,
        uint128 currentLiquidity,
        PoolGeometry memory geometry
    ) internal pure returns (bool valid, string memory reason) {
        // Removing liquidity is always valid
        if (liquidityDelta <= 0) return (true, "");
        
        // Get the plane constant for this tick
        uint256 kQ96 = SphericalTickMath.tickToPlaneConstant(
            tick,
            geometry.radiusQ96,
            geometry.n,
            geometry.sqrtNQ96
        );
        
        // Get virtual reserves at this tick boundary
        // These are exact calculations from the paper:
        // x_min = (k√n - √(k²n - n((n-1)r - k√n)²))/n
        // x_max = min(r, (k√n + √(k²n - n((n-1)r - k√n)²))/n)
        (uint256 xMinQ96, ) = SphericalTickMath.getVirtualReserves(
            kQ96,
            geometry.radiusQ96,
            geometry.n,
            geometry.sqrtNQ96
        );
        
        // Validate geometric constraints
        if (xMinQ96 == 0) {
            return (false, "Invalid tick: x_min is zero");
        }
        
        // Validate k is within valid range
        uint256 kMinQ96 = SphericalTickMath.getKMin(geometry.radiusQ96, geometry.sqrtNQ96);
        uint256 kMaxQ96 = SphericalTickMath.getKMax(geometry.radiusQ96, geometry.n, geometry.sqrtNQ96);
        
        if (kQ96 < kMinQ96 || kQ96 > kMaxQ96) {
            return (false, "Tick plane constant outside valid range");
        }
        
        // Ensure resulting liquidity is positive
        uint128 newLiquidity = LiquidityMath.addDelta(currentLiquidity, liquidityDelta);
        if (newLiquidity == 0) {
            return (false, "Resulting liquidity would be zero");
        }
        
        return (true, "");
    }
    
    /// @notice Check if reserves are at a tick's plane boundary
    /// @dev Verifies if x̄ · v̄ = k within tolerance
    /// @param reserves Current reserve amounts (in Q96)
    /// @param tick The tick to check against
    /// @param geometry Pool geometry parameters
    /// @return isAtBoundary True if reserves lie on the tick plane
    function checkReservesAtBoundary(
        uint256[] memory reserves,
        int24 tick,
        PoolGeometry memory geometry
    ) internal pure returns (bool isAtBoundary) {
        // Get the plane constant for this tick
        uint256 kQ96 = SphericalTickMath.tickToPlaneConstant(
            tick,
            geometry.radiusQ96,
            geometry.n,
            geometry.sqrtNQ96
        );
        
        // Use SphericalTickMath's exact check
        isAtBoundary = SphericalTickMath.isOnTickPlane(
            reserves,
            kQ96,
            geometry.sqrtNQ96
        );
    }

    /// @notice Result of tick crossing detection
    struct CrossingResult {
        bool willCross;
        int24 tickToCross;
        bool crossingTowardsBoundary;  // true: interior->boundary, false: boundary->interior
        uint256 crossingPointQ96;      // The α value where crossing occurs
    }

    /// @notice Check if a trade would cause a tick crossing
    /// @dev Compares projected position against tick boundaries
    /// @param self The mapping containing all tick information
    /// @param activeTicks Array of currently active tick indices
    /// @param projectedAlphaQ96 Projected projection after trade
    /// @return result Information about potential crossing
    function detectCrossing(
        mapping(int24 => Info) storage self,
        int24[] memory activeTicks,
        uint256 projectedAlphaQ96
    ) internal view returns (CrossingResult memory result) {
        uint256 minInteriorK = type(uint256).max;
        uint256 maxBoundaryK = 0;
        int24 nextInteriorTick = -1;
        int24 nextBoundaryTick = -1;
        
        // Find the closest ticks to crossing
        for (uint256 i = 0; i < activeTicks.length; i++) {
            Info storage info = self[activeTicks[i]];
            if (info.liquidityGross == 0) continue;
            
            if (!info.isAtBoundary) {
                // Interior tick - check if it would hit boundary
                if (info.kQ96 < minInteriorK) {
                    minInteriorK = info.kQ96;
                    nextInteriorTick = activeTicks[i];
                }
            } else {
                // Boundary tick - check if it would become interior
                if (info.kQ96 > maxBoundaryK) {
                    maxBoundaryK = info.kQ96;
                    nextBoundaryTick = activeTicks[i];
                }
            }
        }
        
        // Check for interior->boundary crossing
        if (projectedAlphaQ96 >= minInteriorK && nextInteriorTick >= 0) {
            result.willCross = true;
            result.tickToCross = nextInteriorTick;
            result.crossingTowardsBoundary = true;
            result.crossingPointQ96 = minInteriorK;
        }
        // Check for boundary->interior crossing
        else if (projectedAlphaQ96 <= maxBoundaryK && nextBoundaryTick >= 0) {
            result.willCross = true;
            result.tickToCross = nextBoundaryTick;
            result.crossingTowardsBoundary = false;
            result.crossingPointQ96 = maxBoundaryK;
        }
    }

    /// @notice Initialize geometric parameters for a tick
    /// @dev Called when tick is first initialized with liquidity
    /// @param self The tick info to update
    /// @param tick The tick index
    /// @param radiusQ96 The tick's sphere radius
    /// @param geometry Pool geometry parameters
    function initializeGeometry(
        Info storage self,
        int24 tick,
        uint256 radiusQ96,
        PoolGeometry memory geometry
    ) internal {
        // Calculate k from tick index
        uint256 kQ96 = SphericalTickMath.tickToPlaneConstant(
            tick,
            radiusQ96,
            geometry.n,
            geometry.sqrtNQ96
        );
        
        // Store geometric parameters
        self.radiusQ96 = radiusQ96;
        self.kQ96 = kQ96;
        self.kNormQ96 = FullMath.mulDiv(kQ96, FixedPoint96.Q96, radiusQ96);
    }

    /// @notice Information about a tick state change
    struct TickStateChange {
        int24 tickIndex;           // Which tick changed state
        bool wasInterior;          // State before the change
        bool isInterior;           // State after the change
        uint256 newRadiusQ96;      // New radius after state change (0 if no longer contributing)
        uint256 newKQ96;           // New k value after state change (0 if no longer contributing)
    }

    /// @notice Apply a state change from tick consolidation
    /// @dev Updates the boundary status after a crossing
    /// @param self The mapping containing all tick information
    /// @param stateChange The state change to apply
    function applyStateChange(
        mapping(int24 => Info) storage self,
        TickStateChange memory stateChange
    ) internal {
        Info storage info = self[stateChange.tickIndex];
        
        // Update boundary status
        info.isAtBoundary = stateChange.isInterior ? false : true;
        
        // Note: The actual updating of consolidated parameters happens in the pool
        // This just updates the individual tick's status
    }

    /// @notice Consolidated tick parameters for coefficient calculations
    struct ConsolidatedTickParams {
        uint256 radiusInteriorQ96;   // r_int = Σr_i for interior ticks
        uint256 radiusBoundaryQ96;   // s_bound = Σs_i for boundary ticks
        uint256 kBoundaryQ96;        // k_bound = Σk_i for boundary ticks
    }

    /// @notice Get consolidated parameters from active ticks
    /// @dev Sums up interior radii and boundary parameters
    /// @param self The mapping containing all tick information
    /// @param activeTicks Array of currently active tick indices
    /// @param geometry Pool geometry parameters
    /// @return params Consolidated parameters for coefficient calculations
    function getConsolidatedParams(
        mapping(int24 => Info) storage self,
        int24[] memory activeTicks,
        PoolGeometry memory geometry
    ) internal view returns (ConsolidatedTickParams memory params) {
        for (uint256 i = 0; i < activeTicks.length; i++) {
            Info storage info = self[activeTicks[i]];
            if (info.liquidityGross == 0) continue;
            
            if (!info.isAtBoundary) {
                // Interior tick - contributes radius
                params.radiusInteriorQ96 = params.radiusInteriorQ96 + info.radiusQ96;
            } else {
                // Boundary tick - contributes k and orthogonal radius
                params.kBoundaryQ96 = params.kBoundaryQ96 + info.kQ96;
                
                // Calculate orthogonal radius s = √(r² - (k - r√n)²)
                uint256 sQ96 = SphericalTickMath.getOrthogonalRadius(
                    info.kQ96,
                    info.radiusQ96,
                    geometry.sqrtNQ96
                );
                params.radiusBoundaryQ96 = params.radiusBoundaryQ96 + sQ96;
            }
        }
    }
}