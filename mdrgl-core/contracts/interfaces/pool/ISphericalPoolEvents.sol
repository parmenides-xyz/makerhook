// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Events emitted by a spherical AMM pool
/// @notice Contains all events emitted by the pool
interface ISphericalPoolEvents {
    /// @notice Emitted when the pool is initialized
    /// @param initialReserves The initial reserves for each token
    /// @param alphaQ96 The initial projection value
    event Initialize(uint256[] initialReserves, uint256 alphaQ96);

    /// @notice Emitted when liquidity is added to a tick
    /// @param owner The owner of the position
    /// @param tick The tick that received liquidity
    /// @param liquidity The amount of liquidity added
    /// @param amounts The amounts of each token added
    event Mint(
        address indexed owner,
        int24 indexed tick,
        uint128 liquidity,
        uint256[] amounts
    );

    /// @notice Emitted when liquidity is removed from a tick
    /// @param owner The owner of the position
    /// @param tick The tick that had liquidity removed
    /// @param liquidity The amount of liquidity removed
    /// @param amounts The amounts of each token removed
    event Burn(
        address indexed owner,
        int24 indexed tick,
        uint128 liquidity,
        uint256[] amounts
    );

    /// @notice Emitted when fees are collected
    /// @param owner The owner collecting fees
    /// @param recipient The address receiving the fees
    /// @param tick The tick from which fees were collected
    /// @param amounts The amounts of each token collected
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tick,
        uint128[] amounts
    );

    /// @notice Emitted when a swap occurs
    /// @param sender The address initiating the swap
    /// @param recipient The address receiving the output
    /// @param tokenIndexIn Index of the input token
    /// @param tokenIndexOut Index of the output token
    /// @param amountIn Amount of input token
    /// @param amountOut Amount of output token
    /// @param alphaQ96 The projection α after the swap
    event Swap(
        address indexed sender,
        address indexed recipient,
        uint256 tokenIndexIn,
        uint256 tokenIndexOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 alphaQ96
    );

    /// @notice Emitted when a flash loan occurs
    /// @param sender The address initiating the flash loan
    /// @param recipient The address receiving the tokens
    /// @param amounts The amounts of each token loaned
    /// @param fees The fees paid for each token
    event Flash(
        address indexed sender,
        address indexed recipient,
        uint256[] amounts,
        uint256[] fees
    );

    /// @notice Emitted when a tick transitions between interior and boundary
    /// @param tick The tick that changed state
    /// @param isInterior True if now interior, false if now boundary
    event TickTransition(
        int24 indexed tick,
        bool isInterior
    );

    /// @notice Emitted when tick consolidated parameters are updated
    /// @param radiusInteriorQ96 New sum of interior radii
    /// @param radiusBoundaryQ96 New sum of boundary orthogonal radii
    /// @param kBoundaryQ96 New sum of boundary k values
    event ConsolidatedParamsUpdated(
        uint256 radiusInteriorQ96,
        uint256 radiusBoundaryQ96,
        uint256 kBoundaryQ96
    );

    /// @notice Emitted when the observation cardinality is increased
    /// @param observationCardinalityNextOld The previous capacity
    /// @param observationCardinalityNextNew The new capacity
    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld,
        uint16 observationCardinalityNextNew
    );

    /// @notice Emitted when the protocol fee is changed
    /// @param feeProtocolOld The previous protocol fee
    /// @param feeProtocolNew The new protocol fee
    event SetFeeProtocol(
        uint8 feeProtocolOld,
        uint8 feeProtocolNew
    );

    /// @notice Emitted when accumulated protocol fees are collected
    /// @param sender The address collecting the fees
    /// @param recipient The address receiving the fees
    /// @param amounts The amounts of each token collected
    event CollectProtocol(
        address indexed sender,
        address indexed recipient,
        uint128[] amounts
    );
}