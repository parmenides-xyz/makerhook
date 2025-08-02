// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockStablecoin
 * @dev Mock ERC20 token for testing the Elea AMM
 * Uses OpenZeppelin's ERC20 and Ownable for security
 */
contract MockStablecoin is ERC20, Ownable {
    uint8 private immutable _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsValue,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {
        _decimals = decimalsValue;
        // Mint initial supply to deployer
        _mint(msg.sender, 1_000_000 * 10**decimalsValue);
    }
    
    /**
     * @dev Returns the number of decimals used
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @dev Mint new tokens (only owner) - for controlled testing
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    /**
     * @dev Burns tokens from the caller
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
    
    /**
     * @dev Public faucet for testing - anyone can get tokens
     * Mints 10,000 tokens to the caller
     */
    function faucet() external {
        uint256 amount = 10_000 * 10**uint256(_decimals);
        _mint(msg.sender, amount);
    }
    
    /**
     * @dev Batch mint to multiple addresses (only owner)
     * @param recipients Array of addresses to mint to
     * @param amount Amount to mint to each address
     */
    function batchMint(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }
}