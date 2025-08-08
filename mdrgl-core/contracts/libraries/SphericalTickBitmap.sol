// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './BitMath.sol';

/// @title Spherical Tick Bitmap
/// @notice Efficiently tracks initialized ticks for the spherical AMM
/// @dev Optimized for 0 to MAX_TICK range with additional boundary tracking
library SphericalTickBitmap {
    // Maximum tick value for stablecoin pools
    int24 internal constant MAX_TICK = 10000;
    
    /// @notice Computes the position in the bitmap for a given tick
    /// @param tick The tick for which to compute the position
    /// @return wordPos The key in the mapping containing the word in which the bit is stored
    /// @return bitPos The bit position in the word
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        require(tick >= 0 && tick <= MAX_TICK, "Invalid tick");
        wordPos = int16(tick >> 8);  // Divide by 256
        bitPos = uint8(tick & 0xFF); // Modulo 256
    }
    
    /// @notice Flips the initialized state for the given tick
    /// @param self The mapping in which to flip the tick
    /// @param tick The tick to flip
    /// @param tickSpacing The spacing between usable ticks
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0, "Tick not aligned");
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }
    
    /// @notice Returns the next initialized tick contained in the same word (or adjacent word)
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param searchUpwards Whether to search for the next initialized tick upwards or downwards
    /// @return next The next initialized or uninitialized tick up to 256 ticks away
    /// @return initialized Whether the next tick is initialized
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool searchUpwards
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        
        if (searchUpwards) {
            (int16 wordPos, uint8 bitPos) = position((compressed + 1) * tickSpacing);
            // all the 1s at or to the right of the current bitPos
            uint256 mask = (1 << bitPos) - 1;
            uint256 masked = self[wordPos] & ~mask;
            
            // if there are no initialized ticks to the right of the current tick, return rightmost in the word
            initialized = masked != 0;
            // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        } else {
            // start from the word of the next tick, since the current tick state doesn't matter
            (int16 wordPos, uint8 bitPos) = position((compressed - 1) * tickSpacing);
            // all the 1s at or to the left of the bitPos
            uint256 mask = (1 << (bitPos + 1)) - 1;
            uint256 masked = self[wordPos] & mask;
            
            // if there are no initialized ticks to the left of the current tick, return leftmost in the word
            initialized = masked != 0;
            // underflow is possible, but prevented externally by limiting both tickSpacing and tick
            next = initialized
                ? (compressed - 1 - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - 1 - int24(bitPos)) * tickSpacing;
        }
    }
    
    /// @notice Returns the next initialized tick in the given direction
    /// @param self The mapping of tick bitmaps
    /// @param tick The starting tick
    /// @param tickSpacing The spacing between usable ticks
    /// @param searchUpwards Whether to search upwards or downwards
    /// @return next The next initialized tick, or the boundary if none found
    /// @return found Whether an initialized tick was found
    function nextInitializedTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool searchUpwards
    ) internal view returns (int24 next, bool found) {
        // First check within the current word
        (next, found) = nextInitializedTickWithinOneWord(self, tick, tickSpacing, searchUpwards);
        
        if (!found) {
            // Search in adjacent words
            (int16 currentWordPos, ) = position(tick);
            int16 maxWordPos = int16(MAX_TICK >> 8);
            
            if (searchUpwards) {
                // Search in higher words
                for (int16 wordPos = currentWordPos + 1; wordPos <= maxWordPos; wordPos++) {
                    uint256 word = self[wordPos];
                    if (word > 0) {
                        next = (int24(wordPos) << 8) + int24(BitMath.leastSignificantBit(word));
                        // Align to tick spacing
                        next = (next / tickSpacing) * tickSpacing;
                        found = next <= MAX_TICK;
                        return (next, found);
                    }
                }
                next = MAX_TICK;
            } else {
                // Search in lower words
                for (int16 wordPos = currentWordPos - 1; wordPos >= 0; wordPos--) {
                    uint256 word = self[wordPos];
                    if (word > 0) {
                        next = (int24(wordPos) << 8) + int24(BitMath.mostSignificantBit(word));
                        // Align to tick spacing
                        next = (next / tickSpacing) * tickSpacing;
                        found = true;
                        return (next, found);
                    }
                }
                next = 0;
            }
        }
    }
    
    /// @notice Check if a tick is initialized
    /// @param self The mapping of tick bitmaps
    /// @param tick The tick to check
    /// @return Whether the tick is initialized
    function isInitialized(
        mapping(int16 => uint256) storage self,
        int24 tick
    ) internal view returns (bool) {
        require(tick >= 0 && tick <= MAX_TICK, "Invalid tick");
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        return (self[wordPos] & mask) != 0;
    }
    
    /// @notice Get all active (initialized) ticks
    /// @dev Returns array of initialized ticks for consolidation calculations
    /// @param self The mapping of tick bitmaps
    /// @param tickSpacing The spacing between usable ticks
    /// @return activeTicks Array of all initialized tick indices
    function getActiveTicks(
        mapping(int16 => uint256) storage self,
        int24 tickSpacing
    ) internal view returns (int24[] memory activeTicks) {
        uint256 count = 0;
        int16 maxWordPos = int16(MAX_TICK >> 8) + 1;
        
        // First pass: count active ticks
        for (int16 i = 0; i <= maxWordPos; i++) {
            uint256 word = self[i];
            while (word != 0) {
                word &= word - 1; // Clear least significant bit set
                count++;
            }
        }
        
        // Second pass: collect active ticks
        activeTicks = new int24[](count);
        uint256 index = 0;
        
        for (int16 i = 0; i <= maxWordPos; i++) {
            uint256 word = self[i];
            while (word != 0) {
                uint8 bitPos = BitMath.leastSignificantBit(word);
                int24 tick = (int24(i) << 8) + int24(bitPos);
                // Ensure tick is aligned to spacing
                if (tick % tickSpacing == 0 && tick <= MAX_TICK) {
                    activeTicks[index++] = tick;
                }
                word &= word - 1; // Clear the bit we just processed
            }
        }
        
        // Resize array if needed (in case some ticks weren't aligned)
        if (index < count) {
            int24[] memory resized = new int24[](index);
            for (uint256 i = 0; i < index; i++) {
                resized[i] = activeTicks[i];
            }
            return resized;
        }
        
        return activeTicks;
    }
    
    /// @notice Counts the number of initialized ticks
    /// @param self The mapping of tick bitmaps
    /// @return count The number of initialized ticks
    function countInitializedTicks(
        mapping(int16 => uint256) storage self
    ) internal view returns (uint256 count) {
        int16 maxWordPos = int16(MAX_TICK >> 8) + 1;
        
        for (int16 i = 0; i <= maxWordPos; i++) {
            uint256 word = self[i];
            while (word != 0) {
                word &= word - 1; // Clear least significant bit set
                count++;
            }
        }
    }
}

/// @title Spherical Boundary Bitmap
/// @notice Tracks which initialized ticks are at their boundary
/// @dev Separate bitmap for efficient boundary status tracking
library SphericalBoundaryBitmap {
    /// @notice Sets the boundary status for a tick
    /// @param self The mapping of boundary bitmaps
    /// @param tick The tick to update
    /// @param isAtBoundary Whether the tick is at its boundary
    function setBoundaryStatus(
        mapping(int16 => uint256) storage self,
        int24 tick,
        bool isAtBoundary
    ) internal {
        require(tick >= 0 && tick <= SphericalTickBitmap.MAX_TICK, "Invalid tick");
        int16 wordPos = int16(tick >> 8);
        uint8 bitPos = uint8(tick & 0xFF);
        uint256 mask = 1 << bitPos;
        
        if (isAtBoundary) {
            self[wordPos] |= mask;  // Set bit to 1
        } else {
            self[wordPos] &= ~mask; // Clear bit to 0
        }
    }
    
    /// @notice Checks if a tick is at its boundary
    /// @param self The mapping of boundary bitmaps
    /// @param tick The tick to check
    /// @return Whether the tick is at its boundary
    function isAtBoundary(
        mapping(int16 => uint256) storage self,
        int24 tick
    ) internal view returns (bool) {
        require(tick >= 0 && tick <= SphericalTickBitmap.MAX_TICK, "Invalid tick");
        int16 wordPos = int16(tick >> 8);
        uint8 bitPos = uint8(tick & 0xFF);
        uint256 mask = 1 << bitPos;
        return (self[wordPos] & mask) != 0;
    }
    
    /// @notice Gets all ticks that are at their boundary
    /// @param tickBitmap The initialized tick bitmap
    /// @param boundaryBitmap The boundary status bitmap
    /// @return boundaryTicks Array of ticks at their boundary
    function getBoundaryTicks(
        mapping(int16 => uint256) storage tickBitmap,
        mapping(int16 => uint256) storage boundaryBitmap
    ) internal view returns (int24[] memory boundaryTicks) {
        uint256 count = 0;
        int16 maxWordPos = int16(SphericalTickBitmap.MAX_TICK >> 8) + 1;
        
        // First pass: count boundary ticks
        for (int16 i = 0; i <= maxWordPos; i++) {
            // Only check boundary status for initialized ticks
            uint256 boundaryWord = tickBitmap[i] & boundaryBitmap[i];
            while (boundaryWord != 0) {
                boundaryWord &= boundaryWord - 1;
                count++;
            }
        }
        
        // Second pass: collect boundary ticks
        boundaryTicks = new int24[](count);
        uint256 index = 0;
        
        for (int16 i = 0; i <= maxWordPos; i++) {
            uint256 boundaryWord = tickBitmap[i] & boundaryBitmap[i];
            while (boundaryWord != 0) {
                uint8 bitPos = BitMath.leastSignificantBit(boundaryWord);
                boundaryTicks[index++] = (int24(i) << 8) + int24(bitPos);
                boundaryWord &= boundaryWord - 1;
            }
        }
        
        return boundaryTicks;
    }
    
    /// @notice Flips the boundary status of a tick
    /// @param self The mapping of boundary bitmaps
    /// @param tick The tick to flip
    function flipBoundaryStatus(
        mapping(int16 => uint256) storage self,
        int24 tick
    ) internal {
        require(tick >= 0 && tick <= SphericalTickBitmap.MAX_TICK, "Invalid tick");
        int16 wordPos = int16(tick >> 8);
        uint8 bitPos = uint8(tick & 0xFF);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }
}