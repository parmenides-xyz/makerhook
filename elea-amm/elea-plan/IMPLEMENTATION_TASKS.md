# Orbitals AMM - Implementation Tasks

## File Structure

### Required Files
```
contracts/
├── OrbitalsFactory.sol
├── OrbitalsPool.sol
├── interfaces/
│   ├── IOrbitalsFactory.sol
│   └── IOrbitalsPool.sol
└── libraries/
    ├── SphericalMath.sol
    ├── ToroidalInvariant.sol
    ├── TickManager.sol
    └── TradeSegmentation.sol

test/
├── unit/
│   ├── SphericalMath.test.sol
│   └── ToroidalInvariant.test.sol
├── integration/
│   └── OrbitalsPool.test.sol
└── invariant/
    └── PoolInvariant.test.sol

scripts/
├── deploy.ts
└── verify.ts
```

## Task 1: Core Mathematical Libraries

### 1.1 SphericalMath.sol
1. **Create** library with fixed-point arithmetic (Q128.128)
2. **Implement** sphere constraint validation:
   ```solidity
   function validateSphereConstraint(uint256[] memory reserves, uint256 radius) 
       pure returns (bool)
   ```
3. **Implement** price calculation:
   ```solidity
   function calculatePrice(uint256 reserveI, uint256 reserveJ, uint256 radius) 
       pure returns (uint256)
   ```
4. **Implement** equal price point calculation:
   ```solidity
   function calculateEqualPricePoint(uint256 radius, uint256 numAssets) 
       pure returns (uint256)
   ```

### 1.2 Acceptance Tests
- [ ] Sphere constraint holds for 3-asset pool within 1 wei precision
- [ ] Price ratios maintain consistency across all asset pairs
- [ ] Equal price point calculation matches formula for n=3,5,10

## Task 2: Tick Management System

### 2.1 TickManager.sol
1. **Define** tick structure:
   ```solidity
   struct Tick {
       uint256 radius;
       uint256 planeConstant;
       bool isInterior;
       uint128 liquidity;
   }
   ```
2. **Implement** tick boundary checking:
   ```solidity
   function isTickInterior(uint256 normalizedProjection, uint256 normalizedK) 
       pure returns (bool)
   ```
3. **Create** tick consolidation logic for interior and boundary cases

### 2.2 Acceptance Tests
- [ ] Tick transitions correctly when projection crosses boundary
- [ ] Consolidation maintains price consistency
- [ ] Gas cost remains constant for up to 100 ticks

## Task 3: Toroidal Invariant

### 3.1 ToroidalInvariant.sol
1. **Implement** sum tracking state variables:
   ```solidity
   uint256 public sumReserves;
   uint256 public sumSquaredReserves;
   ```
2. **Create** invariant validation function:
   ```solidity
   function validateToroidalInvariant(
       uint256 sumReserves,
       uint256 sumSquares,
       uint256 radiusInterior,
       uint256 radiusBoundary,
       uint256 kBoundaryTotal
   ) pure returns (bool)
   ```
3. **Optimize** computation using pre-calculated constants

### 3.2 Acceptance Tests
- [ ] Invariant holds through 1000 random trades
- [ ] Sum updates correctly for single reserve changes
- [ ] Computation uses less than 100k gas

## Task 4: Trade Execution

### 4.1 TradeSegmentation.sol
1. **Implement** quartic equation solver:
   ```solidity
   function solveQuartic(
       int256 a, int256 b, int256 c, int256 d, int256 e
   ) pure returns (uint256)
   ```
2. **Create** tick crossing detection:
   ```solidity
   function detectCrossing(
       uint256 startProjection,
       uint256 endProjection,
       uint256[] memory tickBoundaries
   ) pure returns (uint256 crossingIndex)
   ```
3. **Build** segmented trade execution with crossing points

### 4.2 Acceptance Tests
- [ ] Quartic solver converges within 10 Newton iterations
- [ ] Tick crossings detected accurately for all boundary cases
- [ ] Segmented trades maintain invariant at each step

## Task 5: Pool Implementation

### 5.1 OrbitalsPool.sol
1. **Inherit** from ERC20 for LP tokens
2. **Implement** swap function with segmentation:
   ```solidity
   function swap(
       uint256 tokenIn,
       uint256 tokenOut,
       uint256 amountIn,
       uint256 minAmountOut
   ) external returns (uint256 amountOut)
   ```
3. **Create** liquidity provision interface:
   ```solidity
   function mint(
       uint256 tickRadius,
       uint256 tickPlaneConstant,
       uint256[] memory amounts
   ) external returns (uint256 liquidity)
   ```

### 5.2 Acceptance Tests
- [ ] Swap reverts if output below minAmountOut
- [ ] Liquidity provision maintains sphere constraint
- [ ] Fees accumulate correctly to LPs

## Task 6: Factory Contract

### 6.1 OrbitalsFactory.sol
1. **Create** deterministic pool deployment:
   ```solidity
   function createPool(
       address[] memory tokens,
       uint256 radius
   ) external returns (address pool)
   ```
2. **Implement** pool registry mapping
3. **Add** owner functions for fee configuration

### 6.2 Acceptance Tests
- [ ] Pools deploy to predictable addresses
- [ ] Duplicate pool creation reverts
- [ ] Only owner can modify fee parameters

## Task 7: Integration Testing

### 7.1 Multi-Asset Scenarios
1. **Test** 3-asset pool (USDC, USDT, AID) with various depeg scenarios
2. **Verify** capital efficiency matches theoretical predictions
3. **Benchmark** gas costs against Curve StableSwap

### 7.2 Stress Testing
1. **Execute** 10,000 random trades
2. **Verify** invariant holds throughout
3. **Test** extreme depeg scenarios (one asset → 0)

## Task 8: Deployment

### 8.1 Deployment Script
1. **Create** deployment script for Sei testnet
2. **Configure** initial pools with appropriate radii
3. **Set** conservative tick boundaries for launch

### 8.2 Verification
1. **Verify** all contracts on Seiscan
2. **Document** deployed addresses
3. **Create** interaction examples

## Critical Path Dependencies

```
SphericalMath.sol
    ↓
TickManager.sol → ToroidalInvariant.sol
                        ↓
                 TradeSegmentation.sol
                        ↓
                  OrbitalsPool.sol
                        ↓
                 OrbitalsFactory.sol
```

## Gas Optimization Targets

- Single swap: < 150k gas
- Swap with 1 crossing: < 200k gas  
- Mint liquidity: < 250k gas
- Burn liquidity: < 200k gas