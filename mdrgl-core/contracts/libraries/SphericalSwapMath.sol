// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './SphericalMath.sol';

/// @title Swap verification for sphere AMM with ZK proofs
/// @notice Verifies swap outputs computed off-chain via ZK proofs
/// @dev All computation happens in zkVM, this only verifies constraints
library SphericalSwapMath {
    /// @notice Parameters for swap verification
    struct SwapParams {
        uint256 tokenIn;              // Index of input token
        uint256 tokenOut;             // Index of output token
        uint256 amountIn;             // Amount of input token
        uint256[] currentReserves;    // Current reserves for all tokens
        uint256 sumReservesQ96;       // Sum of all reserves in Q96
        uint256 sumSquaresQ96;        // Sum of squared reserves in Q96
        SphericalMath.PoolConstants poolConstants; // Pool configuration
        uint24 feePips;               // Fee in hundredths of a bip (1e-6)
        // Active tick parameters
        uint256 radiusInteriorQ96;    // Interior tick radius
        uint256 radiusBoundaryQ96;    // Boundary tick radius
        uint256 kBoundaryQ96;         // Boundary constant
    }
    
    /// @notice Verifies a swap output computed off-chain
    /// @param params Swap parameters including reserves, fees, and tick config
    /// @param amountOut The proposed output amount from ZK proof
    /// @return feeAmount The fee amount taken from input
    function verifySwapAmount(
        SwapParams memory params,
        uint256 amountOut
    ) 
        internal 
        pure 
        returns (uint256 feeAmount) 
    {
        require(params.tokenIn < params.currentReserves.length, "Invalid tokenIn");
        require(params.tokenOut < params.currentReserves.length, "Invalid tokenOut");
        require(params.tokenIn != params.tokenOut, "Same token");
        require(params.amountIn > 0, "Zero input");
        require(amountOut > 0, "Zero output");
        require(amountOut <= params.currentReserves[params.tokenOut], "Insufficient reserves");
        
        // Calculate fee amount
        uint256 amountInLessFee = params.amountIn * (1e6 - params.feePips) / 1e6;
        feeAmount = params.amountIn - amountInLessFee;
        
        // Verify sphere constraint is maintained after swap
        uint256 newReserveIn = params.currentReserves[params.tokenIn] + amountInLessFee;
        uint256 newReserveOut = params.currentReserves[params.tokenOut] - amountOut;
        
        // Update sums
        (uint256 newSumReservesQ96, uint256 newSumSquaresQ96) = SphericalMath.updateSumsAfterTrade(
            params.sumReservesQ96,
            params.sumSquaresQ96,
            params.currentReserves[params.tokenIn],
            newReserveIn,
            params.currentReserves[params.tokenOut],
            newReserveOut
        );
        
        // Verify sphere constraint
        bool valid = SphericalMath.validateConstraintFromSums(
            newSumReservesQ96,
            newSumSquaresQ96,
            params.poolConstants,
            params.radiusInteriorQ96,
            params.radiusBoundaryQ96,
            params.kBoundaryQ96
        );
        
        require(valid, "Invalid swap: sphere constraint violated");
    }
}