// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SLAWToken
 * @dev Lightweight SLAW token optimized for PVM/Revive
 * Features:
 * - Core ERC20 functionality
 * - Role-based minting
 * - Integration with treasury system
 * - PVM-optimized (no .send/.transfer, withdrawal pattern)
 */
contract SLAWToken is ERC20, AccessControl, ReentrancyGuard, Pausable {
    // Roles for modular architecture
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // Token economics
    uint256 private constant INITIAL_SUPPLY = 10_000_000_000 * 10 ** 18; // 10B SLAW
    uint256 public constant MAX_SUPPLY = 50_000_000_000 * 10 ** 18; // 50B SLAW max

    // Treasury integration
    address public treasuryCore;

    // Withdrawal pattern for PVM compatibility (no .send/.transfer)
    mapping(address => uint256) public pendingWithdrawals;

    // Events
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    event WithdrawalScheduled(address indexed user, uint256 amount);
    event WithdrawalProcessed(address indexed user, uint256 amount);
    event TokensMinted(address indexed to, uint256 amount, string reason);
    event TokensBurned(address indexed from, uint256 amount, string reason);

    constructor(
        address _admin,
        address _treasuryCore
    ) ERC20("SoftLaw Token", "SLAW") {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);

        treasuryCore = _treasuryCore;

        // Mint initial supply to treasury
        _mint(_treasuryCore, INITIAL_SUPPLY);

        emit TokensMinted(_treasuryCore, INITIAL_SUPPLY, "INITIAL_SUPPLY");
    }

    // ===== MINTING FUNCTIONS =====

    /**
     * @dev Mint tokens with supply cap protection
     * @param to Recipient address
     * @param amount Amount to mint
     * @param reason Reason for minting (for transparency)
     */
    function mint(
        address to,
        uint256 amount,
        string calldata reason
    ) external onlyRole(MINTER_ROLE) whenNotPaused {
        require(to != address(0), "Cannot mint to zero address");
        require(amount > 0, "Amount must be > 0");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");

        _mint(to, amount);
        emit TokensMinted(to, amount, reason);
    }

    /**
     * @dev Batch mint for efficiency
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts for each recipient
     * @param reason Reason for batch minting
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string calldata reason
    ) external onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(recipients.length <= 100, "Too many recipients"); // PVM memory limit protection

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Invalid amount");
            totalAmount += amounts[i];
        }

        require(
            totalSupply() + totalAmount <= MAX_SUPPLY,
            "Exceeds max supply"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }

        emit TokensMinted(address(0), totalAmount, reason);
    }

    // ===== BURNING FUNCTIONS =====

    /**
     * @dev Burn tokens with reason tracking
     * @param amount Amount to burn
     * @param reason Reason for burning
     */
    function burn(
        uint256 amount,
        string calldata reason
    ) external whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount, reason);
    }

    /**
     * @dev Burn tokens from another account (with allowance)
     * @param from Account to burn from
     * @param amount Amount to burn
     * @param reason Reason for burning
     */
    function burnFrom(
        address from,
        uint256 amount,
        string calldata reason
    ) external onlyRole(BURNER_ROLE) whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(from) >= amount, "Insufficient balance");

        _burn(from, amount);
        emit TokensBurned(from, amount, reason);
    }

    // ===== WITHDRAWAL PATTERN (PVM SAFE) =====

    /**
     * @dev Schedule withdrawal (instead of direct transfer)
     * @param user User to schedule withdrawal for
     * @param amount Amount to withdraw
     */
    function scheduleWithdrawal(
        address user,
        uint256 amount
    ) external onlyRole(TREASURY_ROLE) whenNotPaused {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be > 0");
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        pendingWithdrawals[user] += amount;
        emit WithdrawalScheduled(user, amount);
    }

    /**
     * @dev Process scheduled withdrawal (user pulls funds)
     */
    function processWithdrawal() external nonReentrant whenNotPaused {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No pending withdrawal");
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        pendingWithdrawals[msg.sender] = 0;

        // Use safe transfer method (not .send/.transfer)
        bool success = transfer(msg.sender, amount);
        require(success, "Transfer failed");

        emit WithdrawalProcessed(msg.sender, amount);
    }

    /**
     * @dev Batch process withdrawals for gas efficiency
     * @param users Array of users to process withdrawals for
     */
    function batchProcessWithdrawals(
        address[] calldata users
    ) external onlyRole(TREASURY_ROLE) nonReentrant whenNotPaused {
        require(users.length <= 50, "Too many users"); // PVM memory limit protection

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 amount = pendingWithdrawals[user];

            if (amount > 0 && balanceOf(address(this)) >= amount) {
                pendingWithdrawals[user] = 0;

                bool success = transfer(user, amount);
                if (success) {
                    emit WithdrawalProcessed(user, amount);
                }
            }
        }
    }

    // ===== TREASURY INTEGRATION =====

    /**
     * @dev Transfer tokens to treasury contracts (direct integration)
     * @param to Treasury contract address
     * @param amount Amount to transfer
     */
    function treasuryTransfer(
        address to,
        uint256 amount
    ) external onlyRole(TREASURY_ROLE) whenNotPaused returns (bool) {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Amount must be > 0");

        return transfer(to, amount);
    }

    /**
     * @dev Transfer tokens from treasury contracts
     * @param from Treasury contract address
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function treasuryTransferFrom(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(TREASURY_ROLE) whenNotPaused returns (bool) {
        require(from != address(0) && to != address(0), "Invalid addresses");
        require(amount > 0, "Amount must be > 0");

        return transferFrom(from, to, amount);
    }

    // ===== VIEW FUNCTIONS =====

    function getPendingWithdrawal(
        address user
    ) external view returns (uint256) {
        return pendingWithdrawals[user];
    }

    function getCirculatingSupply() external view returns (uint256) {
        return
            totalSupply() - balanceOf(address(this)) - balanceOf(treasuryCore);
    }

    function getTreasuryBalance() external view returns (uint256) {
        return balanceOf(treasuryCore);
    }

    function getContractBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }

    // ===== ADMIN FUNCTIONS =====

    function updateTreasuryCore(
        address newTreasuryCore
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasuryCore != address(0), "Invalid treasury address");

        address oldTreasury = treasuryCore;
        treasuryCore = newTreasuryCore;

        // Update treasury role
        _revokeRole(TREASURY_ROLE, oldTreasury);
        _grantRole(TREASURY_ROLE, newTreasuryCore);

        emit TreasuryUpdated(oldTreasury, newTreasuryCore);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ===== OVERRIDES =====

    function transfer(
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
