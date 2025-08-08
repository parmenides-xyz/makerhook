// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Permissionless pool actions
/// @notice Contains pool methods that can be called by anyone
interface ISphericalPoolActions {
    /// @notice Sets the initial reserves for the pool
    /// @dev Can only be called once when the pool is first created
    /// @param initialReserves The initial reserve amounts for each token
    function initialize(uint256[] calldata initialReserves) external;

    /// @notice Adds liquidity to a specific tick
    /// @dev The caller receives a callback to transfer tokens
    /// Each tick can only have one owner in the spherical AMM model
    /// @param tick The tick index to add liquidity to
    /// @param liquidity The amount of liquidity to add
    /// @param data Any data to pass through to the callback
    /// @return amounts The amounts of each token that were paid
    function mint(
        int24 tick,
        uint128 liquidity,
        bytes calldata data
    ) external returns (uint256[] memory amounts);

    /// @notice Removes liquidity from a tick
    /// @dev Can only be called by the tick owner
    /// @param tick The tick to remove liquidity from
    /// @param liquidity The amount of liquidity to remove
    /// @return amounts The amounts of each token returned
    function burn(
        int24 tick,
        uint128 liquidity
    ) external returns (uint256[] memory amounts);

    /// @notice Collects tokens owed to a tick position
    /// @dev Must be called by the position owner
    /// @param tick The tick to collect fees from
    /// @param recipient The address to receive the fees
    /// @param amountRequested Maximum amounts to collect for each token
    /// @return amounts The amounts actually collected for each token
    function collect(
        int24 tick,
        address recipient,
        uint128[] calldata amountRequested
    ) external returns (uint128[] memory amounts);

    /// @notice Swap one token for another
    /// @dev The caller receives a callback to transfer the input token
    /// Uses Newton's method to solve the toroidal invariant
    /// @param recipient The address to receive the output token
    /// @param tokenIndexIn The index of the input token
    /// @param tokenIndexOut The index of the output token
    /// @param amountIn The amount of input token to swap
    /// @param amountOutMinimum The minimum amount of output token to receive
    /// @param data Any data to pass through to the callback
    /// @return amountOut The amount of output token received
    function swap(
        address recipient,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata data
    ) external returns (uint256 amountOut);

    /// @notice Flash loan tokens from the pool
    /// @dev The caller receives a callback and must return tokens plus fee
    /// @param recipient The address to receive the tokens
    /// @param amounts The amounts of each token to borrow
    /// @param data Any data to pass through to the callback
    function flash(
        address recipient,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    /// @notice Increase the maximum number of observations stored
    /// @dev Observations track the projection α over time for TWAP
    /// @param observationCardinalityNext The desired minimum number of observations
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;

    /// @notice Update consolidated tick parameters after state changes
    /// @dev Called internally when ticks transition between interior/boundary
    function updateConsolidatedTickParams() external;
}