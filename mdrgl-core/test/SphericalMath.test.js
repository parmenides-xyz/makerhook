const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SphericalMath", function () {
    let sphericalMath;
    let Q96;

    beforeEach(async function () {
        const SphericalMathTest = await ethers.getContractFactory("SphericalMathTest");
        sphericalMath = await SphericalMathTest.deploy();
        await sphericalMath.waitForDeployment();
        
        Q96 = 2n ** 96n; // Use BigInt notation for ethers v6
    });

    describe("sqrt", function () {
        it("should return 0 for input 0", async function () {
            const result = await sphericalMath.sqrt(0);
            expect(result).to.equal(0);
        });

        it("should return Q96 for input Q96 (sqrt(1) = 1)", async function () {
            const result = await sphericalMath.sqrt(Q96);
            expect(result).to.equal(Q96);
        });

        it("should return approximately 1.414*Q96 for input 2*Q96", async function () {
            const input = Q96 * 2n;
            const result = await sphericalMath.sqrt(input);
            const expected = Q96 * 14142n / 10000n; // 1.4142
            const tolerance = Q96 / 100n; // 1% tolerance
            
            expect(result).to.be.closeTo(expected, tolerance);
        });

        it("should return approximately 2*Q96 for input 4*Q96", async function () {
            const input = Q96 * 4n;
            const result = await sphericalMath.sqrt(input);
            const expected = Q96 * 2n;
            
            expect(result).to.equal(expected);
        });

        it("should handle small values less than Q96", async function () {
            const input = Q96 / 4n; // 0.25 in Q96
            const result = await sphericalMath.sqrt(input);
            const expected = Q96 / 2n; // sqrt(0.25) = 0.5
            
            expect(result).to.equal(expected);
        });

        it("should handle very small values", async function () {
            const input = 1n;
            const result = await sphericalMath.sqrt(input);
            // sqrt(1/2^96) * 2^96 = sqrt(1) * 2^48 = 2^48
            const expected = 2n ** 48n;
            
            expect(result).to.equal(expected);
        });

        it("should handle large values", async function () {
            const input = Q96 * 100n;
            const result = await sphericalMath.sqrt(input);
            const expected = Q96 * 10n; // sqrt(100) = 10
            
            expect(result).to.equal(expected);
        });

        it("should maintain monotonicity (sqrt(x) <= sqrt(x+1))", async function () {
            const testValues = [
                Q96 / 2n,
                Q96 - 1n,
                Q96,
                Q96 + 1n,
                Q96 * 2n
            ];

            for (let i = 0; i < testValues.length - 1; i++) {
                const sqrt1 = await sphericalMath.sqrt(testValues[i]);
                const sqrt2 = await sphericalMath.sqrt(testValues[i + 1]);
                
                expect(sqrt2).to.be.gte(sqrt1);
            }
        });

        it("should satisfy sqrt(x)^2 ≈ x for various values", async function () {
            const testValues = [
                Q96 / 10n,
                Q96 / 2n,
                Q96,
                Q96 * 2n,
                Q96 * 10n
            ];

            for (const x of testValues) {
                const sqrtX = await sphericalMath.sqrt(x);
                // (sqrt(x))^2 should approximately equal x
                // In Q96: sqrtX * sqrtX / Q96 ≈ x
                const squared = sqrtX * sqrtX / Q96;
                const tolerance = x / 100n; // 1% tolerance
                
                expect(squared).to.be.closeTo(x, tolerance);
            }
        });

        it("should handle edge case at Q96 boundary", async function () {
            const testCases = [
                { input: Q96 - 100n, name: "Q96 - 100" },
                { input: Q96 - 1n, name: "Q96 - 1" },
                { input: Q96, name: "Q96" },
                { input: Q96 + 1n, name: "Q96 + 1" },
                { input: Q96 + 100n, name: "Q96 + 100" }
            ];

            let prevResult = 0n;
            for (const testCase of testCases) {
                const result = await sphericalMath.sqrt(testCase.input);
                
                // Check monotonicity
                expect(result).to.be.gte(prevResult);
                prevResult = result;
                
                // Check approximate correctness
                const squared = result * result / Q96;
                const tolerance = testCase.input / 50n; // 2% tolerance near boundary
                expect(squared).to.be.closeTo(testCase.input, tolerance);
            }
        });
    });

    describe("computeOrthogonalComponent", function () {
        it("should return 0 for all equal reserves", async function () {
            // If all reserves are equal (e.g., [100, 100, 100])
            // sumReserves = 300, sumSquares = 30000
            // orthogonal = 30000 - (300)²/3 = 30000 - 30000 = 0
            const sumReservesQ96 = 300n * Q96;
            const sumSquaresQ96 = 30000n * Q96;
            const numAssets = 3n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            expect(result).to.equal(0n);
        });

        it("should compute correct orthogonal component for imbalanced reserves", async function () {
            // Reserves: [100, 200] in raw values
            // sumReserves = 300, sumSquares = 100² + 200² = 50000
            // orthogonal = 50000 - (300)²/2 = 50000 - 45000 = 5000
            const sumReservesQ96 = 300n * Q96;
            const sumSquaresQ96 = 50000n * Q96;
            const numAssets = 2n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            const expected = 5000n * Q96;
            expect(result).to.equal(expected);
        });

        it("should handle single asset case", async function () {
            // For single asset: orthogonal = x² - x²/1 = 0
            const sumReservesQ96 = 100n * Q96;
            const sumSquaresQ96 = 10000n * Q96;
            const numAssets = 1n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            expect(result).to.equal(0n);
        });

        it("should handle zero reserves", async function () {
            const sumReservesQ96 = 0n;
            const sumSquaresQ96 = 0n;
            const numAssets = 2n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            expect(result).to.equal(0n);
        });

        it("should revert for zero assets", async function () {
            const sumReservesQ96 = 100n * Q96;
            const sumSquaresQ96 = 10000n * Q96;
            const numAssets = 0n;
            
            await expect(
                sphericalMath.computeOrthogonalComponent(
                    sumSquaresQ96,
                    sumReservesQ96,
                    numAssets
                )
            ).to.be.revertedWith("Invalid asset count");
        });

        it("should handle large imbalance correctly", async function () {
            // Reserves: [1000, 1] - highly imbalanced
            // sumReserves = 1001, sumSquares = 1000000 + 1 = 1000001
            // orthogonal = 1000001 - (1001)²/2 = 1000001 - 501000.5 ≈ 499000.5
            const sumReservesQ96 = 1001n * Q96;
            const sumSquaresQ96 = 1000001n * Q96;
            const numAssets = 2n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            // Expected: approximately 499000.5 * Q96
            // Due to integer division, we expect 499000 * Q96
            const expected = 499000n * Q96 + Q96 / 2n;
            const tolerance = Q96; // Allow small rounding difference
            
            expect(result).to.be.closeTo(expected, tolerance);
        });

        it("should handle multiple assets correctly", async function () {
            // Reserves: [10, 20, 30, 40] 
            // sumReserves = 100, sumSquares = 100 + 400 + 900 + 1600 = 3000
            // orthogonal = 3000 - (100)²/4 = 3000 - 2500 = 500
            const sumReservesQ96 = 100n * Q96;
            const sumSquaresQ96 = 3000n * Q96;
            const numAssets = 4n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            const expected = 500n * Q96;
            expect(result).to.equal(expected);
        });

        it("should maintain precision for Q96 arithmetic", async function () {
            // Test with actual Q96 values that might come from real calculations
            // This tests the mulDiv operations don't overflow
            const sumReservesQ96 = Q96 * 1000n; // 1000 in Q96
            const sumSquaresQ96 = Q96 * 1000000n; // 1000² in Q96
            const numAssets = 1n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            // For single asset, should be 0
            expect(result).to.equal(0n);
        });

        it("should return 0 when sumSquares is less than expected (numerical safety)", async function () {
            // This shouldn't happen with real data, but function should handle it
            // Set sumSquares artificially low
            const sumReservesQ96 = 1000n * Q96;
            const sumSquaresQ96 = 100n * Q96; // Too low for the given sum
            const numAssets = 2n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            // Should return 0 for safety
            expect(result).to.equal(0n);
        });

        it("should handle 5-asset pool correctly", async function () {
            // Reserves: [100, 150, 200, 250, 300]
            // sumReserves = 1000
            // sumSquares = 100² + 150² + 200² + 250² + 300² = 10000 + 22500 + 40000 + 62500 + 90000 = 225000
            // orthogonal = 225000 - (1000)²/5 = 225000 - 200000 = 25000
            const sumReservesQ96 = 1000n * Q96;
            const sumSquaresQ96 = 225000n * Q96;
            const numAssets = 5n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            const expected = 25000n * Q96;
            expect(result).to.equal(expected);
        });

        it("should handle 10-asset pool with equal reserves", async function () {
            // 10 assets, all with reserve = 100
            // sumReserves = 1000, sumSquares = 10 * 100² = 100000
            // orthogonal = 100000 - (1000)²/10 = 100000 - 100000 = 0
            const sumReservesQ96 = 1000n * Q96;
            const sumSquaresQ96 = 100000n * Q96;
            const numAssets = 10n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            expect(result).to.equal(0n);
        });

        it("should handle 100-asset pool", async function () {
            // 100 assets with varying reserves
            // For simplicity: 50 assets at 10, 50 assets at 30
            // sumReserves = 50*10 + 50*30 = 500 + 1500 = 2000
            // sumSquares = 50*10² + 50*30² = 50*100 + 50*900 = 5000 + 45000 = 50000
            // orthogonal = 50000 - (2000)²/100 = 50000 - 40000 = 10000
            const sumReservesQ96 = 2000n * Q96;
            const sumSquaresQ96 = 50000n * Q96;
            const numAssets = 100n;
            
            const result = await sphericalMath.computeOrthogonalComponent(
                sumSquaresQ96,
                sumReservesQ96,
                numAssets
            );
            
            const expected = 10000n * Q96;
            expect(result).to.equal(expected);
        });
    });

    describe("calculatePriceRatio", function () {
        it("should return 1 (Q96) for equal reserves", async function () {
            const reserveI = 100n * Q96;  // Convert to Q96
            const reserveJ = 100n * Q96;  // Convert to Q96
            const radiusQ96 = 1000n * Q96;
            
            const result = await sphericalMath.calculatePriceRatio(
                reserveI,
                reserveJ,
                radiusQ96
            );
            
            expect(result).to.equal(Q96); // Ratio of 1.0 in Q96
        });

        it("should calculate correct ratio for different reserves", async function () {
            // reserveI = 100, reserveJ = 200, radius = 1000
            // ratio = (1000 - 200) / (1000 - 100) = 800 / 900 = 0.888...
            const reserveI = 100n * Q96;
            const reserveJ = 200n * Q96;
            const radiusQ96 = 1000n * Q96;
            
            const result = await sphericalMath.calculatePriceRatio(
                reserveI,
                reserveJ,
                radiusQ96
            );
            
            const expected = Q96 * 800n / 900n; // ~0.888 in Q96
            const tolerance = Q96 / 1000n; // 0.1% tolerance
            
            expect(result).to.be.closeTo(expected, tolerance);
        });

        it("should handle inverse relationship correctly", async function () {
            const reserveI = 100n * Q96;
            const reserveJ = 200n * Q96;
            const radiusQ96 = 1000n * Q96;
            
            const ratioIJ = await sphericalMath.calculatePriceRatio(
                reserveI,
                reserveJ,
                radiusQ96
            );
            
            const ratioJI = await sphericalMath.calculatePriceRatio(
                reserveJ,
                reserveI,
                radiusQ96
            );
            
            // ratioIJ * ratioJI should equal Q96² (1.0 * 1.0 in Q96)
            const product = ratioIJ * ratioJI / Q96;
            const tolerance = Q96 / 100n; // 1% tolerance
            
            expect(product).to.be.closeTo(Q96, tolerance);
        });

        it("should revert when reserveI exceeds radius", async function () {
            const reserveI = 1001n * Q96;
            const reserveJ = 100n * Q96;
            const radiusQ96 = 1000n * Q96;
            
            await expect(
                sphericalMath.calculatePriceRatio(reserveI, reserveJ, radiusQ96)
            ).to.be.revertedWith("Reserve I exceeds radius");
        });

        it("should revert when reserveJ exceeds radius", async function () {
            const reserveI = 100n * Q96;
            const reserveJ = 1001n * Q96;
            const radiusQ96 = 1000n * Q96;
            
            await expect(
                sphericalMath.calculatePriceRatio(reserveI, reserveJ, radiusQ96)
            ).to.be.revertedWith("Reserve J exceeds radius");
        });

        it("should revert for zero radius", async function () {
            const reserveI = 100n * Q96;
            const reserveJ = 100n * Q96;
            const radiusQ96 = 0n;
            
            await expect(
                sphericalMath.calculatePriceRatio(reserveI, reserveJ, radiusQ96)
            ).to.be.revertedWith("Invalid radius");
        });

        it("should revert when reserve is too close to radius (99%)", async function () {
            const radiusQ96 = 1000n * Q96;
            const reserveI = 100n * Q96;
            const reserveJ = 995n * Q96; // 99.5% of radius
            
            await expect(
                sphericalMath.calculatePriceRatio(reserveI, reserveJ, radiusQ96)
            ).to.be.revertedWith("Reserve J too close to radius");
        });


        it("should handle extreme price ratios", async function () {
            // Large difference in reserves should give extreme ratio
            const reserveI = 10n * Q96;
            const reserveJ = 900n * Q96;
            const radiusQ96 = 1000n * Q96;
            
            const result = await sphericalMath.calculatePriceRatio(
                reserveI,
                reserveJ,
                radiusQ96
            );
            
            // ratio = (1000 - 900) / (1000 - 10) = 100 / 990 ≈ 0.101
            const expected = Q96 * 100n / 990n;
            const tolerance = Q96 / 1000n;
            
            expect(result).to.be.closeTo(expected, tolerance);
        });

        it("should maintain consistency with sphere economics", async function () {
            // Test that higher reserve leads to lower price
            const radius = 1000n;
            const radiusQ96 = radius * Q96;
            
            const reserve1 = 100n * Q96;
            const reserve2 = 200n * Q96;
            const reserve3 = 300n * Q96;
            
            // Price of asset with reserve1 vs reserve2
            const ratio12 = await sphericalMath.calculatePriceRatio(
                reserve1,
                reserve2,
                radiusQ96
            );
            
            // Price of asset with reserve1 vs reserve3
            const ratio13 = await sphericalMath.calculatePriceRatio(
                reserve1,
                reserve3,
                radiusQ96
            );
            
            // Asset with lower reserve (1) should have higher price
            // So ratio should decrease as other reserve increases
            expect(ratio13).to.be.lt(ratio12);
        });

        it("should work with Q96 format reserves", async function () {
            // Test with reserves already in Q96 format
            const reserveI = Q96 * 100n / 1000n; // 0.1 in Q96
            const reserveJ = Q96 * 200n / 1000n; // 0.2 in Q96
            const radiusQ96 = Q96; // 1.0 in Q96
            
            const result = await sphericalMath.calculatePriceRatio(
                reserveI,
                reserveJ,
                radiusQ96
            );
            
            // ratio = (1 - 0.2) / (1 - 0.1) = 0.8 / 0.9 ≈ 0.888
            const expected = Q96 * 8n / 9n;
            const tolerance = Q96 / 1000n;
            
            expect(result).to.be.closeTo(expected, tolerance);
        });
    });

    describe("updateSumsAfterTrade", function () {
        it("should handle no change (old equals new)", async function () {
            const sumReservesQ96 = 1000n * Q96;
            const sumSquaresQ96 = 500000n * Q96;
            const oldReserveI = 100n * Q96;
            const newReserveI = 100n * Q96;
            const oldReserveJ = 200n * Q96;
            const newReserveJ = 200n * Q96;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            expect(newSumReserves).to.equal(sumReservesQ96);
            expect(newSumSquares).to.equal(sumSquaresQ96);
        });

        it("should update sums correctly for a simple swap", async function () {
            // Initial: [100, 200, 300], sum = 600, sum_squares = 140000
            const sumReservesQ96 = 600n * Q96;
            const sumSquaresQ96 = 140000n * Q96;
            
            // Swap: reserve[0]: 100 -> 110, reserve[1]: 200 -> 190
            const oldReserveI = 100n * Q96;
            const newReserveI = 110n * Q96;
            const oldReserveJ = 200n * Q96;
            const newReserveJ = 190n * Q96;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // New sum = 110 + 190 + 300 = 600 (unchanged in this case)
            expect(newSumReserves).to.equal(600n * Q96);
            
            // New sum_squares = 110² + 190² + 300² = 12100 + 36100 + 90000 = 138200
            expect(newSumSquares).to.equal(138200n * Q96);
        });

        it("should handle reserves increasing", async function () {
            const sumReservesQ96 = 500n * Q96;
            const sumSquaresQ96 = 125000n * Q96;
            
            // Both reserves increase
            const oldReserveI = 100n * Q96;
            const newReserveI = 150n * Q96;
            const oldReserveJ = 200n * Q96;
            const newReserveJ = 250n * Q96;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // Delta = (150 + 250) - (100 + 200) = 100
            expect(newSumReserves).to.equal(600n * Q96);
            
            // Old squares: 100² + 200² = 10000 + 40000 = 50000
            // New squares: 150² + 250² = 22500 + 62500 = 85000
            // Delta squares = 85000 - 50000 = 35000
            expect(newSumSquares).to.equal(160000n * Q96);
        });

        it("should handle reserves decreasing", async function () {
            const sumReservesQ96 = 600n * Q96;
            const sumSquaresQ96 = 180000n * Q96;
            
            // Both reserves decrease
            const oldReserveI = 200n * Q96;
            const newReserveI = 150n * Q96;
            const oldReserveJ = 300n * Q96;
            const newReserveJ = 250n * Q96;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // Delta = (150 + 250) - (200 + 300) = -100
            expect(newSumReserves).to.equal(500n * Q96);
            
            // Old squares: 200² + 300² = 40000 + 90000 = 130000
            // New squares: 150² + 250² = 22500 + 62500 = 85000
            // sumSquares - 130000 + 85000 = 180000 - 130000 + 85000 = 135000
            expect(newSumSquares).to.equal(135000n * Q96);
        });

        it("should handle one increase, one decrease (typical swap)", async function () {
            const sumReservesQ96 = 1000n * Q96;
            const sumSquaresQ96 = 500000n * Q96;
            
            // Swap: I increases, J decreases
            const oldReserveI = 300n * Q96;
            const newReserveI = 350n * Q96;
            const oldReserveJ = 400n * Q96;
            const newReserveJ = 350n * Q96;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // Sum unchanged: (350 + 350) - (300 + 400) = 0
            expect(newSumReserves).to.equal(1000n * Q96);
            
            // Old squares: 300² + 400² = 90000 + 160000 = 250000
            // New squares: 350² + 350² = 122500 + 122500 = 245000
            // sumSquares - 250000 + 245000 = 500000 - 250000 + 245000 = 495000
            expect(newSumSquares).to.equal(495000n * Q96);
        });

        it("should handle zero old reserves", async function () {
            const sumReservesQ96 = 100n * Q96;
            const sumSquaresQ96 = 10000n * Q96;
            
            // Adding liquidity from zero
            const oldReserveI = 0n;
            const newReserveI = 50n * Q96;
            const oldReserveJ = 0n;
            const newReserveJ = 50n * Q96;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // Sum increases by 100
            expect(newSumReserves).to.equal(200n * Q96);
            
            // Squares increase by 50² + 50² = 5000
            expect(newSumSquares).to.equal(15000n * Q96);
        });

        it("should handle zero new reserves", async function () {
            const sumReservesQ96 = 200n * Q96;
            const sumSquaresQ96 = 20000n * Q96;
            
            // Removing all liquidity
            const oldReserveI = 50n * Q96;
            const newReserveI = 0n;
            const oldReserveJ = 50n * Q96;
            const newReserveJ = 0n;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // Sum decreases by 100
            expect(newSumReserves).to.equal(100n * Q96);
            
            // Squares decrease by 50² + 50² = 5000
            expect(newSumSquares).to.equal(15000n * Q96);
        });

        it("should maintain precision with Q96 arithmetic", async function () {
            // Use actual Q96 values
            const sumReservesQ96 = Q96 * 1000n;
            const sumSquaresQ96 = Q96 * 500000n;
            
            const oldReserveI = Q96 * 333n;
            const newReserveI = Q96 * 334n;
            const oldReserveJ = Q96 * 667n;
            const newReserveJ = Q96 * 666n;
            
            const [newSumReserves, newSumSquares] = await sphericalMath.updateSumsAfterTrade(
                sumReservesQ96,
                sumSquaresQ96,
                oldReserveI,
                newReserveI,
                oldReserveJ,
                newReserveJ
            );
            
            // Sum unchanged: (334 + 666) - (333 + 667) = 0
            expect(newSumReserves).to.equal(Q96 * 1000n);
            
            // Calculate expected sum of squares
            // Old: 333² + 667² = 110889 + 444889 = 555778
            // New: 334² + 666² = 111556 + 443556 = 555112
            // Change: 555112 - 555778 = -666
            const expectedSumSquares = Q96 * (500000n - 666n);
            
            // Allow small tolerance for rounding
            expect(newSumSquares).to.be.closeTo(expectedSumSquares, Q96);
        });
    });

    describe("validateConstraintFromSums", function () {
        it("should validate perfect sphere constraint", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 * 500n; // 0.05% relative tolerance for integer approximation
            
            // For equal reserves on 2-asset sphere: (r - x)² + (r - x)² = r²
            // 2(r - x)² = r²
            // (r - x)² = r²/2
            // r - x = ±r/√2
            // x = r(1 ∓ 1/√2)
            // Using plus: x = r(1 + 1/√2) ≈ 1000(1.707) = 1707
            const x = 1707n;
            const sumReservesQ96 = (x * 2n) * Q96;
            const sumSquaresQ96 = (x * x * 2n) * Q96;
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(true);
            expect(deviationQ96).to.be.lte(epsilonQ96);
        });

        it("should reject constraint violation", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 / 100n;
            
            const sumReservesQ96 = 2000n * Q96;
            const sumSquaresQ96 = 2000000n * Q96;
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(false);
            expect(deviationQ96).to.be.gt(epsilonQ96);
        });

        it("should validate equal reserves on sphere", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 4n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 * 10n;
            
            const sumReservesQ96 = 2000n * Q96;
            const sumSquaresQ96 = 1000000n * Q96;
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(true);
        });

        it("should calculate correct deviation", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 * 1000n; // Reasonable tolerance
            
            // Use x=1707 (optimal) plus a tiny perturbation in sumSquares
            // to create a small but non-zero deviation
            const x = 1707n;
            const sumReservesQ96 = (x * 2n) * Q96;
            const sumSquaresQ96 = (x * x * 2n) * Q96 + Q96 * 100n; // Add small perturbation
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(true);
            expect(deviationQ96).to.be.gt(0n);
            expect(deviationQ96).to.be.lte(epsilonQ96);
        });

        it("should handle single asset case", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 1n;
            const sqrtNumAssetsQ96 = Q96;
            const epsilonQ96 = Q96 / 100n; // Tight tolerance since exact solution
            
            // For n=1: (r - x₁)² = r²
            // This gives: r² - 2rx₁ + x₁² = r²
            // Simplifying: x₁² - 2rx₁ = 0
            // So: x₁(x₁ - 2r) = 0
            // Non-zero solution: x₁ = 2r = 2000
            const sumReservesQ96 = 2000n * Q96;
            const sumSquaresQ96 = 4000000n * Q96; // (2000)² = 4000000
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(true);
            expect(deviationQ96).to.equal(0n);
        });

        it("should handle multi-asset pools", async function () {
            const radiusQ96 = 10000n * Q96;
            const numAssets = 10n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 * 50000n; // Larger tolerance for approximation error
            
            // For 10 equal reserves: 10(r - x)² = r²
            // (r - x)² = r²/10
            // r - x = r/√10
            // x = r(1 - 1/√10) ≈ 10000(1 - 0.316) = 6838
            const x = 6838n;
            const sumReservesQ96 = (x * 10n) * Q96;
            const sumSquaresQ96 = (x * x * 10n) * Q96;
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(true);
        });

        it("should detect violations with zero tolerance", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = 0n;
            
            const sumReservesQ96 = 1414n * Q96 + 1n;
            const sumSquaresQ96 = 1000000n * Q96;
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(false);
            expect(deviationQ96).to.be.gt(0n);
        });

        it("should handle edge case where reserves sum to 2nr", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 / 100n; // Tight tolerance for exact solution
            
            // Asymmetric solution: x₁ = 2000, x₂ = 1000
            // Check: (1000 - 2000)² + (1000 - 1000)² = 1000000 + 0 = 1000000 = r²
            const x1 = 2000n;
            const x2 = 1000n;
            const sumReservesQ96 = (x1 + x2) * Q96;
            const sumSquaresQ96 = (x1 * x1 + x2 * x2) * Q96;
            
            const [valid, deviationQ96] = await sphericalMath.validateConstraintFromSums(
                sumReservesQ96,
                sumSquaresQ96,
                radiusQ96,
                numAssets,
                sqrtNumAssetsQ96,
                epsilonQ96
            );
            
            expect(valid).to.equal(true);
        });
    });

    describe("validatePoolConstants", function () {
        it("should accept valid pool constants", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 4n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 / 10n; // 0.1 tolerance

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.not.be.reverted;
        });

        it("should reject numAssets less than 2", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 1n;
            const sqrtNumAssetsQ96 = Q96;
            const epsilonQ96 = Q96 / 10n;

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.be.revertedWith("Invalid asset count");
        });

        it("should reject zero radius", async function () {
            const radiusQ96 = 0n;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96 / 10n;

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.be.revertedWith("Invalid radius");
        });

        it("should reject zero epsilon", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = 0n;

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.be.revertedWith("Invalid epsilon");
        });

        it("should reject epsilon >= radius", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = 1001n * Q96;

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.be.revertedWith("Invalid epsilon");
        });

        it("should reject incorrect sqrtNumAssetsQ96", async function () {
            const radiusQ96 = 1000n * Q96;
            const numAssets = 4n;
            const sqrtNumAssetsQ96 = Q96 * 3n; // Wrong! Should be 2*Q96
            const epsilonQ96 = Q96 / 10n;

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.be.revertedWith("Incorrect sqrt computation");
        });

        it("should reject radius that could cause overflow", async function () {
            const radiusQ96 = 2n ** 200n; // Very large, r² would overflow
            const numAssets = 2n;
            const sqrtNumAssetsQ96 = await sphericalMath.sqrt(numAssets * Q96);
            const epsilonQ96 = Q96;

            await expect(
                sphericalMath.validatePoolConstants(
                    radiusQ96,
                    numAssets,
                    sqrtNumAssetsQ96,
                    epsilonQ96
                )
            ).to.be.revertedWith("Radius overflow risk");
        });
    });
});