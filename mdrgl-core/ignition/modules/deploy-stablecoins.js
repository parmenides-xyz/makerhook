const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("StablecoinsModule", (m) => {
  // Get the deployer account
  const deployer = m.getAccount(0);
  
  // Deploy Mock USDC (6 decimals)
  const mUSDC = m.contract("MockStablecoin", [
    "Mock USDC",
    "mUSDC", 
    6,
    deployer
  ], {
    id: "mUSDC"
  });
  
  // Deploy Mock USDT (6 decimals)
  const mUSDT = m.contract("MockStablecoin", [
    "Mock USDT",
    "mUSDT",
    6,
    deployer
  ], {
    id: "mUSDT"
  });
  
  // Deploy Mock AID (18 decimals)
  const mAID = m.contract("MockStablecoin", [
    "Mock AID",
    "mAID",
    18,
    deployer
  ], {
    id: "mAID"
  });
  
  // Deploy Mock syUSD (18 decimals)
  const msyUSD = m.contract("MockStablecoin", [
    "Mock syUSD",
    "msyUSD",
    18,
    deployer
  ], {
    id: "msyUSD"
  });
  
  // Deploy Mock fastUSD (18 decimals)
  const mfastUSD = m.contract("MockStablecoin", [
    "Mock fastUSD",
    "mfastUSD",
    18,
    deployer
  ], {
    id: "mfastUSD"
  });
  
  // Return all deployed contracts
  return {
    mUSDC,
    mUSDT,
    mAID,
    msyUSD,
    mfastUSD
  };
});