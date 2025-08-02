const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('SphericalMath', function () {
  let sphericalMathTest;

  beforeEach(async function () {
    // Deploy test contract that exposes SphericalMath library functions
    const SphericalMathTest = await ethers.getContractFactory('SphericalMathTest');
    sphericalMathTest = await SphericalMathTest.deploy();
    await sphericalMathTest.waitForDeployment();
  });

  // Helper to convert to Q96
  function toQ96(value) {
    return value * (2n ** 96n) / ethers.parseEther('1');
  }

  describe('sqrt', function () {
    it('Should compute square root correctly', async function () {
      // Test sqrt(4) = 2, in Q96 format
      // 4 in Q96 = 4 * 2^96
      const fourQ96 = 4n * (2n ** 96n);
      const result = await sphericalMathTest.sqrt(fourQ96);
      // Expected: 2 in Q48 format (since sqrt of Q96 is Q48)
      expect(result).to.equal(2n * (2n ** 48n));

      // Test sqrt(9) = 3
      const nineQ96 = 9n * (2n ** 96n);
      const result2 = await sphericalMathTest.sqrt(nineQ96);
      expect(result2).to.equal(3n * (2n ** 48n));

      // Test sqrt(16) = 4
      const sixteenQ96 = 16n * (2n ** 96n);
      const result3 = await sphericalMathTest.sqrt(sixteenQ96);
      expect(result3).to.equal(4n * (2n ** 48n));
    });

    it('Should handle sqrt(0) = 0', async function () {
      const result = await sphericalMathTest.sqrt(0);
      expect(result).to.equal(0);
    });

    it('Should compute sqrt of large numbers', async function () {
      // Test sqrt(1e18) in Q96 format
      const oneEtherQ96 = (ethers.parseEther('1') * (2n ** 96n)) / ethers.parseEther('1');
      const result = await sphericalMathTest.sqrt(oneEtherQ96);
      // Expected: sqrt(1) = 1 in Q48 format
      expect(result).to.equal(2n ** 48n);
    });
  });

  describe('validateConstraintFromSums', function () {
    it('Should validate constraint for balanced reserves', async function () {
      // Test case: 5 equal reserves of 100 each
      const numAssets = 5;
      const reserve = ethers.parseEther('100');
      const sumReservesQ96 = (reserve * 5n * (2n ** 96n)) / ethers.parseEther('1');
      const sumSquaresQ96 = (reserve * reserve * 5n * (2n ** 96n)) / (ethers.parseEther('1') * ethers.parseEther('1'));
      
      // Radius ≈ 180.901699437494747
      const radiusQ96 = (ethers.parseEther('180.901699437494747') * (2n ** 96n)) / ethers.parseEther('1');
      const sqrtNumAssetsQ96 = (ethers.parseEther('2.236067977499789696') * (2n ** 96n)) / ethers.parseEther('1');
      const epsilonQ96 = (ethers.parseEther('1') * (2n ** 96n)) / ethers.parseEther('1'); // 1 unit tolerance

      const [valid, deviation] = await sphericalMathTest.validateConstraintFromSums(
        sumReservesQ96,
        sumSquaresQ96,
        radiusQ96,
        numAssets,
        sqrtNumAssetsQ96,
        epsilonQ96
      );

      expect(valid).to.be.true;
      expect(deviation).to.be.lt(epsilonQ96);
    });

    it('Should detect constraint violation', async function () {
      // Test case: reserves that don't satisfy sphere constraint
      const numAssets = 5;
      const reserve = ethers.parseEther('100');
      const sumReservesQ96 = (reserve * 5n * (2n ** 96n)) / ethers.parseEther('1');
      const sumSquaresQ96 = (reserve * reserve * 5n * (2n ** 96n)) / (ethers.parseEther('1') * ethers.parseEther('1'));
      // Using wrong radius intentionally to test constraint violation
      const radiusQ96 = (ethers.parseEther('200') * (2n ** 96n)) / ethers.parseEther('1');
      const sqrtNumAssetsQ96 = (ethers.parseEther('2.236067977499789696') * (2n ** 96n)) / ethers.parseEther('1');
      const epsilonQ96 = (ethers.parseEther('1') * (2n ** 96n)) / ethers.parseEther('1'); // 1 unit tolerance

      const [valid, deviation] = await sphericalMathTest.validateConstraintFromSums(
        sumReservesQ96,
        sumSquaresQ96,
        radiusQ96,
        numAssets,
        sqrtNumAssetsQ96,
        epsilonQ96
      );

      expect(valid).to.be.false;
      expect(deviation).to.be.gt(epsilonQ96);
    });
  });

  describe('computeOrthogonalComponent', function () {
    it('Should return 0 for reserves on equal-price vector', async function () {
      // Test case: 3 equal reserves => orthogonal component = 0
      const numAssets = 5;
      const reserve = ethers.parseEther('100');
      const sumSquaresQ96 = (reserve * reserve * 5n * (2n ** 96n)) / (ethers.parseEther('1') * ethers.parseEther('1'));
      const sumReservesQ96 = (reserve * 5n * (2n ** 96n)) / ethers.parseEther('1');

      const wQ96 = await sphericalMathTest.computeOrthogonalComponent(
        sumSquaresQ96,
        sumReservesQ96,
        numAssets
      );

      // Should be very close to 0
      expect(wQ96).to.be.lt(2n ** 96n / 1000n);
    });

    it('Should compute non-zero orthogonal component', async function () {
      // Test case: unequal reserves [150, 50, 100, 120, 80]
      const numAssets = 5;
      const reserves = [
        ethers.parseEther('150'),
        ethers.parseEther('50'),
        ethers.parseEther('100'),
        ethers.parseEther('120'),
        ethers.parseEther('80')
      ];
      
      // Compute sums manually
      let sumReserves = 0n;
      let sumSquares = 0n;
      for (const reserve of reserves) {
        sumReserves += reserve;
        sumSquares += (reserve * reserve) / ethers.parseEther('1');
      }
      const sumReservesQ96 = (sumReserves * (2n ** 96n)) / ethers.parseEther('1');
      const sumSquaresQ96 = (sumSquares * (2n ** 96n)) / ethers.parseEther('1');

      const wQ96 = await sphericalMathTest.computeOrthogonalComponent(
        sumSquaresQ96,
        sumReservesQ96,
        numAssets
      );

      // Should be non-zero since reserves are not equal
      expect(wQ96).to.be.gt(0);
    });
  });

  describe('calculatePriceRatio', function () {
    it('Should return 1 for equal reserves', async function () {
      const reserveI = (ethers.parseEther('100') * (2n ** 96n)) / ethers.parseEther('1');
      const reserveJ = (ethers.parseEther('100') * (2n ** 96n)) / ethers.parseEther('1');
      // For 5 assets with reserves of 100 each, radius is ~180.9 (the larger root)
      const radiusQ96 = (ethers.parseEther('180.901699437494747') * (2n ** 96n)) / ethers.parseEther('1');

      const priceQ96 = await sphericalMathTest.calculatePriceRatio(
        reserveI,
        reserveJ,
        radiusQ96
      );

      // Price should be 1 (in Q96 format)
      expect(priceQ96).to.equal(2n ** 96n);
    });

    it('Should compute correct price ratio for unequal reserves', async function () {
      // If xi = 30 and xj = 50, and r = 180.901...
      // Price = (r - xj)/(r - xi) = (180.901 - 50)/(180.901 - 30) = 130.901/150.901 ≈ 0.868
      const reserveI = (ethers.parseEther('30') * (2n ** 96n)) / ethers.parseEther('1');
      const reserveJ = (ethers.parseEther('50') * (2n ** 96n)) / ethers.parseEther('1');
      // Using same radius as above for consistency
      const radiusQ96 = (ethers.parseEther('180.901699437494747') * (2n ** 96n)) / ethers.parseEther('1');

      const priceQ96 = await sphericalMathTest.calculatePriceRatio(
        reserveI,
        reserveJ,
        radiusQ96
      );

      // Price = (180.901 - 50)/(180.901 - 30) = 130.901/150.901 ≈ 0.868
      const expectedPrice = (ethers.parseEther('0.868') * (2n ** 96n)) / ethers.parseEther('1');
      const tolerance = expectedPrice / 100n; // 1% tolerance
      expect(priceQ96).to.be.closeTo(expectedPrice, tolerance);
    });
  });

  describe('updateSumsAfterTrade', function () {
    it('Should correctly update sums after a trade', async function () {
      // Initial state: reserves = [100, 100, 100, 100, 100]
      const initialReserve = ethers.parseEther('100');
      const oldSumReservesQ96 = (initialReserve * 5n * (2n ** 96n)) / ethers.parseEther('1');
      // Sum of squares in Q96: Σ(x²) * Q96 = 5 * (100e18)² * Q96
      const oldSumSquaresQ96 = 5n * (initialReserve * initialReserve * (2n ** 96n)) / ethers.parseEther('1');
      
      // Trade: reserves[0]: 100 -> 110, reserves[1]: 100 -> 90 (other 3 remain at 100)
      const oldReserveI = initialReserve;
      const oldReserveJ = initialReserve;
      const newReserveI = ethers.parseEther('110');
      const newReserveJ = ethers.parseEther('90');

      const [newSumReservesQ96, newSumSquaresQ96] = await sphericalMathTest.updateSumsAfterTrade(
        oldSumReservesQ96,
        oldSumSquaresQ96,
        oldReserveI,
        newReserveI,
        oldReserveJ,
        newReserveJ
      );

      // Sum should still be 500 (3×100 + 110 + 90)
      expect(newSumReservesQ96).to.equal(oldSumReservesQ96);
      
      // Sum of squares should be 3×100² + 110² + 90² = 3×10000 + 12100 + 8100 = 50200
      // In Q96: 3×(100e18)² + (110e18)² + (90e18)² scaled by Q96
      const hundred = ethers.parseEther('100');
      const hundredTen = ethers.parseEther('110');
      const ninety = ethers.parseEther('90');
      const expectedSumSquares = (3n * (hundred * hundred) + (hundredTen * hundredTen) + (ninety * ninety)) * (2n ** 96n) / ethers.parseEther('1');
      const tolerance = expectedSumSquares / 1000000n;
      expect(newSumSquaresQ96).to.be.closeTo(expectedSumSquares, tolerance);
    });

    it('Should handle zero trades correctly', async function () {
      const sumReservesQ96 = (ethers.parseEther('100') * 5n * (2n ** 96n)) / ethers.parseEther('1');
      // Sum of squares: 5 * (100e18)² * Q96
      const sumSquaresQ96 = 5n * (ethers.parseEther('100') * ethers.parseEther('100') * (2n ** 96n)) / ethers.parseEther('1');
      const reserve = ethers.parseEther('100');

      const [newSumReservesQ96, newSumSquaresQ96] = await sphericalMathTest.updateSumsAfterTrade(
        sumReservesQ96,
        sumSquaresQ96,
        reserve,
        reserve,
        reserve,
        reserve
      );

      // Should remain unchanged
      expect(newSumReservesQ96).to.equal(sumReservesQ96);
      expect(newSumSquaresQ96).to.equal(sumSquaresQ96);
    });
  });
});