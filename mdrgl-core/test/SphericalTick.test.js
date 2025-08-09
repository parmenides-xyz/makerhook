const { ethers } = require('hardhat')
const { expect } = require('chai')
const { FeeAmount, TICK_SPACINGS } = require('./shared/utilities')

// Helper to get max liquidity per tick for Spherical AMM
function getSphericalMaxLiquidityPerTick(tickSpacing) {
  const MAX_TICK = 10000 // SphericalTickMath.MAX_TICK
  const numTicks = Math.floor(MAX_TICK / tickSpacing) + 1
  const MaxUint128 = (2n ** 128n) - 1n
  return MaxUint128 / BigInt(numTicks)
}

describe('SphericalTick', () => {
  let tickTest
  let MaxUint128
  const NUM_ASSETS = 3 // Test with 3-asset pool

  beforeEach('deploy SphericalTickTest', async () => {
    const tickTestFactory = await ethers.getContractFactory('SphericalTickTest')
    tickTest = await tickTestFactory.deploy()
    MaxUint128 = (2n ** 128n) - 1n
  })

  describe('#tickSpacingToMaxLiquidityPerTick', () => {
    it('returns the correct value for tick spacing 1', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(1)
      expect(maxLiquidityPerTick).to.eq(getSphericalMaxLiquidityPerTick(1))
    })

    it('returns the correct value for tick spacing 10', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(10)
      expect(maxLiquidityPerTick).to.eq(getSphericalMaxLiquidityPerTick(10))
    })

    it('returns the correct value for tick spacing 60', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(60)
      expect(maxLiquidityPerTick).to.eq(getSphericalMaxLiquidityPerTick(60))
    })

    it('reverts for tick spacing 0', async () => {
      await expect(tickTest.tickSpacingToMaxLiquidityPerTick(0)).to.be.revertedWith('TICK_SPACING')
    })
  })

  describe('#getFeeGrowthInside', () => {
    // Create array of fee growth values for multi-asset testing
    const createFeeGrowthArray = (values) => {
      return values.map(v => BigInt(v))
    }

    it('returns all for two uninitialized ticks if tick is inside', async () => {
      const globalFeeGrowth = createFeeGrowthArray([15, 20, 25])
      const feeGrowthInside = await tickTest.getFeeGrowthInside(-2, 2, 0, globalFeeGrowth, NUM_ASSETS)
      
      expect(feeGrowthInside[0]).to.eq(15)
      expect(feeGrowthInside[1]).to.eq(20)
      expect(feeGrowthInside[2]).to.eq(25)
    })

    it('returns 0 for two uninitialized ticks if tick is above', async () => {
      const globalFeeGrowth = createFeeGrowthArray([15, 20, 25])
      const feeGrowthInside = await tickTest.getFeeGrowthInside(-2, 2, 4, globalFeeGrowth, NUM_ASSETS)
      
      for (let i = 0; i < NUM_ASSETS; i++) {
        expect(feeGrowthInside[i]).to.eq(0)
      }
    })

    it('returns 0 for two uninitialized ticks if tick is below', async () => {
      const globalFeeGrowth = createFeeGrowthArray([15, 20, 25])
      const feeGrowthInside = await tickTest.getFeeGrowthInside(-2, 2, -4, globalFeeGrowth, NUM_ASSETS)
      
      for (let i = 0; i < NUM_ASSETS; i++) {
        expect(feeGrowthInside[i]).to.eq(0)
      }
    })

    it('subtracts upper tick if below', async () => {
      // Set fee growth for upper tick
      await tickTest.setFeeGrowthOutside(2, 0, 2)
      await tickTest.setFeeGrowthOutside(2, 1, 3)
      await tickTest.setFeeGrowthOutside(2, 2, 4)
      
      // Mark tick as initialized
      await tickTest.setTickState(2, true, false)
      
      const globalFeeGrowth = createFeeGrowthArray([15, 20, 25])
      const feeGrowthInside = await tickTest.getFeeGrowthInside(-2, 2, 0, globalFeeGrowth, NUM_ASSETS)
      
      expect(feeGrowthInside[0]).to.eq(13) // 15 - 2
      expect(feeGrowthInside[1]).to.eq(17) // 20 - 3
      expect(feeGrowthInside[2]).to.eq(21) // 25 - 4
    })
  })

  describe('#update', () => {
    it('flips from zero to nonzero', async () => {
      const feeGrowthGlobal = [0, 0, 0]
      expect(await tickTest.update.staticCall(0, 0, 1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)).to.eq(true)
    })

    it('does not flip from nonzero to greater nonzero', async () => {
      const feeGrowthGlobal = [0, 0, 0]
      await tickTest.update(0, 0, 1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)
      expect(await tickTest.update.staticCall(0, 0, 1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)).to.eq(false)
    })

    it('flips from nonzero to zero', async () => {
      const feeGrowthGlobal = [0, 0, 0]
      await tickTest.update(0, 0, 1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)
      expect(await tickTest.update.staticCall(0, 0, -1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)).to.eq(true)
    })

    it('does not flip from nonzero to lesser nonzero', async () => {
      const feeGrowthGlobal = [0, 0, 0]
      await tickTest.update(0, 0, 2, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)
      expect(await tickTest.update.staticCall(0, 0, -1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)).to.eq(false)
    })

    it('reverts if total liquidity gross is greater than max', async () => {
      const feeGrowthGlobal = [0, 0, 0]
      await tickTest.update(0, 0, 2, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)
      await tickTest.update(0, 0, 1, feeGrowthGlobal, 0, 0, 0, true, 3, NUM_ASSETS)
      await expect(tickTest.update(0, 0, 1, feeGrowthGlobal, 0, 0, 0, false, 3, NUM_ASSETS)).to.be.revertedWith('LO')
    })

    it('nets the liquidity based on upper flag', async () => {
      const feeGrowthGlobal = [0, 0, 0]
      await tickTest.update(0, 0, 2, feeGrowthGlobal, 0, 0, 0, false, 10, NUM_ASSETS)
      await tickTest.update(0, 0, 1, feeGrowthGlobal, 0, 0, 0, true, 10, NUM_ASSETS)
      await tickTest.update(0, 0, 3, feeGrowthGlobal, 0, 0, 0, true, 10, NUM_ASSETS)
      await tickTest.update(0, 0, 1, feeGrowthGlobal, 0, 0, 0, false, 10, NUM_ASSETS)
      
      const tickInfo = await tickTest.getTickInfo(0)
      expect(tickInfo.liquidityGross).to.eq(2 + 1 + 3 + 1)
      expect(tickInfo.liquidityNet).to.eq(2 - 1 - 3 + 1)
    })

    it('assumes all growth happens below ticks lte current tick', async () => {
      const feeGrowthGlobal = [1, 2, 3]
      await tickTest.update(1, 1, 1, feeGrowthGlobal, 3, 4, 5, false, MaxUint128, NUM_ASSETS)
      
      const tickInfo = await tickTest.getTickInfo(1)
      
      // Check each token's fee growth
      for (let i = 0; i < NUM_ASSETS; i++) {
        const feeGrowth = await tickTest.getFeeGrowthOutside(1, i)
        expect(feeGrowth).to.eq(feeGrowthGlobal[i])
      }
      
      expect(tickInfo.secondsPerLiquidityOutsideX128).to.eq(3)
      expect(tickInfo.tickCumulativeOutside).to.eq(4)
      expect(tickInfo.secondsOutside).to.eq(5)
      expect(tickInfo.initialized).to.eq(true)
    })

    it('does not set any growth fields if tick is already initialized', async () => {
      const feeGrowthGlobal1 = [1, 2, 3]
      const feeGrowthGlobal2 = [6, 7, 8]
      
      await tickTest.update(1, 1, 1, feeGrowthGlobal1, 3, 4, 5, false, MaxUint128, NUM_ASSETS)
      await tickTest.update(1, 1, 1, feeGrowthGlobal2, 8, 9, 10, false, MaxUint128, NUM_ASSETS)
      
      const tickInfo = await tickTest.getTickInfo(1)
      
      // Fee growth should still be from first update
      for (let i = 0; i < NUM_ASSETS; i++) {
        const feeGrowth = await tickTest.getFeeGrowthOutside(1, i)
        expect(feeGrowth).to.eq(feeGrowthGlobal1[i])
      }
      
      expect(tickInfo.secondsPerLiquidityOutsideX128).to.eq(3)
      expect(tickInfo.tickCumulativeOutside).to.eq(4)
      expect(tickInfo.secondsOutside).to.eq(5)
    })
  })

  describe('#clear', () => {
    it('deletes all the data in the tick', async () => {
      // Initialize a tick with data
      const feeGrowthGlobal = [1, 2, 3]
      await tickTest.update(2, 2, 5, feeGrowthGlobal, 5, 6, 7, false, MaxUint128, NUM_ASSETS)
      
      // Clear the tick
      await tickTest.clear(2, NUM_ASSETS)
      
      const tickInfo = await tickTest.getTickInfo(2)
      
      // Check all fields are reset
      expect(tickInfo.liquidityGross).to.eq(0)
      expect(tickInfo.liquidityNet).to.eq(0)
      expect(tickInfo.secondsPerLiquidityOutsideX128).to.eq(0)
      expect(tickInfo.tickCumulativeOutside).to.eq(0)
      expect(tickInfo.secondsOutside).to.eq(0)
      expect(tickInfo.initialized).to.eq(false)
      expect(tickInfo.isAtBoundary).to.eq(false)
      
      // Check fee growth for each token is reset
      for (let i = 0; i < NUM_ASSETS; i++) {
        const feeGrowth = await tickTest.getFeeGrowthOutside(2, i)
        expect(feeGrowth).to.eq(0)
      }
    })
  })

  describe('#cross', () => {
    it('flips the growth variables', async () => {
      // Initialize tick with some values
      const feeGrowthGlobal1 = [1, 2, 3]
      await tickTest.update(2, 2, 3, feeGrowthGlobal1, 5, 6, 7, false, MaxUint128, NUM_ASSETS)
      
      // Cross the tick
      const feeGrowthGlobal2 = [7, 9, 11]
      await tickTest.cross(2, feeGrowthGlobal2, 8, 15, 10, NUM_ASSETS)
      
      const tickInfo = await tickTest.getTickInfo(2)
      
      // Check fee growth flipped for each token
      expect(await tickTest.getFeeGrowthOutside(2, 0)).to.eq(6) // 7 - 1
      expect(await tickTest.getFeeGrowthOutside(2, 1)).to.eq(7) // 9 - 2
      expect(await tickTest.getFeeGrowthOutside(2, 2)).to.eq(8) // 11 - 3
      
      expect(tickInfo.secondsPerLiquidityOutsideX128).to.eq(3) // 8 - 5
      expect(tickInfo.tickCumulativeOutside).to.eq(9) // 15 - 6
      expect(tickInfo.secondsOutside).to.eq(3) // 10 - 7
    })

    it('two flips are no op', async () => {
      // Initialize tick
      const feeGrowthGlobal1 = [1, 2, 3]
      await tickTest.update(2, 2, 3, feeGrowthGlobal1, 5, 6, 7, false, MaxUint128, NUM_ASSETS)
      
      // Cross twice with same values
      const feeGrowthGlobal2 = [7, 9, 11]
      await tickTest.cross(2, feeGrowthGlobal2, 8, 15, 10, NUM_ASSETS)
      await tickTest.cross(2, feeGrowthGlobal2, 8, 15, 10, NUM_ASSETS)
      
      const tickInfo = await tickTest.getTickInfo(2)
      
      // Should be back to original values
      expect(await tickTest.getFeeGrowthOutside(2, 0)).to.eq(1)
      expect(await tickTest.getFeeGrowthOutside(2, 1)).to.eq(2)
      expect(await tickTest.getFeeGrowthOutside(2, 2)).to.eq(3)
      
      expect(tickInfo.secondsPerLiquidityOutsideX128).to.eq(5)
      expect(tickInfo.tickCumulativeOutside).to.eq(6)
      expect(tickInfo.secondsOutside).to.eq(7)
    })
  })

  describe('#initializeGeometry', () => {
    it('initializes tick geometry parameters', async () => {
      const radiusQ96 = (2n ** 96n) * 100n // radius = 100
      const sqrtNumAssetsQ96 = (2n ** 96n) * 1732n / 1000n // sqrt(3) ≈ 1.732
      
      await tickTest.initializeGeometry(100, radiusQ96, NUM_ASSETS, sqrtNumAssetsQ96)
      
      const tickGeometry = await tickTest.getTickGeometry(100)
      
      // Check that geometry was initialized (non-zero values)
      expect(tickGeometry.radiusQ96).to.be.gt(0)
      expect(tickGeometry.kQ96).to.be.gt(0)
    })
  })

  describe('#updateBoundaryStatus', () => {
    it('updates boundary status to true', async () => {
      await tickTest.updateBoundaryStatus(50, true)
      const tickInfo = await tickTest.getTickInfo(50)
      expect(tickInfo.isAtBoundary).to.eq(true)
    })

    it('updates boundary status to false', async () => {
      await tickTest.updateBoundaryStatus(50, true)
      await tickTest.updateBoundaryStatus(50, false)
      const tickInfo = await tickTest.getTickInfo(50)
      expect(tickInfo.isAtBoundary).to.eq(false)
    })
  })

  describe('#validateLiquidityAtTick', () => {
    it('allows removing liquidity', async () => {
      const radiusQ96 = (2n ** 96n) * 100n // radius = 100
      const sqrtNumAssetsQ96 = (2n ** 96n) * 1732n / 1000n // sqrt(3) ≈ 1.732
      
      const [valid, reason] = await tickTest.validateLiquidityAtTick(
        100,
        -100, // negative delta (removing)
        1000,
        radiusQ96,
        NUM_ASSETS,
        sqrtNumAssetsQ96
      )
      expect(valid).to.eq(true)
      expect(reason).to.eq('')
    })

    it('validates adding liquidity at valid tick', async () => {
      const radiusQ96 = (2n ** 96n) * 100n // radius = 100
      const sqrtNumAssetsQ96 = (2n ** 96n) * 1732n / 1000n // sqrt(3) ≈ 1.732
      
      const [valid, reason] = await tickTest.validateLiquidityAtTick(
        100,
        100, // positive delta (adding)
        0,
        radiusQ96,
        NUM_ASSETS,
        sqrtNumAssetsQ96
      )
      expect(valid).to.eq(true)
      expect(reason).to.eq('')
    })

    it('validates liquidity at maximum tick', async () => {
      const radiusQ96 = (2n ** 96n) * 100n // radius = 100
      const sqrtNumAssetsQ96 = (2n ** 96n) * 1732n / 1000n // sqrt(3) ≈ 1.732
      
      // Test at maximum valid tick (10000 - 1 = 9999)
      const [valid, reason] = await tickTest.validateLiquidityAtTick(
        9999,
        100,
        0,
        radiusQ96,
        NUM_ASSETS,
        sqrtNumAssetsQ96
      )
      // Tick 9999 is actually valid (< MAX_TICK = 10000)
      expect(valid).to.eq(true)
      expect(reason).to.eq('')
    })
  })
})