// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';

/// @title Spherical Position
/// @notice Simplified position tracking for sphere AMM where each tick has a single owner
/// @dev Tracks ownership and fee accumulation for individual ticks
library SphericalPosition {
    // info stored for each tick position
    struct Info {
        // the address that owns this tick's liquidity
        address owner;
        // fee growth per unit of liquidity as of the last update for each token
        // uses Q128 for maximum precision in fee accounting
        uint256[] feeGrowthInsideLastX128;
        // the fees owed to the position owner in each token
        uint128[] tokensOwed;
    }

    /// @notice Returns the position info for a specific tick
    /// @param self The mapping containing all tick positions
    /// @param tickIndex The tick index to look up
    /// @return position The position info struct for the given tick
    function get(
        mapping(int24 => Info) storage self,
        int24 tickIndex
    ) internal view returns (Info storage position) {
        position = self[tickIndex];
    }

    /// @notice Initializes a new position for a tick
    /// @param self The position to initialize
    /// @param owner The address that will own this tick
    /// @param numAssets The number of assets in the pool
    function initialize(
        Info storage self,
        address owner,
        uint256 numAssets
    ) internal {
        require(self.owner == address(0), 'PI'); // Position already initialized
        self.owner = owner;
        self.feeGrowthInsideLastX128 = new uint256[](numAssets);
        self.tokensOwed = new uint128[](numAssets);
    }

    /// @notice Updates fee accumulation for a position
    /// @dev Called when liquidity changes or fees need to be calculated
    /// @param self The position to update
    /// @param liquidity The amount of liquidity in this tick
    /// @param feeGrowthInsideX128 Current fee growth for each token
    function update(
        Info storage self,
        uint128 liquidity,
        uint256[] memory feeGrowthInsideX128
    ) internal {
        require(self.owner != address(0), 'PU'); // Position uninitialized
        require(liquidity > 0, 'NL'); // No liquidity
        
        uint256 numAssets = feeGrowthInsideX128.length;
        
        // Calculate accumulated fees for each token
        for (uint256 i = 0; i < numAssets; i++) {
            uint256 feeGrowthDelta = feeGrowthInsideX128[i] - self.feeGrowthInsideLastX128[i];
            if (feeGrowthDelta > 0) {
                uint128 tokensOwed = uint128(
                    FullMath.mulDiv(
                        feeGrowthDelta,
                        liquidity,
                        FixedPoint128.Q128
                    )
                );
                
                // Overflow is acceptable, have to withdraw before hitting max
                self.tokensOwed[i] += tokensOwed;
            }
            
            // Update last fee growth
            self.feeGrowthInsideLastX128[i] = feeGrowthInsideX128[i];
        }
    }

    /// @notice Collects accumulated fees for a position
    /// @param self The position to collect from
    /// @param amountRequested Amount requested for each token (type(uint128).max for all)
    /// @return amountCollected Actual amounts collected for each token
    function collect(
        Info storage self,
        uint128[] memory amountRequested
    ) internal returns (uint128[] memory amountCollected) {
        require(self.owner != address(0), 'PU'); // Position uninitialized
        require(msg.sender == self.owner, 'NO'); // Not owner
        
        uint256 numAssets = amountRequested.length;
        amountCollected = new uint128[](numAssets);
        
        for (uint256 i = 0; i < numAssets; i++) {
            uint128 tokensOwed = self.tokensOwed[i];
            uint128 amount = amountRequested[i] > tokensOwed ? tokensOwed : amountRequested[i];
            
            if (amount > 0) {
                self.tokensOwed[i] = tokensOwed - amount;
                amountCollected[i] = amount;
            }
        }
    }

    /// @notice Transfers ownership of a tick position
    /// @param self The position to transfer
    /// @param newOwner The new owner address
    function transferOwnership(
        Info storage self,
        address newOwner
    ) internal {
        require(self.owner != address(0), 'PU'); // Position uninitialized
        require(msg.sender == self.owner, 'NO'); // Not owner
        require(newOwner != address(0), 'ZA'); // Zero address
        
        self.owner = newOwner;
    }
}