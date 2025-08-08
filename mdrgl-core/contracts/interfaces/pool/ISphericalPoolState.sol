// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Pool state that can change
/// @notice Contains view functions to access pool state variables
interface ISphericalPoolState {
    /// @notice The current reserves for each token
    /// @return reserves Array of current token reserves
    function getReserves() external view returns (uint256[] memory reserves);

    /// @notice The reserve of a specific token
    /// @param tokenIndex The index of the token
    /// @return The current reserve amount
    function getReserve(uint256 tokenIndex) external view returns (uint256);

    /// @notice The sum of all reserves in Q96 format
    /// @dev Used in invariant calculations
    /// @return The sum in Q96
    function sumReservesQ96() external view returns (uint256);

    /// @notice The sum of squared reserves in Q96 format
    /// @dev Used in orthogonal component calculations
    /// @return The sum of squares in Q96
    function sumSquaresQ96() external view returns (uint256);

    /// @notice The current projection α = x̄ · v̄ in Q96 format
    /// @dev Represents the position on the equal-price vector
    /// @return The projection value in Q96
    function alphaQ96() external view returns (uint256);

    /// @notice The 0th storage slot of the pool
    /// @dev Contains global state that is frequently accessed
    /// @return alphaQ96 The current projection α
    /// @return observationIndex The index of the last oracle observation
    /// @return observationCardinality The current maximum capacity of the oracle
    /// @return observationCardinalityNext The next maximum capacity of the oracle
    /// @return feeProtocol The protocol fee for token swaps
    /// @return unlocked Whether the pool is currently locked to reentrancy
    function slot0()
        external
        view
        returns (
            uint256 alphaQ96,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice The currently active ticks
    /// @dev Ticks with non-zero liquidity
    /// @return Array of active tick indices
    function getActiveTicks() external view returns (int24[] memory);

    /// @notice Information about a specific tick
    /// @param tick The tick index
    /// @return liquidityGross Total liquidity referencing this tick
    /// @return liquidityNet Net liquidity when tick is crossed left to right
    /// @return isAtBoundary Whether the tick is at its boundary
    /// @return owner The owner of this tick's liquidity
    function tickInfo(int24 tick)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            bool isAtBoundary,
            address owner
        );

    /// @notice The consolidated parameters from all active ticks
    /// @return radiusInteriorQ96 Sum of radii from interior ticks
    /// @return radiusBoundaryQ96 Sum of orthogonal radii from boundary ticks
    /// @return kBoundaryQ96 Sum of k values from boundary ticks
    function consolidatedTickParams()
        external
        view
        returns (
            uint256 radiusInteriorQ96,
            uint256 radiusBoundaryQ96,
            uint256 kBoundaryQ96
        );

    /// @notice The pool's total liquidity
    /// @return The currently in-range liquidity
    function liquidity() external view returns (uint128);

    /// @notice The fee growth per unit of liquidity for each token
    /// @dev Stored as a Q128 fixed-point number
    /// @return Array of fee growth values for each token
    function feeGrowthGlobalX128() external view returns (uint256[] memory);

    /// @notice The amounts owed for a specific tick position
    /// @param tick The tick index
    /// @return tokensOwed Array of amounts owed for each token
    function positionTokensOwed(int24 tick) 
        external 
        view 
        returns (uint128[] memory tokensOwed);

    /// @notice Observations stored for TWAP calculations
    /// @param index The observation index
    /// @return blockTimestamp The timestamp of the observation
    /// @return alphaCumulativeQ96 The alpha accumulator value
    /// @return secondsPerLiquidityCumulativeX128 The seconds per liquidity accumulator
    /// @return initialized Whether the observation is initialized
    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            uint256 alphaCumulativeQ96,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );
}