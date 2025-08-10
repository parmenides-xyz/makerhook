const { expect } = require('chai')
const { ethers } = require('hardhat')

// Helper for FullMath.mulDiv equivalent in JS
const FullMath = {
  mulDiv: (a, b, denominator) => (a * b) / denominator
}

describe('SphericalTickMath', () => {
  let tickMath
  const Q96 = 2n ** 96n
  
  // Helper to convert number to Q96
  const toQ96 = (x) => BigInt(Math.floor(x * Number(2n ** 96n)))
  
  beforeEach(async () => {
    const SphericalTickMathTest = await ethers.getContractFactory('SphericalTickMathTest')
    tickMath = await SphericalTickMathTest.deploy()
    await tickMath.waitForDeployment()
  })
  
  describe('constants', () => {
    it('has correct MAX_TICK', async () => {
      expect(await tickMath.MAX_TICK()).to.eq(10000)
    })
    
    it('has correct TICK_SPACING', async () => {
      expect(await tickMath.TICK_SPACING()).to.eq(1)
    })
  })
  
  describe('#getKMin', () => {
    it('calculates k_min = r(√n - 1)', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2) // sqrt(4) = 2
      
      const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
      
      // k_min = 100 * (2 - 1) = 100
      const expected = toQ96(100)
      expect(kMinQ96).to.be.closeTo(expected, expected / 1000n) // 0.1% tolerance
    })
    
    it('works with sqrt(3) ≈ 1.732', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3) ≈ 1.732
      
      const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
      
      // k_min = 100 * (1.732 - 1) = 73.2
      const expected = toQ96(732) / 10n
      expect(kMinQ96).to.be.closeTo(expected, expected / 100n)
    })
    
    it('reverts if sqrt(n) <= 1', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(1) // sqrt(1) = 1
      
      await expect(tickMath.getKMin(radiusQ96, sqrtNQ96))
        .to.be.revertedWith('sqrt(n) must be > 1')
    })
  })
  
  describe('#getKMax', () => {
    it('calculates k_max = r(n-1)/√n', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3n
      const sqrtNQ96 = toQ96(1.732) // sqrt(3)
      
      const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
      
      // k_max = 100 * (3-1) / 1.732 ≈ 115.47
      const expected = toQ96(115.47)
      expect(kMaxQ96).to.be.closeTo(expected, expected / 100n)
    })
    
    it('works with 3 assets', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3) ≈ 1.732
      
      const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
      
      // k_max = 100 * (3 - 1) / 1.732 ≈ 115.47
      const expected = toQ96(11547) / 100n
      expect(kMaxQ96).to.be.closeTo(expected, expected / 100n)
    })
    
    it('reverts if n <= 1', async () => {
      const radiusQ96 = toQ96(100)
      const n = 1
      const sqrtNQ96 = toQ96(1)
      
      await expect(tickMath.getKMax(radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('n must be > 1')
    })
    
    it('reverts if sqrtN is 0', async () => {
      const radiusQ96 = toQ96(100)
      const n = 2
      const sqrtNQ96 = 0n
      
      await expect(tickMath.getKMax(radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('sqrtN must be > 0')
    })
  })
  
  describe('#tickToPlaneConstant', () => {
    it('returns k_min for tick 0', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3n
      const sqrtNQ96 = toQ96(1.732)
      
      const kQ96 = await tickMath.tickToPlaneConstant(0, radiusQ96, n, sqrtNQ96)
      const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
      
      expect(kQ96).to.equal(kMinQ96)
    })
    
    it('returns k_max for MAX_TICK', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3n
      const sqrtNQ96 = toQ96(1.732)
      const maxTick = await tickMath.MAX_TICK()
      
      const kQ96 = await tickMath.tickToPlaneConstant(maxTick, radiusQ96, n, sqrtNQ96)
      const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
      
      expect(kQ96).to.be.closeTo(kMaxQ96, kMaxQ96 / 1000n)
    })
    
    it('linearly interpolates between k_min and k_max', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Test midpoint (tick 5000)
      const kQ96 = await tickMath.tickToPlaneConstant(5000, radiusQ96, n, sqrtNQ96)
      const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
      const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
      
      // Should be approximately halfway between k_min and k_max
      const expectedK = kMinQ96 + (kMaxQ96 - kMinQ96) / 2n
      expect(kQ96).to.be.closeTo(expectedK, expectedK / 100n)
    })
    
    it('reverts for negative tick', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      await expect(tickMath.tickToPlaneConstant(-1, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('Tick out of range')
    })
    
    it('reverts for tick > MAX_TICK', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      await expect(tickMath.tickToPlaneConstant(10001, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('Tick out of range')
    })
  })
  
  describe('#planeConstantToTick', () => {
    it('returns 0 for k_min', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
      const tick = await tickMath.planeConstantToTick(kMinQ96, radiusQ96, n, sqrtNQ96)
      
      expect(tick).to.eq(0)
    })
    
    it('returns MAX_TICK for k_max', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      const maxTick = await tickMath.MAX_TICK()
      
      const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
      const tick = await tickMath.planeConstantToTick(kMaxQ96, radiusQ96, n, sqrtNQ96)
      
      expect(tick).to.eq(maxTick)
    })
    
    it('is inverse of tickToPlaneConstant', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Test several tick values
      const testTicks = [100, 1000, 5000, 9000]
      
      for (const originalTick of testTicks) {
        const kQ96 = await tickMath.tickToPlaneConstant(originalTick, radiusQ96, n, sqrtNQ96)
        const recoveredTick = await tickMath.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96)
        
        // Allow small rounding error
        expect(Math.abs(Number(recoveredTick) - originalTick)).to.be.lte(1)
      }
    })
    
    it('reverts for k < k_min', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
      const invalidK = kMinQ96 - 1n
      
      await expect(tickMath.planeConstantToTick(invalidK, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('k out of range')
    })
    
    it('reverts for k > k_max', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
      const invalidK = kMaxQ96 + 1n
      
      await expect(tickMath.planeConstantToTick(invalidK, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('k out of range')
    })
  })
  
  describe('#getOrthogonalRadius', () => {
    it('calculates s = √(r² - (k - r√n)²)', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2) // sqrt(4) = 2
      
      // k = r√n (center point)
      const kQ96 = toQ96(200) // 100 * 2
      
      const sQ96 = await tickMath.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96)
      
      // At center (k = r√n), the difference is 0, so s = r
      expect(sQ96).to.equal(radiusQ96)
    })
    
    it('returns smaller radius for k far from center', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2)
      
      // k far from center
      const kQ96 = toQ96(150) // Away from center at 200
      
      const sQ96 = await tickMath.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96)
      
      // s should be less than r
      expect(sQ96).to.be.lt(radiusQ96)
      expect(sQ96).to.be.gt(0)
    })
    
    it('works with k < r√n', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2)
      // k = 150 < r√n = 200
      const kQ96 = toQ96(150)
      
      const sQ96 = await tickMath.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96)
      
      // Calculate expected: s = √(r² - (k - r√n)²)
      // diff = |150 - 200| = 50
      // s = √(100² - 50²) = √(10000 - 2500) = √7500 ≈ 86.6
      const expectedS = toQ96(86.6)
      expect(sQ96).to.be.closeTo(expectedS, toQ96(1))
    })
    
    it('reverts for invalid k that makes s² negative', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2)
      
      // k = 400 makes |k - r√n| = |400 - 200| = 200 > r = 100
      // This would make s² = r² - 200² = 10000 - 40000 = negative
      const kQ96 = toQ96(400)
      
      // Should revert when s² would be negative
      await expect(tickMath.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96))
        .to.be.revertedWith('Invalid k for radius')
    })
  })
  
  describe('#getVirtualReserves', () => {
    it('calculates virtual reserves at tick boundary', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Get k at midpoint tick
      const kQ96 = await tickMath.tickToPlaneConstant(5000, radiusQ96, n, sqrtNQ96)
      
      const [xMinQ96, xMaxQ96] = await tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
      
      // Basic validations
      expect(xMinQ96).to.be.gt(0)
      expect(xMaxQ96).to.be.gt(xMinQ96)
      expect(xMaxQ96).to.be.lte(radiusQ96)
    })
    
    it('xMax is capped at radius', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Get k at a reasonable tick (not at boundary)
      const kQ96 = await tickMath.tickToPlaneConstant(3000, radiusQ96, n, sqrtNQ96)
      
      const [xMinQ96, xMaxQ96] = await tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
      
      // xMax should be capped at radius
      expect(xMaxQ96).to.be.lte(radiusQ96)
    })
    
    it('xMin approaches 0 at k_min', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Use a very low tick (close to k_min but not exactly at it)
      const kQ96 = await tickMath.tickToPlaneConstant(10, radiusQ96, n, sqrtNQ96)
      
      const [xMinQ96, ] = await tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
      
      // xMin should be smaller than xMax at low ticks
      // At tick 10 (very close to equal price), xMin should be relatively small
      expect(xMinQ96).to.be.lt(toQ96(50)) // Less than half the radius
    })
    
    it('reverts for invalid k parameters', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // k that's too small will cause issues
      const kQ96 = toQ96(50) // Below k_min ≈ 73.2
      
      await expect(tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('Invalid tick parameters')
    })
  })
  
  describe('#isOnTickPlane', () => {
    it('returns true for reserves on the plane', async () => {
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3)
      
      // Create reserves that sum to a specific value
      // For 3 assets: x₁ + x₂ + x₃ = k * √3
      const kQ96 = toQ96(100)
      
      // Equal reserves case: each = k * √3 / 3
      const equalReserve = toQ96(100) // Simplified for test
      const reserves = [equalReserve, equalReserve, equalReserve]
      
      // Calculate what k should be for these reserves
      const sumReserves = equalReserve * 3n
      const expectedK = sumReserves * Q96 / sqrtNQ96
      
      const isValid = await tickMath.isOnTickPlane(reserves, expectedK, sqrtNQ96)
      expect(isValid).to.be.true
    })
    
    it('returns false for reserves not on the plane', async () => {
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3)
      const kQ96 = toQ96(100)
      
      // Reserves that don't satisfy x̄ · v̄ = k
      const reserves = [toQ96(50), toQ96(60), toQ96(70)]
      
      const isValid = await tickMath.isOnTickPlane(reserves, kQ96, sqrtNQ96)
      expect(isValid).to.be.false
    })
    
    it('allows small tolerance for rounding', async () => {
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const reserves = [toQ96(100), toQ96(100), toQ96(100)]
      const sumReserves = toQ96(300)
      const kQ96 = sumReserves * Q96 / sqrtNQ96
      
      // The contract uses a fixed tolerance of Q96/1000 (0.1%)
      // Let's add an error just under this tolerance
      const tolerance = Q96 / 1000n
      const kWithErrorQ96 = kQ96 + tolerance / 2n
      
      const isValid = await tickMath.isOnTickPlane(reserves, kWithErrorQ96, sqrtNQ96)
      expect(isValid).to.be.true
    })
    
    it('reverts for empty reserves', async () => {
      const sqrtNQ96 = toQ96(1732) / 1000n
      const kQ96 = toQ96(100)
      const reserves = []
      
      await expect(tickMath.isOnTickPlane(reserves, kQ96, sqrtNQ96))
        .to.be.revertedWith('Empty reserves')
    })
  })
  
  describe('additional coverage tests', () => {
    describe('multi-asset configurations', () => {
      it('works with n=2 assets', async () => {
        const radiusQ96 = toQ96(100)
        const n = 2
        const sqrtNQ96 = toQ96(1.414) // sqrt(2)
        
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        // k_min = 100 * (1.414 - 1) = 41.4
        expect(kMinQ96).to.be.closeTo(toQ96(41.4), toQ96(1))
        // k_max = 100 * (2-1) / 1.414 ≈ 70.7
        expect(kMaxQ96).to.be.closeTo(toQ96(70.7), toQ96(1))
      })
      
      it('works with n=4 assets', async () => {
        const radiusQ96 = toQ96(100)
        const n = 4
        const sqrtNQ96 = toQ96(2) // sqrt(4)
        
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        // k_min = 100 * (2 - 1) = 100
        expect(kMinQ96).to.equal(toQ96(100))
        // k_max = 100 * (4-1) / 2 = 150
        expect(kMaxQ96).to.equal(toQ96(150))
      })
      
      it('works with n=10 assets', async () => {
        const radiusQ96 = toQ96(100)
        const n = 10
        const sqrtNQ96 = toQ96(3.162) // sqrt(10)
        
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        // k_max = 100 * (10-1) / 3.162 ≈ 284.6
        expect(kMaxQ96).to.be.closeTo(toQ96(284.6), toQ96(3))
      })
    })
    
    describe('extreme radius values', () => {
      it('works with very small radius', async () => {
        const radiusQ96 = toQ96(0.001)
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        // k_min = 0.001 * (1.732 - 1) = 0.000732
        expect(kMinQ96).to.be.closeTo(toQ96(0.000732), toQ96(0.00001))
        // k_max = 0.001 * 2 / 1.732 ≈ 0.001155
        expect(kMaxQ96).to.be.closeTo(toQ96(0.001155), toQ96(0.00001))
      })
      
      it('works with very large radius', async () => {
        const radiusQ96 = toQ96(1000000)
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        // k_min = 1000000 * 0.732 = 732000
        expect(kMinQ96).to.be.closeTo(toQ96(732000), toQ96(1000))
        // k_max = 1000000 * 2 / 1.732 ≈ 1154700
        expect(kMaxQ96).to.be.closeTo(toQ96(1154700), toQ96(1000))
      })
    })
    
    describe('tick range coverage', () => {
      it('tests tick values throughout range', async () => {
        const radiusQ96 = toQ96(100)
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        const testTicks = [0, 100, 500, 1000, 2500, 5000, 7500, 9000, 9900, 10000]
        let previousK = 0n
        
        for (const tick of testTicks) {
          const kQ96 = await tickMath.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96)
          
          // k should increase monotonically
          expect(kQ96).to.be.gt(previousK)
          previousK = kQ96
          
          // Round-trip test
          const recoveredTick = await tickMath.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96)
          expect(Math.abs(Number(recoveredTick) - tick)).to.be.lte(1)
        }
      })
    })
    
    describe('getVirtualReserves edge cases', () => {
      it('calculates virtual reserves near k_min', async () => {
        const radiusQ96 = toQ96(100)
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        // Near k_min = r(√n - 1), one asset approaches 0 while others are equal
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kQ96 = kMinQ96 + toQ96(1) // Slightly above k_min
        
        const [xMinQ96, xMaxQ96] = await tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
        
        // Near k_min, xMin should be small and xMax should be less than radius
        expect(xMinQ96).to.be.gt(0)
        expect(xMaxQ96).to.be.lt(radiusQ96)
        expect(xMaxQ96).to.be.gt(xMinQ96)
      })
      
      it('calculates virtual reserves near k_max', async () => {
        const radiusQ96 = toQ96(100)
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        // Near k_max = r(n-1)/√n, one asset is at 0 while others are at r
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        const kQ96 = kMaxQ96 - toQ96(1) // Slightly below k_max
        
        const [xMinQ96, xMaxQ96] = await tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
        
        // Near k_max, xMin should be very small and xMax should equal radius
        expect(xMinQ96).to.be.lt(toQ96(1))
        expect(xMaxQ96).to.equal(radiusQ96)
      })
      
      it('returns sensible bounds for middle tick values', async () => {
        const radiusQ96 = toQ96(100)
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        const kQ96 = await tickMath.tickToPlaneConstant(5000, radiusQ96, n, sqrtNQ96)
        const [xMinQ96, xMaxQ96] = await tickMath.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
        
        expect(xMinQ96).to.be.gt(0)
        expect(xMaxQ96).to.be.lte(radiusQ96)
        expect(xMaxQ96).to.be.gt(xMinQ96)
        
        expect(xMinQ96).to.be.gt(toQ96(2))
        expect(xMinQ96).to.be.lt(toQ96(10))
        expect(xMaxQ96).to.be.gt(toQ96(50))
        expect(xMaxQ96).to.be.lte(radiusQ96)
      })
    })
    
    describe('Q96 boundary stability', () => {
      it('handles values near Q96 boundaries', async () => {
        // Test with radius exactly at Q96
        const radiusQ96 = Q96
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        // Should calculate without overflow
        expect(kMinQ96).to.be.gt(0)
        expect(kMaxQ96).to.be.gt(kMinQ96)
        
        // Test orthogonal radius at center
        const kCenter = (radiusQ96 * sqrtNQ96) / Q96
        const sQ96 = await tickMath.getOrthogonalRadius(kCenter, radiusQ96, sqrtNQ96)
        expect(sQ96).to.equal(radiusQ96)
      })
      
      it('handles very large Q96 values', async () => {
        // Test with large values that approach uint256 limits
        const radiusQ96 = Q96 * 1000000n
        const n = 3
        const sqrtNQ96 = toQ96(1.732)
        
        const kMinQ96 = await tickMath.getKMin(radiusQ96, sqrtNQ96)
        const kMaxQ96 = await tickMath.getKMax(radiusQ96, n, sqrtNQ96)
        
        expect(kMinQ96).to.be.gt(0)
        expect(kMaxQ96).to.be.gt(kMinQ96)
      })
    })
  })
})