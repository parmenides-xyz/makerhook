# Orbitals AMM - Implementation Tasks V2 (Production-Grade)

## Critical Design Decisions

### Fixed-Point Precision
- **Primary**: Q64.96 for most calculations (gas-efficient, sufficient for 18 decimals)
- **High-precision**: Q128.128 only for tick boundary calculations where n > 5
- **Tolerance**: Configurable epsilon (1e-15) for constraint validation

### Data Structure Choices
- **Tick Storage**: Bitmap for active ticks + mapping for tick data (Uniswap V3 pattern)
- **LP Positions**: ERC-721 with on-chain parameters (not metadata)
- **Reserve Tracking**: Packed struct with sum caching

## File Structure (Revised)

```
contracts/
├── core/
│   ├── OrbitalsFactory.sol
│   ├── OrbitalsPool.sol
│   └── OrbitalsPoolDeployer.sol
├── interfaces/
│   ├── IOrbitalsFactory.sol
│   ├── IOrbitalsPool.sol
│   ├── IOrbitalsPoolEvents.sol
│   └── IOrbitalsPoolErrors.sol
├── libraries/
│   ├── uniswap/                    # Copy directly from Uniswap V3
│   │   ├── BitMath.sol
│   │   ├── FixedPoint96.sol       # Just Q96 constant
│   │   ├── FixedPoint128.sol      # Q128 constant
│   │   ├── FullMath.sol           # mulDiv operations
│   │   ├── LowGasSafeMath.sol     # Gas-optimized arithmetic
│   │   ├── SafeCast.sol           # Type conversions
│   │   ├── UnsafeMath.sol         # Unchecked operations
│   │   └── LiquidityMath.sol      # Safe liquidity arithmetic
│   ├── SphericalMath.sol           # Sphere constraint math (adapts SqrtPriceMath)
│   ├── SphericalSwapMath.sol       # Swap calculations + quartic solver (adapts SwapMath)
│   ├── SphericalTickMath.sol       # Tick conversions + virtual reserves (adapts TickMath)
│   ├── SphericalOracle.sol         # TWAP functionality (adapts Oracle)
│   ├── Position.sol                # LP position tracking (minimal changes from V3)
│   ├── Tick.sol                    # Tick data structure (sphere-specific)
│   └── TickBitmap.sol              # Tick navigation (minimal changes from V3)
└── periphery/
    ├── OrbitalsRouter.sol
    └── OrbitalsQuoter.sol
```

## Phase 1: Mathematical Foundation (Week 1)

### 1.1 Copy Uniswap V3 Libraries
Copy these libraries directly from Uniswap V3 without modification:
- `BitMath.sol` - Bit manipulation utilities
- `FixedPoint96.sol` - Q96 constant definition
- `FixedPoint128.sol` - Q128 constant definition  
- `FullMath.sol` - Overflow-safe mulDiv operations
- `LowGasSafeMath.sol` - Gas-optimized safe arithmetic
- `SafeCast.sol` - Safe type conversions
- `UnsafeMath.sol` - Unchecked math operations
- `LiquidityMath.sol` - Safe liquidity delta calculations

### 1.2 SphericalMath.sol
```solidity
import "./uniswap/FullMath.sol";
import "./uniswap/FixedPoint96.sol";
import "./uniswap/LowGasSafeMath.sol";

library SphericalMath {
    using LowGasSafeMath for uint256;
    
    error ConstraintViolation(uint256 deviation);
    
    struct PoolConstants {
        uint256 radiusQ96;
        uint256 numAssets;
        uint256 sqrtNumAssetsQ96;  // Pre-computed √n
        uint256 epsilonQ96;         // Tolerance for validation
    }
    
    // Core sphere constraint validation (includes toroidal consolidation)
    function validateConstraintFromSums(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        PoolConstants memory constants
    ) internal pure returns (bool valid, uint256 deviationQ96);
    
    // Price calculations
    function calculatePriceRatio(
        uint256 reserveI,
        uint256 reserveJ,
        uint256 radiusQ96
    ) internal pure returns (uint256 ratioQ96);
    
    // Helper functions
    function sqrt(uint256 x) internal pure returns (uint256);
    function toQ96(uint256 value) internal pure returns (uint256);
    
    // Sum tracking for O(1) updates
    function updateSumsAfterTrade(
        uint256 sumReservesQ96,
        uint256 sumSquaresQ96,
        uint256 oldReserveI,
        uint256 newReserveI,
        uint256 oldReserveJ,
        uint256 newReserveJ
    ) internal pure returns (uint256 newSumReserves, uint256 newSumSquares);
}
```

### 1.3 Acceptance Criteria
- [ ] All Uniswap libraries copied and compile correctly
- [ ] SphericalMath uses FullMath.mulDiv instead of custom implementation
- [ ] Sphere constraint validation with configurable tolerance
- [ ] Gas cost < 50k for 10-asset validation

## Phase 2: Tick Architecture (Week 2)

### 2.1 TickBitmap.sol
```solidity
library TickBitmap {
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal;
    
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized);
}
```

### 2.2 SphericalTickMath.sol
```solidity
library SphericalTickMath {
    // Convert between tick index and plane constant k
    function getPlaneConstantAtTick(int24 tick) internal pure returns (uint256 kQ96);
    function getTickAtPlaneConstant(uint256 kQ96) internal pure returns (int24 tick);
    
    // Virtual reserves calculations
    function getVirtualReserves(
        uint256 kQ96,
        uint256 radiusQ96,
        uint256 numAssets
    ) internal pure returns (uint256 minReserve, uint256 maxReserve);
    
    // Normalization for comparing ticks
    function getNormalizedProjection(
        uint256 projectionQ96,
        uint256 radiusQ96
    ) internal pure returns (uint256 normalizedQ96);
}
```

### 2.3 Tick.sol
```solidity
library Tick {
    struct Info {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // Sphere-specific additions:
        uint256 radiusQ96;          // Tick's contribution to pool radius
        uint256 planeConstantQ96;   // k value for this tick
    }
    
    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped);
}
```

### 2.3 Acceptance Criteria
- [ ] Bitmap operations O(1) for tick navigation
- [ ] Tick updates handle liquidity overflow gracefully
- [ ] State packing saves 50%+ storage vs naive approach

## Phase 3: Swap and Oracle Libraries (Week 3)

### 3.1 SphericalSwapMath.sol
```solidity
import "./uniswap/FullMath.sol";
import "./SphericalMath.sol";

library SphericalSwapMath {
    error ConvergenceFailure(uint256 iterations);
    
    struct SwapParams {
        uint256 tokenIn;
        uint256 tokenOut;
        uint256 amountIn;
        uint256 currentReserveIn;
        uint256 currentReserveOut;
        uint256 radiusQ96;
        uint256 feeRate;
    }
    
    // Main swap calculation (includes quartic solving)
    function computeSwapStep(
        SwapParams memory params
    ) internal pure returns (
        uint256 amountOut,
        uint256 newReserveIn,
        uint256 newReserveOut,
        uint256 feeAmount
    );
    
    // Quartic solver for exact output amount
    function solveQuarticForOutput(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 radiusQ96
    ) internal pure returns (uint256 amountOut);
    
    // Tick crossing calculations
    function getOutputToReachTick(
        uint256 targetProjectionQ96,
        uint256 currentProjectionQ96,
        uint256 numAssets
    ) internal pure returns (uint256 outputAmount);
}
```

### 3.2 SphericalOracle.sol
```solidity
library SphericalOracle {
    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 projectionCumulative;  // Cumulative α values for TWAP
        bool initialized;
    }
    
    function initialize(
        Observation[65535] storage self,
        uint32 time
    ) internal returns (uint16 cardinality, uint16 cardinalityNext);
    
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 projection,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated);
    
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint128 projection,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory projectionCumulatives);
}
```

### 3.3 Acceptance Criteria
- [ ] Quartic solver converges within 10 iterations for typical swaps
- [ ] Oracle tracks projection values for multi-asset TWAP
- [ ] Gas < 150k for simple swap without tick crossing

## Phase 4: Position Management (Week 4)

### 4.1 Position.sol
```solidity
library Position {
    struct Info {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        // Note: For n assets, we'd need arrays but hackathon focuses on 3-5 assets
    }
    
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Position.Info storage position);
    
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal;
}
```

### 4.2 Acceptance Criteria
- [ ] Position tracking works for multi-asset pools
- [ ] Fee accumulation accurate across all assets
- [ ] Gas-efficient storage packing

## Phase 5: Core Pool Contract (Week 5)

### 5.1 OrbitalsPool.sol
```solidity
import "./libraries/uniswap/FullMath.sol";
import "./libraries/uniswap/FixedPoint96.sol";
import "./libraries/uniswap/LiquidityMath.sol";
import "./libraries/SphericalMath.sol";
import "./libraries/SphericalSwapMath.sol";
import "./libraries/SphericalTickMath.sol";
import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/Position.sol";

contract OrbitalsPool is IOrbitalsPool {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using TickBitmap for mapping(int16 => uint256);
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    
    // Events
    event Swap(
        address indexed sender,
        address indexed recipient,
        uint256 indexed tokenIn,
        uint256 tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeAmount
    );
    
    event Mint(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    
    // Custom errors
    error InsufficientLiquidity();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InvalidTickRange();
    error Locked();
    
    // State variables (packed)
    struct Slot0 {
        uint128 sumReservesQ96;
        uint128 sumSquaresUpperQ96; // Split for packing
    }
    
    struct PoolState {
        Slot0 slot0;
        uint256 sumSquaresLowerQ96;
        uint256 radiusInteriorQ96;
        uint256 radiusBoundaryQ96;
        uint256 kBoundaryTotalQ96;
        uint128 liquidity;
        uint32 lastTimestamp;
        bool unlocked;
    }
    
    PoolState public poolState;
    mapping(int24 => TickMath.Tick) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;
    
    modifier lock() {
        require(poolState.unlocked);
        poolState.unlocked = false;
        _;
        poolState.unlocked = true;
    }
    
    function swap(
        address recipient,
        uint256 tokenIn,
        uint256 tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata data
    ) external override lock returns (uint256 amountOut) {
        // Implementation
    }
}
```

### 5.2 Acceptance Criteria
- [ ] All state transitions emit appropriate events
- [ ] Custom errors provide clear revert reasons
- [ ] Reentrancy protection via lock modifier
- [ ] Oracle price accumulation for TWAP

## Phase 6: Factory & Deployment (Week 6)

### 6.1 OrbitalsFactory.sol
```solidity
contract OrbitalsFactory is IOrbitalsFactory, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    error PoolAlreadyExists();
    error InvalidTokenOrder();
    error InvalidRadius();
    
    mapping(bytes32 => address) public getPool;
    EnumerableSet.AddressSet private allPools;
    
    uint256 public protocolFee; // In basis points
    address public feeRecipient;
    
    event PoolCreated(
        address indexed pool,
        address[] tokens,
        uint256 radius,
        uint256 numAssets
    );
    
    function createPool(
        address[] calldata tokens,
        uint256 radiusQ96
    ) external returns (address pool) {
        // Validate token ordering
        // Deploy via CREATE2
        // Initialize pool state
        // Emit event
    }
}
```

### 6.2 Acceptance Criteria
- [ ] CREATE2 deployment with deterministic addresses
- [ ] Access control for fee updates
- [ ] Pool enumeration for off-chain indexing

## Phase 7: Comprehensive Testing (Week 7)

### 7.1 Test Matrix
```
Unit Tests:
├── Mathematical primitives (100% coverage)
├── Tick state transitions
├── Invariant preservation
└── Edge cases (0 reserves, max reserves)

Integration Tests:
├── Multi-hop swaps
├── Cross-tick liquidity aggregation
├── Fee accumulation & distribution
└── Flash loan integration

Invariant Tests:
├── No value extraction possible
├── Sum preservation across all operations
└── Tick consistency after 10k operations
└── Depeg resistance (1 asset → 0.01)

Gas Benchmarks:
├── Simple swap: Target 120k
├── Single crossing: Target 250k
├── Complex route (5 crossings): Target 800k
└── Comparison vs Curve StableSwap
```

### 7.2 Security Considerations
- [ ] Formal verification of core invariant
- [ ] Overflow protection in all arithmetic
- [ ] Front-running resistance via commit-reveal
- [ ] Emergency pause mechanism

## Phase 8: Production Deployment (Week 8)

### 8.1 Deployment Checklist
```bash
1. [ ] Deploy libraries to Sei testnet
2. [ ] Deploy factory with conservative parameters:
      - Initial radius: 1000e18 (high for safety)
      - Protocol fee: 0 (enable after testing)
      - Min tick spacing: 100 (reduce later)
3. [ ] Create first pool (USDC/USDT/AID)
4. [ ] Seed initial liquidity across 5-10 ticks
5. [ ] Run integration test suite on testnet
6. [ ] Deploy monitoring dashboard
7. [ ] Submit for audit (Sherlock/Code4rena)
```

### 8.2 Mainnet Migration Path
- 2-week testnet soak period
- Gradual liquidity migration incentives
- Parameter relaxation schedule
- Cross-chain expansion via IBC

## Risk Mitigation Summary

1. **Numerical Stability**: Fallback solvers, iteration caps, tolerance bands
2. **Gas Optimization**: Bitmap navigation, state packing, sum caching
3. **Access Control**: Ownable factory, emergency pause, fee caps
4. **Audit Readiness**: Custom errors, comprehensive events, clean separation

## Recommendation for Hackathon Scope

Given timeline constraints, consider an "n=3 MVP" approach:
- Fix n=3 (USDC/USDT/AID) to simplify math
- Single tick initially (no bitmap needed)
- Pre-computed quartic roots with on-chain verification
- Basic factory without CREATE2
- Focus on demonstrating capital efficiency gains

This maintains the core innovation while deferring complex optimizations until post-hackathon.