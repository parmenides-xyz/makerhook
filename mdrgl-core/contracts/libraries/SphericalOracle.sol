// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint96.sol';

/// @title Spherical Oracle
/// @notice Provides position and liquidity data for the n-dimensional sphere AMM
/// @dev Tracks the projection α = x̄ · v̄ = Σx_i/√n over time for TWAP calculations
library SphericalOracle {
    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the alpha accumulator, i.e. α * time elapsed since pool was first initialized
        uint256 alphaCumulativeQ96;
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // whether or not the observation is initialized
        bool initialized;
    }

    /// @notice Transforms a previous observation into a new observation
    /// @dev blockTimestamp _must_ be chronologically equal to or greater than last.blockTimestamp
    /// @param last The specified observation to be transformed
    /// @param blockTimestamp The timestamp of the new observation
    /// @param alphaQ96 The current projection α in Q96 format
    /// @param liquidity The total in-range liquidity at the time of the new observation
    /// @return Observation The newly populated observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        uint256 alphaQ96,
        uint128 liquidity
    ) private pure returns (Observation memory) {
        uint32 delta = blockTimestamp - last.blockTimestamp;
        
        // Calculate alpha accumulation over time
        uint256 alphaAccumulation = FullMath.mulDiv(
            alphaQ96,
            delta,
            1
        );
        
        return
            Observation({
                blockTimestamp: blockTimestamp,
                alphaCumulativeQ96: last.alphaCumulativeQ96 + alphaAccumulation,
                secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 +
                    ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
                initialized: true
            });
    }

    /// @notice Initialize the oracle array by writing the first slot
    /// @param self The stored oracle array
    /// @param time The time of the oracle initialization, via block.timestamp truncated to uint32
    /// @return cardinality The number of populated elements in the oracle array
    /// @return cardinalityNext The new length of the oracle array
    function initialize(Observation[65535] storage self, uint32 time)
        internal
        returns (uint16 cardinality, uint16 cardinalityNext)
    {
        self[0] = Observation({
            blockTimestamp: time,
            alphaCumulativeQ96: 0,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        return (1, 1);
    }

    /// @notice Writes an oracle observation to the array
    /// @dev Writable at most once per block
    /// @param self The stored oracle array
    /// @param index The index of the observation that was most recently written
    /// @param blockTimestamp The timestamp of the new observation
    /// @param alphaQ96 The current projection α in Q96 format
    /// @param liquidity The total in-range liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @param cardinalityNext The new length of the oracle array
    /// @return indexUpdated The new index of the most recently written element
    /// @return cardinalityUpdated The new cardinality of the oracle array
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        uint256 alphaQ96,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];

        // early return if we've already written an observation this block
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // if the conditions are right, we can bump the cardinality
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        self[indexUpdated] = transform(last, blockTimestamp, alphaQ96, liquidity);
    }

    /// @notice Prepares the oracle array to store up to `next` observations
    /// @param self The stored oracle array
    /// @param current The current next cardinality of the oracle array
    /// @param next The proposed next cardinality which will be populated
    /// @return next The next cardinality which will be populated in the oracle array
    function grow(
        Observation[65535] storage self,
        uint16 current,
        uint16 next
    ) internal returns (uint16) {
        require(current > 0, 'I');
        // no-op if the passed next value isn't greater than the current next value
        if (next <= current) return current;
        // store in each slot to prevent fresh SSTOREs in swaps
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice comparator for 32-bit timestamps
    /// @dev safe for 0 or 1 overflows, a and b _must_ be chronologically before or equal to time
    /// @param time A timestamp truncated to 32 bits
    /// @param a A comparison timestamp from which to determine the relative position of `time`
    /// @param b From which to determine the relative position of `time`
    /// @return bool Whether `a` is chronologically <= `b`
    function lte(
        uint32 time,
        uint32 a,
        uint32 b
    ) private pure returns (bool) {
        // if there hasn't been overflow, no need to adjust
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2**32;
        uint256 bAdjusted = b > time ? b : b + 2**32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a target
    /// @dev Binary search through the oracle array
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param index The index of the observation that was most recently written
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation recorded before, or at, the target
    /// @return atOrAfter The observation recorded at, or after, the target
    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // oldest observation
        uint256 r = l + cardinality - 1; // newest observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // we've landed on an uninitialized tick, keep searching higher
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

            // check if we've found the answer!
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a given target
    /// @dev Assumes there is at least 1 initialized observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param alphaQ96 The current projection α
    /// @param index The index of the observation that was most recently written
    /// @param liquidity The total pool liquidity at the time of the call
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation which occurred at, or before, the given timestamp
    /// @return atOrAfter The observation which occurred at, or after, the given timestamp
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint256 alphaQ96,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // optimistically set before to the newest observation
        beforeOrAt = self[index];

        // if the target is chronologically at or after the newest observation, we can early return
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // if newest observation equals target, we're in the same block
                return (beforeOrAt, atOrAfter);
            } else {
                // otherwise, we need to transform
                return (beforeOrAt, transform(beforeOrAt, target, alphaQ96, liquidity));
            }
        }

        // now, set before to the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // ensure that the target is chronologically at or after the oldest observation
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // if we've reached this point, we have to binary search
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @notice Returns the accumulator values as of `secondsAgo`
    /// @dev 0 may be passed as `secondsAgo' to return the current cumulative values
    /// @param self The stored oracle array
    /// @param time The current block timestamp
    /// @param secondsAgo The amount of time to look back, in seconds
    /// @param alphaQ96 The current projection α
    /// @param index The index of the observation that was most recently written
    /// @param liquidity The current in-range pool liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @return alphaCumulativeQ96 The alpha * time elapsed since pool initialization
    /// @return secondsPerLiquidityCumulativeX128 The time elapsed / liquidity since pool initialization
    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        uint256 alphaQ96,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (uint256 alphaCumulativeQ96, uint160 secondsPerLiquidityCumulativeX128) {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) last = transform(last, time, alphaQ96, liquidity);
            return (last.alphaCumulativeQ96, last.secondsPerLiquidityCumulativeX128);
        }

        uint32 target = time - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, alphaQ96, index, liquidity, cardinality);

        if (target == beforeOrAt.blockTimestamp) {
            // we're at the left boundary
            return (beforeOrAt.alphaCumulativeQ96, beforeOrAt.secondsPerLiquidityCumulativeX128);
        } else if (target == atOrAfter.blockTimestamp) {
            // we're at the right boundary
            return (atOrAfter.alphaCumulativeQ96, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // we're in the middle - interpolate
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            
            // Linear interpolation of alpha cumulative
            alphaCumulativeQ96 = beforeOrAt.alphaCumulativeQ96 + 
                FullMath.mulDiv(
                    atOrAfter.alphaCumulativeQ96 - beforeOrAt.alphaCumulativeQ96,
                    targetDelta,
                    observationTimeDelta
                );
            
            // Linear interpolation of seconds per liquidity
            secondsPerLiquidityCumulativeX128 = beforeOrAt.secondsPerLiquidityCumulativeX128 +
                uint160(
                    (uint256(
                        atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128
                    ) * targetDelta) / observationTimeDelta
                );
            
            return (alphaCumulativeQ96, secondsPerLiquidityCumulativeX128);
        }
    }

    /// @notice Returns the accumulator values as of each time seconds ago
    /// @dev Reverts if `secondsAgos` > oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param secondsAgos Each amount of time to look back, in seconds
    /// @param alphaQ96 The current projection α
    /// @param index The index of the observation that was most recently written
    /// @param liquidity The current in-range pool liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @return alphaCumulatives The alpha * time elapsed since pool initialization
    /// @return secondsPerLiquidityCumulativeX128s The cumulative seconds / liquidity
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        uint256 alphaQ96,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (uint256[] memory alphaCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        require(cardinality > 0, 'I');

        alphaCumulatives = new uint256[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (alphaCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(
                self,
                time,
                secondsAgos[i],
                alphaQ96,
                index,
                liquidity,
                cardinality
            );
        }
    }

    /// @notice Given two cumulative alpha values, calculate the time-weighted average α
    /// @dev Useful for calculating TWAP position on the sphere
    /// @param alphaCumulative0 The alpha cumulative value at the beginning of the period
    /// @param alphaCumulative1 The alpha cumulative value at the end of the period
    /// @param timeElapsed The time elapsed between the two observations
    /// @return alphaAvgQ96 The time-weighted average α in Q96 format
    function getTimeWeightedAverageAlpha(
        uint256 alphaCumulative0,
        uint256 alphaCumulative1,
        uint32 timeElapsed
    ) internal pure returns (uint256 alphaAvgQ96) {
        require(timeElapsed > 0, 'BP');
        return (alphaCumulative1 - alphaCumulative0) / timeElapsed;
    }
}