// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DAOTreasury
 * @dev Treasury contract focused on balance management and token distribution
 * @notice Only the owner (core DAO contract) can execute payments
 */
contract DAOTreasury is Ownable, ReentrancyGuard, ERC20 {
    // Token configuration
    uint256 private constant INITIAL_SUPPLY = 10000000000000000;

    // Spending tier limits (in tokens)
    uint256 public spenderLimit = 10000;

    // Events
    event TokensDistributed(address indexed beneficiary, uint256 amount);
    event TokensMinted(address indexed recipient, uint256 amount);
    event SpenderLimitUpdated(uint256 oldLimit, uint256 newLimit);

    // Custom errors
    error InsufficientTreasuryBalance();
    error InvalidBeneficiary();
    error AmountMustBeGreaterThanZero();
    error AmountExceedsSpendingLimit();

    constructor(address _owner) Ownable(_owner) ERC20("SoftLaw Token", "SLaw") {
        _mint(address(this), INITIAL_SUPPLY * 10 ** decimals());
    }

    /**
     * @dev Mint additional tokens (only owner)
     * @param amount Amount of tokens to mint
     */
    function printBrrrr(uint256 amount) public onlyOwner nonReentrant {
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        _mint(address(this), amount);
        emit TokensMinted(address(this), amount);
    }

    /**
     * @dev Distribute tokens from treasury to beneficiary
     * @param amount Amount of tokens to distribute
     * @param beneficiary Address to receive tokens
     */
    function spend(
        uint256 amount,
        address beneficiary
    ) public onlyOwner nonReentrant {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (amount > spenderLimit) revert AmountExceedsSpendingLimit();

        // Check treasury balance
        if (balanceOf(address(this)) < amount) {
            revert InsufficientTreasuryBalance();
        }

        // Use OpenZeppelin's _transfer function
        _transfer(address(this), beneficiary, amount);
        emit TokensDistributed(beneficiary, amount);
    }

    /**
     * @dev Update spending limit (only owner)
     * @param newLimit New spending limit
     */
    function updateSpenderLimit(uint256 newLimit) public onlyOwner {
        uint256 oldLimit = spenderLimit;
        spenderLimit = newLimit;
        emit SpenderLimitUpdated(oldLimit, newLimit);
    }

    /**
     * @dev Check if treasury has sufficient balance for a payment
     * @param amount Amount to check
     * @return hasBalance True if sufficient balance exists
     */
    function hasSufficientBalance(
        uint256 amount
    ) external view returns (bool hasBalance) {
        return balanceOf(address(this)) >= amount;
    }

    // View functions
    /**
     * @dev Get the current token balance of the treasury
     * @return balance The token balance of the treasury
     */
    function getTreasuryBalance() external view returns (uint256 balance) {
        return balanceOf(address(this));
    }

    /**
     * @dev Get the current token balance of any account
     * @param account Account address to check
     * @return balance The token balance
     */
    function getAccountBalance(
        address account
    ) external view returns (uint256 balance) {
        return balanceOf(account);
    }

    /**
     * @dev Get current spending limit
     * @return limit Current spending limit
     */
    function getSpenderLimit() external view returns (uint256 limit) {
        return spenderLimit;
    }

    /**
     * @dev Emergency withdraw function - only owner can withdraw all treasury funds
     * @param recipient Address to receive the funds
     */
    function emergencyWithdraw(
        address recipient
    ) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert InvalidBeneficiary();

        uint256 treasuryBalance = balanceOf(address(this));
        if (treasuryBalance > 0) {
            _transfer(address(this), recipient, treasuryBalance);
            emit TokensDistributed(recipient, treasuryBalance);
        }
    }

    /**
     * @dev Batch transfer function for multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts for each recipient
     */
    function batchSpend(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner nonReentrant {
        if (recipients.length != amounts.length) {
            revert("Recipients and amounts length mismatch");
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        if (totalAmount > spenderLimit) revert AmountExceedsSpendingLimit();
        if (balanceOf(address(this)) < totalAmount)
            revert InsufficientTreasuryBalance();

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidBeneficiary();
            if (amounts[i] == 0) revert AmountMustBeGreaterThanZero();

            _transfer(address(this), recipients[i], amounts[i]);
            emit TokensDistributed(recipients[i], amounts[i]);
        }
    }
}
