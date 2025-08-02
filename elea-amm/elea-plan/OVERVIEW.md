# Orbitals AMM - Executive Overview

## Introduction

Orbitals is a next-generation automated market maker (AMM) designed for multi-dimensional stablecoin pools. Built on the mathematical foundation of n-dimensional spheres, it extends concentrated liquidity concepts from 2D (Uniswap V3) to arbitrary dimensions, enabling efficient trading between 3, 10, or even thousands of stable assets.

## Core Innovation

Traditional AMMs face a fundamental limitation: concentrated liquidity works brilliantly for pairs but doesn't scale to multiple assets. Orbitals solves this through a novel geometric approach where liquidity is concentrated in spherical caps around the equal-price point ($1 for all stablecoins).

The key insight: by mapping tick boundaries as orbits around the equilibrium point and consolidating them into a toroidal (donut-shaped) invariant, we achieve O(1) computational complexity regardless of pool dimensions.

## Technical Architecture

The protocol consists of three mathematical layers:

1. **Base Sphere AMM**: Reserves satisfy ||r̄ - x̄||² = r², creating an n-dimensional trading surface
2. **Tick System**: Planar boundaries (x̄ · v̄ = k) slice the sphere into nested spherical caps
3. **Toroidal Consolidation**: Interior and boundary ticks combine into a single computational invariant

## Capital Efficiency

Through virtual reserves—the mathematical minimum that maintains sphere constraints—liquidity providers achieve dramatic efficiency gains:
- 15x efficiency at $0.90 depeg protection
- 150x efficiency at $0.99 depeg protection

## Implementation Target

This implementation targets the Sei blockchain, leveraging:
- Sei's parallel execution for tick state updates
- Native order matching integration
- Sub-second finality for responsive rebalancing
- IBC for cross-chain stablecoin aggregation

The initial pool will feature USDC, USDT, and AID (GAIB's GPU-backed stablecoin), demonstrating how Orbitals enables efficient multi-dimensional stable asset trading at scale.