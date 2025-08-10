# SphericalTickMath Implementation

This document describes the SphericalTickMath library implementation for the Spherical AMM.

## Overview

SphericalTickMath provides tick-based liquidity concentration for spherical AMMs, similar to how Uniswap V3 uses ticks for concentrated liquidity.

## Key Functions

- `getKMin`: Calculate minimum plane constant k_min = r(√n - 1)
- `getKMax`: Calculate maximum plane constant k_max = r(n-1)/√n  
- `tickToPlaneConstant`: Convert tick to plane constant k
- `planeConstantToTick`: Convert plane constant k to tick
- `getOrthogonalRadius`: Calculate orthogonal radius s = √(r² - (k - r√n)²)
- `getVirtualReserves`: Calculate virtual reserve bounds at a tick
- `isOnTickPlane`: Check if reserves satisfy tick plane constraint

## Mathematical Foundation

Based on the Orbital paper: https://www.paradigm.xyz/2025/06/orbital

The implementation uses Q96 fixed-point arithmetic for precision.