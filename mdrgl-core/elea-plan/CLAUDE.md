# Orbitals AMM - Development Reference

This document serves as the primary reference for the Orbitals AMM implementation on Sei. For modular documentation:

- **Executive Overview**: See [OVERVIEW.md](./OVERVIEW.md)
- **Mathematical Reference**: See [REFERENCE_MATH.md](./REFERENCE_MATH.md)  
- **Implementation Tasks**: See [IMPLEMENTATION_TASKS.md](./IMPLEMENTATION_TASKS.md)

## Quick Links

### Core Concepts
- [Sphere AMM Formula](#sphere-amm-formula)
- [Tick System](#tick-system)
- [Toroidal Consolidation](#toroidal-consolidation)
- [Capital Efficiency](#capital-efficiency)

### Implementation
- [Architecture](#architecture)
- [Key Algorithms](#key-algorithms)
- [Testing Strategy](#testing-strategy)

## Context

This implementation extends Uniswap V3's concentrated liquidity concept to n-dimensional pools, starting with a 3-asset stablecoin pool (USDC, USDT, AID).

## Key Design Decisions

### 1. Mathematical Precision
- Use Q128.128 fixed-point arithmetic
- Maintain 1 wei precision for all calculations
- Implement Newton-Raphson for quartic solving

### 2. Gas Optimization
- Track only Σxi and Σxi² for O(1) complexity
- Pre-calculate normalization constants
- Minimize storage updates during swaps

### 3. Tick Architecture
- Dynamic interior/boundary classification
- Nested spherical caps (not disjoint like V3)
- Consolidation into single computational invariant

## Lessons Learned

### From Mathematical Analysis
1. **No-arbitrage constraint**: Reserves naturally bounded by radius r
2. **Virtual reserves**: Not "fake" liquidity but mathematical minima
3. **Tick transitions**: Dynamic based on market state, not static

### From Paradigm Paper
1. **1/8 sphere visualization**: Due to xi ≤ r constraint in positive octant
2. **Toroidal structure**: Emerges from consolidating interior/boundary ticks
3. **Normalization critical**: For comparing ticks of different sizes

## Development Workflow

### Phase 1: Core Math (Weeks 1-2)
- Implement SphericalMath library
- Validate against paper formulas
- Optimize for gas efficiency

### Phase 2: Tick System (Weeks 3-4)
- Build TickManager with consolidation
- Implement boundary detection
- Test state transitions

### Phase 3: Trading Logic (Weeks 5-6)
- Develop TradeSegmentation
- Handle tick crossings
- Optimize quartic solver

### Phase 4: Integration (Weeks 7-8)
- Complete OrbitalsPool
- Deploy factory contract
- Comprehensive testing

## Sei-Specific Optimizations

1. **Parallel Execution**: Leverage for independent tick updates
2. **Native Order Matching**: Integrate for better price discovery
3. **IBC Integration**: Enable cross-chain stablecoin liquidity
4. **Sub-second Finality**: Rapid rebalancing during volatility

## Security Considerations

1. **Invariant Checks**: Validate toroidal constraint after every operation
2. **Overflow Protection**: Use SafeMath equivalents in Solidity 0.8+
3. **Reentrancy Guards**: Essential for swap and liquidity functions
4. **Access Control**: Factory owner for fee updates only

## Testing Matrix

### Unit Tests
- [ ] Mathematical primitives
- [ ] Tick state transitions
- [ ] Invariant validation

### Integration Tests
- [ ] Multi-hop swaps
- [ ] Liquidity provision/removal
- [ ] Fee accumulation

### Stress Tests
- [ ] 10k random operations
- [ ] Extreme depeg scenarios
- [ ] Gas profiling

## Deployment Checklist

1. [ ] Audit mathematical implementation
2. [ ] Verify gas costs meet targets
3. [ ] Deploy to Sei testnet
4. [ ] Initialize with conservative parameters
5. [ ] Monitor initial liquidity provision
6. [ ] Gradual parameter relaxation

## References

- [Paradigm Orbitals Paper](https://www.paradigm.xyz/2025/06/orbital)
- [Uniswap V3 Core](https://github.com/Uniswap/v3-core)
- [GAIB Documentation](https://docs.gaib.ai)