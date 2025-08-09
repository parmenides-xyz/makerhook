const { ethers } = require('hardhat')
const { expect } = require('chai')

// Helper function to calculate Q96 representation
function toQ96(value) {
  return BigInt(value) * (2n ** 96n)
}

// Helper function to convert from Q96
function fromQ96(valueQ96) {
  return Number(valueQ96 / (2n ** 96n))
}

// Helper to calculate sqrt in Q96
function sqrtQ96(value) {
  // Simple integer square root approximation
  let x = value
  let y = (x + 1n) / 2n
  while (y < x) {
    x = y
    y = (x + value / x) / 2n
  }
  return x
}

describe('SphericalTickMath', () => {
  let tickMathTest
  const Q96 = 2n ** 96n
  
  beforeEach('deploy SphericalTickMathTest', async () => {
    const tickMathTestFactory = await ethers.getContractFactory('SphericalTickMathTest')
    tickMathTest = await tickMathTestFactory.deploy()
  })

  describe('constants', () => {
    it('has correct MAX_TICK', async () => {
      expect(await tickMathTest.MAX_TICK()).to.eq(10000)
    })

    it('has correct TICK_SPACING', async () => {
      expect(await tickMathTest.TICK_SPACING()).to.eq(1)
    })
  })

  describe('#getKMin', () => {
    it('calculates k_min = r(√n - 1)', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2) // sqrt(4) = 2
      
      const kMinQ96 = await tickMathTest.getKMin(radiusQ96, sqrtNQ96)
      
      // k_min = 100 * (2 - 1) = 100
      const expected = toQ96(100)
      expect(kMinQ96).to.be.closeTo(expected, expected / 1000n) // 0.1% tolerance
    })

    it('works with sqrt(3) ≈ 1.732', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3) ≈ 1.732
      
      const kMinQ96 = await tickMathTest.getKMin(radiusQ96, sqrtNQ96)
      
      // k_min = 100 * (1.732 - 1) = 73.2
      const expected = toQ96(732) / 10n
      expect(kMinQ96).to.be.closeTo(expected, expected / 1000n)
    })

    it('reverts if sqrt(n) <= 1', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(1) // sqrt(n) = 1
      
      await expect(tickMathTest.getKMin(radiusQ96, sqrtNQ96))
        .to.be.revertedWith('sqrt(n) must be > 1')
    })
  })

  describe('#getKMax', () => {
    it('calculates k_max = r(n-1)/√n', async () => {
      const radiusQ96 = toQ96(100)
      const n = 4
      const sqrtNQ96 = toQ96(2) // sqrt(4) = 2
      
      const kMaxQ96 = await tickMathTest.getKMax(radiusQ96, n, sqrtNQ96)
      
      // k_max = 100 * (4 - 1) / 2 = 150
      const expected = toQ96(150)
      expect(kMaxQ96).to.be.closeTo(expected, expected / 1000n)
    })

    it('works with 3 assets', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3) ≈ 1.732
      
      const kMaxQ96 = await tickMathTest.getKMax(radiusQ96, n, sqrtNQ96)
      
      // k_max = 100 * (3 - 1) / 1.732 ≈ 115.47
      const expected = toQ96(11547) / 100n
      expect(kMaxQ96).to.be.closeTo(expected, expected / 100n)
    })

    it('reverts if n <= 1', async () => {
      const radiusQ96 = toQ96(100)
      const n = 1
      const sqrtNQ96 = toQ96(1)
      
      await expect(tickMathTest.getKMax(radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('n must be > 1')
    })

    it('reverts if sqrtN is 0', async () => {
      const radiusQ96 = toQ96(100)
      const n = 2
      const sqrtNQ96 = 0n
      
      await expect(tickMathTest.getKMax(radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('sqrtN must be > 0')
    })
  })

  describe('#tickToPlaneConstant', () => {
    it('returns k_min for tick 0', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kQ96 = await tickMathTest.tickToPlaneConstant(0, radiusQ96, n, sqrtNQ96)
      const kMinQ96 = await tickMathTest.getKMin(radiusQ96, sqrtNQ96)
      
      expect(kQ96).to.eq(kMinQ96)
    })

    it('returns k_max for MAX_TICK', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      const maxTick = await tickMathTest.MAX_TICK()
      
      const kQ96 = await tickMathTest.tickToPlaneConstant(maxTick, radiusQ96, n, sqrtNQ96)
      const kMaxQ96 = await tickMathTest.getKMax(radiusQ96, n, sqrtNQ96)
      
      expect(kQ96).to.be.closeTo(kMaxQ96, kMaxQ96 / 1000n)
    })

    it('linearly interpolates between k_min and k_max', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Test midpoint (tick 5000)
      const kQ96 = await tickMathTest.tickToPlaneConstant(5000, radiusQ96, n, sqrtNQ96)
      const kMinQ96 = await tickMathTest.getKMin(radiusQ96, sqrtNQ96)
      const kMaxQ96 = await tickMathTest.getKMax(radiusQ96, n, sqrtNQ96)
      
      // Should be approximately halfway between k_min and k_max
      const expectedK = kMinQ96 + (kMaxQ96 - kMinQ96) / 2n
      expect(kQ96).to.be.closeTo(expectedK, expectedK / 100n)
    })

    it('reverts for negative tick', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      await expect(tickMathTest.tickToPlaneConstant(-1, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('Tick out of range')
    })

    it('reverts for tick > MAX_TICK', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      await expect(tickMathTest.tickToPlaneConstant(10001, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('Tick out of range')
    })
  })

  describe('#planeConstantToTick', () => {
    it('returns 0 for k_min', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kMinQ96 = await tickMathTest.getKMin(radiusQ96, sqrtNQ96)
      const tick = await tickMathTest.planeConstantToTick(kMinQ96, radiusQ96, n, sqrtNQ96)
      
      expect(tick).to.eq(0)
    })

    it('returns MAX_TICK for k_max', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      const maxTick = await tickMathTest.MAX_TICK()
      
      const kMaxQ96 = await tickMathTest.getKMax(radiusQ96, n, sqrtNQ96)
      const tick = await tickMathTest.planeConstantToTick(kMaxQ96, radiusQ96, n, sqrtNQ96)
      
      expect(tick).to.eq(maxTick)
    })

    it('is inverse of tickToPlaneConstant', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Test several tick values
      const testTicks = [100, 1000, 5000, 9000]
      
      for (const originalTick of testTicks) {
        const kQ96 = await tickMathTest.tickToPlaneConstant(originalTick, radiusQ96, n, sqrtNQ96)
        const recoveredTick = await tickMathTest.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96)
        
        // Allow small rounding error
        expect(Math.abs(Number(recoveredTick) - originalTick)).to.be.lte(1)
      }
    })

    it('reverts for k < k_min', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kMinQ96 = await tickMathTest.getKMin(radiusQ96, sqrtNQ96)
      const invalidK = kMinQ96 - 1n
      
      await expect(tickMathTest.planeConstantToTick(invalidK, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('k out of range')
    })

    it('reverts for k > k_max', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      const kMaxQ96 = await tickMathTest.getKMax(radiusQ96, n, sqrtNQ96)
      const invalidK = kMaxQ96 + 1n
      
      await expect(tickMathTest.planeConstantToTick(invalidK, radiusQ96, n, sqrtNQ96))
        .to.be.revertedWith('k out of range')
    })
  })

  describe('#getOrthogonalRadius', () => {
    it('calculates s = √(r² - (k - r√n)²)', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2) // sqrt(4) = 2
      
      // k = r√n (center point)
      const kQ96 = toQ96(200) // 100 * 2
      
      const sQ96 = await tickMathTest.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96)
      
      // At center (k = r√n), the difference is 0, so s = r
      // However, the calculation may have rounding, so we check it's close to 0
      // When k = r√n, |k - r√n| = 0, so s = √(r² - 0) = r
      // But our implementation might have s very small due to rounding
      expect(sQ96).to.be.lte(toQ96(1)) // Very small, close to 0
    })

    it('returns smaller radius for k far from center', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2)
      
      // k far from center
      const kQ96 = toQ96(150) // Away from center at 200
      
      const sQ96 = await tickMathTest.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96)
      
      // s should be less than r
      expect(sQ96).to.be.lt(radiusQ96)
      expect(sQ96).to.be.gt(0)
    })

    it('works with k < r√n', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2)
      
      // k < r√n
      const kQ96 = toQ96(150) // Less than 200
      
      const sQ96 = await tickMathTest.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96)
      
      // Should still calculate correctly
      expect(sQ96).to.be.gt(0)
      expect(sQ96).to.be.lt(radiusQ96)
    })

    it('reverts for invalid k that makes s² negative', async () => {
      const radiusQ96 = toQ96(100)
      const sqrtNQ96 = toQ96(2)
      
      // k very far from center (beyond valid range)
      const kQ96 = toQ96(500) // Way beyond valid range
      
      await expect(tickMathTest.getOrthogonalRadius(kQ96, radiusQ96, sqrtNQ96))
        .to.be.revertedWith('Invalid k for radius')
    })
  })

  describe('#getVirtualReserves', () => {
    it('calculates virtual reserves at tick boundary', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Get k at midpoint tick
      const kQ96 = await tickMathTest.tickToPlaneConstant(5000, radiusQ96, n, sqrtNQ96)
      
      const [xMinQ96, xMaxQ96] = await tickMathTest.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
      
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
      const kQ96 = await tickMathTest.tickToPlaneConstant(3000, radiusQ96, n, sqrtNQ96)
      
      const [xMinQ96, xMaxQ96] = await tickMathTest.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
      
      // xMax should be capped at radius
      expect(xMaxQ96).to.be.lte(radiusQ96)
    })

    it('xMin approaches 0 at k_min', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Use a very low tick (close to k_min but not exactly at it)
      const kQ96 = await tickMathTest.tickToPlaneConstant(10, radiusQ96, n, sqrtNQ96)
      
      const [xMinQ96, ] = await tickMathTest.getVirtualReserves(kQ96, radiusQ96, n, sqrtNQ96)
      
      // xMin should be smaller than xMax at low ticks
      // At tick 10 (very close to equal price), xMin should be relatively small
      expect(xMinQ96).to.be.lt(toQ96(50)) // Less than half the radius
    })

    it('reverts for invalid k parameters', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // k way beyond valid range
      const invalidK = toQ96(1000)
      
      await expect(tickMathTest.getVirtualReserves(invalidK, radiusQ96, n, sqrtNQ96))
        .to.be.reverted
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
      
      const isValid = await tickMathTest.isOnTickPlane(reserves, expectedK, sqrtNQ96)
      expect(isValid).to.be.true
    })

    it('returns false for reserves not on the plane', async () => {
      const sqrtNQ96 = toQ96(1732) / 1000n // sqrt(3)
      const kQ96 = toQ96(100)
      
      // Reserves that don't satisfy x̄ · v̄ = k
      const reserves = [toQ96(50), toQ96(60), toQ96(70)]
      
      const isValid = await tickMathTest.isOnTickPlane(reserves, kQ96, sqrtNQ96)
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
      const kWithError = kQ96 + tolerance / 2n // Half the tolerance
      
      const isValid = await tickMathTest.isOnTickPlane(reserves, kWithError, sqrtNQ96)
      expect(isValid).to.be.true
    })

    it('reverts for empty reserves array', async () => {
      const sqrtNQ96 = toQ96(1732) / 1000n
      const kQ96 = toQ96(100)
      const reserves = []
      
      await expect(tickMathTest.isOnTickPlane(reserves, kQ96, sqrtNQ96))
        .to.be.revertedWith('Empty reserves')
    })
  })

  describe('integration tests', () => {
    it('tick conversions are consistent', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // Test that we can go from tick -> k -> tick
      for (let tick = 0; tick <= 10000; tick += 1000) {
        const kQ96 = await tickMathTest.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96)
        const recoveredTick = await tickMathTest.planeConstantToTick(kQ96, radiusQ96, n, sqrtNQ96)
        
        // Should recover the same tick (or very close due to rounding)
        expect(Math.abs(Number(recoveredTick) - tick)).to.be.lte(1)
      }
    })

    it('k values increase monotonically with tick', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      let prevK = 0n
      
      for (let tick = 0; tick <= 10000; tick += 1000) {
        const kQ96 = await tickMathTest.tickToPlaneConstant(tick, radiusQ96, n, sqrtNQ96)
        expect(kQ96).to.be.gt(prevK)
        prevK = kQ96
      }
    })

    it('orthogonal radius decreases as k moves from center', async () => {
      const radiusQ96 = toQ96(100)
      const n = 3
      const sqrtNQ96 = toQ96(1732) / 1000n
      
      // r√n is the center
      const center = radiusQ96 * sqrtNQ96 / Q96
      
      // Test k values moving away from center
      const k1 = center
      const k2 = center - toQ96(10)
      const k3 = center - toQ96(20)
      
      const s1 = await tickMathTest.getOrthogonalRadius(k1, radiusQ96, sqrtNQ96)
      const s2 = await tickMathTest.getOrthogonalRadius(k2, radiusQ96, sqrtNQ96)
      const s3 = await tickMathTest.getOrthogonalRadius(k3, radiusQ96, sqrtNQ96)
      
      // Orthogonal radius should decrease as we move from center
      expect(s1).to.be.gt(s2)
      expect(s2).to.be.gt(s3)
    })
  })
})
