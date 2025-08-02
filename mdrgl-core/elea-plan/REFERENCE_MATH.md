# Orbitals AMM - Mathematical Reference

## Constants and Notation

### Primary Constants
- `RADIUS_SPHERE`: Sphere radius parameter (r)
- `NUM_ASSETS`: Number of assets in pool (n)
- `TICK_PLANE_CONST`: Tick boundary plane constant (k)

### Vector Notation
- `vec_reserves`: Current reserve vector (x̄)
- `vec_center`: Sphere center at (r, r, ..., r)
- `vec_equal_price`: Unit vector (1/√n)(1, 1, ..., 1)

## Core Formulas

### 1. Sphere AMM Constraint
```
||vec_center - vec_reserves||² = RADIUS_SPHERE²
```

Expanded form:
```
Σᵢ₌₁ⁿ(RADIUS_SPHERE - reserve_i)² = RADIUS_SPHERE²
```

### 2. Token Price Ratio
```
price_ratio_ij = (RADIUS_SPHERE - reserve_j) / (RADIUS_SPHERE - reserve_i)
```

### 3. Equal Price Point
```
equal_price_value = RADIUS_SPHERE * (1 - 1/√NUM_ASSETS)
```

### 4. Polar Decomposition
For any reserve vector:
```
vec_reserves = alpha * vec_equal_price + vec_orthogonal
```

Where:
```
alpha = vec_reserves · vec_equal_price = (1/√NUM_ASSETS) * Σreserve_i
||vec_orthogonal||² = RADIUS_SPHERE² - (alpha - RADIUS_SPHERE*√NUM_ASSETS)²
```

### 5. Tick Boundary Geometry
Tick boundary plane:
```
vec_reserves · vec_equal_price = TICK_PLANE_CONST
```

Boundary sphere radius in (n-1) dimensions:
```
boundary_radius = √[RADIUS_SPHERE² - (TICK_PLANE_CONST - RADIUS_SPHERE*√NUM_ASSETS)²]
```

### 6. Virtual Reserves
Minimum reserves at tick boundary:
```
reserve_min = [TICK_PLANE_CONST*√NUM_ASSETS - √(TICK_PLANE_CONST²*NUM_ASSETS - NUM_ASSETS*((NUM_ASSETS-1)*RADIUS_SPHERE - TICK_PLANE_CONST*√NUM_ASSETS)²)] / NUM_ASSETS
```

Maximum reserves:
```
reserve_max = min(RADIUS_SPHERE, [TICK_PLANE_CONST*√NUM_ASSETS + √(TICK_PLANE_CONST²*NUM_ASSETS - NUM_ASSETS*((NUM_ASSETS-1)*RADIUS_SPHERE - TICK_PLANE_CONST*√NUM_ASSETS)²)] / NUM_ASSETS)
```

### 7. Capital Efficiency
```
efficiency_ratio = reserve_base / (reserve_base - reserve_min)
```

Where:
```
reserve_base = RADIUS_SPHERE * (1 - 1/√NUM_ASSETS)
```

### 8. Depeg Price Mapping
For single token depeg to price p:
```
k_depeg = RADIUS_SPHERE*√NUM_ASSETS - RADIUS_SPHERE*(p + NUM_ASSETS - 1) / √(NUM_ASSETS*(p² + NUM_ASSETS - 1))
```

### 9. Tick Bounds
```
k_min = RADIUS_SPHERE * (√NUM_ASSETS - 1)
k_max = RADIUS_SPHERE * (NUM_ASSETS - 1) / √NUM_ASSETS
```

## Consolidation Mathematics

### Case 1: Both Ticks Interior
Consolidated radius:
```
radius_consolidated = radius_a + radius_b
```

### Case 2: Both Ticks Boundary
Consolidated boundary radius:
```
boundary_consolidated = boundary_a + boundary_b
```

### Case 3: Mixed (Toroidal)
Global invariant:
```
radius_interior² = ((vec_total · vec_equal_price - k_boundary_total) - radius_interior*√NUM_ASSETS)² + 
                   (||vec_total - (vec_total · vec_equal_price)*vec_equal_price|| - √[radius_boundary² - (k_boundary - radius_boundary*√NUM_ASSETS)²])²
```

## Computational Optimization

### Tracked Sums
```
sum_reserves = Σreserve_i
sum_squares = Σreserve_i²
```

### Update Rules
When reserve_i changes to reserve_i':
```
sum_reserves' = sum_reserves - reserve_i + reserve_i'
sum_squares' = sum_squares - reserve_i² + (reserve_i')²
```

### Invariant Computation
```
radius_interior² = ((1/√NUM_ASSETS)*sum_reserves - k_boundary_total - radius_interior*√NUM_ASSETS)² + 
                   (√[sum_squares - (1/NUM_ASSETS)*sum_reserves²] - √[radius_boundary² - (k_boundary - radius_boundary*√NUM_ASSETS)²])²
```

## Normalization

### Normalized Projections
```
alpha_norm = (vec_reserves · vec_equal_price) / RADIUS_SPHERE
k_norm = TICK_PLANE_CONST / RADIUS_SPHERE
```

### Interior Condition
Tick is interior if and only if:
```
k_norm > alpha_interior_norm
```

## Trading Equations

### Quartic Solution
Given input amount d for asset i, solve for output Δ of asset j:
```
A*Δ⁴ + B*Δ³ + C*Δ² + D*Δ + E = 0
```

Coefficients depend on current reserves, input amount, and pool parameters.

### Crossover Trade
At tick boundary crossing:
```
alpha_crossover = radius_interior * k_crossover_norm + k_boundary_total
```

Output amount:
```
output_crossover = √NUM_ASSETS * (alpha_total - alpha_crossover) + input_crossover
```