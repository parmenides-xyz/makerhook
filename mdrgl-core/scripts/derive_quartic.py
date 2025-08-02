#!/usr/bin/env python3
"""
Derivation of quartic coefficients for toroidal invariant.
"""

from sympy import symbols, sqrt, expand, simplify, Poly

# Define symbols
Δ, d, n = symbols('Δ d n')
S0, S2, xi, xj = symbols('S0 S2 xi xj')
r_int, r_b, k_b = symbols('r_int r_b k_b')
sqrt_n = sqrt(n)

# Orthogonal component squared before trade
W0_sq = S2 - S0**2/n

# Change coefficients for W'² = W0² + K0 + K1*Δ + K2*Δ²
K0 = 2*d*(xi - S0/n) + d**2*(n-1)/n
K1 = 2*(S0/n - xj) + 2*d/n
K2 = (n-1)/n

# New orthogonal component squared after trade
W_sq = W0_sq + K0 + K1*Δ + K2*Δ**2

# Projection component
P = (S0 + d - Δ)/sqrt_n - k_b - r_int*sqrt_n

# Boundary discriminant
B = sqrt(r_b**2 - (k_b - r_b*sqrt_n)**2)

# Algebraic elimination: (W - B² - r_int² + P²)² = 4B²(r_int² - P²)
LHS = W_sq - B**2 - r_int**2 + P**2
LHS_squared = expand(LHS**2)
RHS = expand(4*B**2*(r_int**2 - P**2))

# The quartic equation
quartic = expand(LHS_squared - RHS)

# Extract coefficients
poly = Poly(quartic, Δ)
coeffs = poly.all_coeffs()

# Since poly returns coefficients in descending order
if len(coeffs) >= 5:
    a, b, c, d_coef, e = coeffs[:5]
else:
    coeffs = [0] * (5 - len(coeffs)) + coeffs
    a, b, c, d_coef, e = coeffs

# Display results
print("Quartic coefficients:")
print(f"\na (Δ⁴): {simplify(a)}")
print(f"\nb (Δ³): {simplify(b)}")
print(f"\nc (Δ²): {simplify(c)}")
print(f"\nd (Δ¹): {simplify(d_coef)}")
print(f"\ne (const): {simplify(e)}")