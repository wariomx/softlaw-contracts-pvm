// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SLAWToken.sol";

/**
 * @title OptimizedTreasuryCore
 * @dev PVM-optimized treasury management for Softlaw ecosystem
 * Replaces .send/.transfer with secure .call() pattern
 * Memory-efficient design for Polkadot Virtual Machine
 */
contract OptimizedTreasuryCore is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TREASURY_ADMIN = keccak256("TREASURY_ADMIN");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant DISPUTE_ROLE = keccak256("DISPUTE_ROLE");

    SLAWToken public immutable slawToken;

    // Treasury metrics
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;
    uint256 public totalFeesCollected;
    uint256 public totalDisputeEscrow;

    // Fee structure (basis points)
    uint256 public constant PLATFORM_FEE = 250; // 2.5%
    uint256 public constant DISPUTE_FEE = 100; // 1%
    uint256 public constant BASIS_POINTS = 10000;

    // Account tracking
    mapping(address => uint256) public accountBalances;
    mapping(address => uint256) public escrowBalances;
    mapping(uint256 => uint256) public disputeEscrow; // disputeId => amount
    mapping(address => bool) public authorizedOperators;

    // Events
    event DepositMade(address indexed user, uint256 amount, string purpose);
    event WithdrawalMade(address indexed user, uint256 amount, string purpose);
    event FeeCollected(address indexed from, uint256 amount, string feeType);
    event EscrowDeposited(
        uint256 indexed disputeId,
        address indexed depositor,
        uint256 amount
    );
    event EscrowReleased(
        uint256 indexed disputeId,
        address indexed recipient,
        uint256 amount
    );
    event ArbitratorFeePaid(
        address indexed arbitrator,
        uint256 indexed disputeId,
        uint256 amount
    );
    event AwardDistributed(
        address indexed winner,
        uint256 indexed disputeId,
        uint256 amount
    );
    event SecurePaymentProcessed(
        address indexed recipient,
        uint256 amount,
        bool success
    );
    event OperatorAuthorized(address indexed operator, bool authorized);

    constructor(address _admin, address payable _slawToken) {
        require(_slawToken != address(0), "Invalid SLAW token");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(TREASURY_ADMIN, _admin);

        slawToken = SLAWToken(_slawToken);
    }

    // ===== CORE TREASURY FUNCTIONS =====

    /**
     * @dev Deposit SLAW tokens to user account
     */
    function deposit(
        uint256 amount,
        string calldata purpose
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");

        // Transfer SLAW to treasury
        _safeTransferFrom(
            address(slawToken),
            msg.sender,
            address(this),
            amount
        );

        // Update balances
        accountBalances[msg.sender] += amount;
        totalDeposits += amount;

        emit DepositMade(msg.sender, amount, purpose);
    }

    /**
     * @dev Withdraw SLAW tokens from user account
     */
    function withdraw(
        uint256 amount,
        string calldata purpose
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(accountBalances[msg.sender] >= amount, "Insufficient balance");

        // Update balances
        accountBalances[msg.sender] -= amount;
        totalWithdrawals += amount;

        // Transfer SLAW back to user
        _safeTransfer(address(slawToken), msg.sender, amount);

        emit WithdrawalMade(msg.sender, amount, purpose);
    }

    // ===== LICENSE FEE MANAGEMENT =====

    /**
     * @dev Process license fee payment
     * @param licenseContract Address of license contract (for tracking)
     * @param payer Address paying the fee
     * @param licenseId License ID (for tracking)
     * @param amount Fee amount in SLAW
     */
    function payLicenseFee(
        address licenseContract,
        address payer,
        uint256 licenseId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(
            authorizedOperators[msg.sender] ||
                hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );

        // Transfer fee from payer
        _safeTransferFrom(address(slawToken), payer, address(this), amount);

        // Track fee collection
        totalFeesCollected += amount;

        emit FeeCollected(payer, amount, "LICENSE_FEE");
    }

    // ===== DISPUTE ESCROW MANAGEMENT =====

    /**
     * @dev Deposit funds into dispute escrow
     */
    function depositDisputeEscrow(
        uint256 disputeId,
        address depositor,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DISPUTE_ROLE) {
        require(amount > 0, "Amount must be > 0");

        // Transfer SLAW to escrow
        _safeTransferFrom(address(slawToken), depositor, address(this), amount);

        // Update escrow tracking
        disputeEscrow[disputeId] += amount;
        escrowBalances[depositor] += amount;
        totalDisputeEscrow += amount;

        emit EscrowDeposited(disputeId, depositor, amount);
    }

    /**
     * @dev Release escrow funds to recipient
     */
    function releaseEscrow(
        uint256 disputeId,
        address recipient,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DISPUTE_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(disputeEscrow[disputeId] >= amount, "Insufficient escrow");

        // Update escrow tracking
        disputeEscrow[disputeId] -= amount;
        totalDisputeEscrow -= amount;

        // Transfer funds to recipient
        _safeTransfer(address(slawToken), recipient, amount);

        emit EscrowReleased(disputeId, recipient, amount);
    }

    /**
     * @dev Pay arbitrator fee from dispute funds
     */
    function payArbitratorFee(
        address arbitrator,
        uint256 disputeId,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DISPUTE_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(disputeEscrow[disputeId] >= amount, "Insufficient funds");

        // Deduct from dispute escrow
        disputeEscrow[disputeId] -= amount;
        totalDisputeEscrow -= amount;

        // Pay arbitrator
        _safeTransfer(address(slawToken), arbitrator, amount);

        emit ArbitratorFeePaid(arbitrator, disputeId, amount);
    }

    /**
     * @dev Distribute dispute award to winner
     */
    function distributeAward(
        address winner,
        uint256 disputeId,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DISPUTE_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(disputeEscrow[disputeId] >= amount, "Insufficient funds");

        // Deduct from dispute escrow
        disputeEscrow[disputeId] -= amount;
        totalDisputeEscrow -= amount;

        // Award to winner
        _safeTransfer(address(slawToken), winner, amount);

        emit AwardDistributed(winner, disputeId, amount);
    }

    /**
     * @dev Refund remaining escrow to original depositor
     */
    function refundEscrow(
        address depositor,
        uint256 disputeId,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DISPUTE_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(disputeEscrow[disputeId] >= amount, "Insufficient funds");
        require(escrowBalances[depositor] >= amount, "Invalid refund amount");

        // Update balances
        disputeEscrow[disputeId] -= amount;
        escrowBalances[depositor] -= amount;
        totalDisputeEscrow -= amount;

        // Refund to depositor
        _safeTransfer(address(slawToken), depositor, amount);

        emit EscrowReleased(disputeId, depositor, amount);
    }

    // ===== SECURE TRANSFER FUNCTIONS (Replacement for .send/.transfer) =====

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );

        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Transfer failed"
        );
        emit SecurePaymentProcessed(to, amount, success);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                amount
            )
        );

        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferFrom failed"
        );
    }

    // Secure native token transfer (for ETH/native currency)
    function _safeTransferNative(address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool success, ) = to.call{value: amount}("");
        require(success, "Native transfer failed");
        emit SecurePaymentProcessed(to, amount, success);
    }

    // ===== REVENUE SHARING =====

    /**
     * @dev Distribute platform revenue to stakeholders
     */
    function distributeRevenue(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant onlyRole(TREASURY_ADMIN) {
        require(recipients.length == amounts.length, "Array length mismatch");
        require(recipients.length <= 50, "Too many recipients"); // PVM gas limit

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(
            totalAmount <= totalFeesCollected,
            "Insufficient fees collected"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                _safeTransfer(address(slawToken), recipients[i], amounts[i]);
                totalFeesCollected -= amounts[i];
            }
        }
    }

    // ===== VIEW FUNCTIONS =====

    function getTotalValue() external view returns (uint256) {
        return slawToken.balanceOf(address(this));
    }

    function getUserBalance(address user) external view returns (uint256) {
        return accountBalances[user];
    }

    function getDisputeEscrow(
        uint256 disputeId
    ) external view returns (uint256) {
        return disputeEscrow[disputeId];
    }

    function getTreasuryStats()
        external
        view
        returns (
            uint256 totalValue,
            uint256 deposits,
            uint256 withdrawals,
            uint256 feesCollected,
            uint256 escrowHeld
        )
    {
        return (
            slawToken.balanceOf(address(this)),
            totalDeposits,
            totalWithdrawals,
            totalFeesCollected,
            totalDisputeEscrow
        );
    }

    // ===== OPERATOR MANAGEMENT =====

    function authorizeOperator(
        address operator,
        bool authorized
    ) external onlyRole(TREASURY_ADMIN) {
        require(operator != address(0), "Invalid operator");
        authorizedOperators[operator] = authorized;
        emit OperatorAuthorized(operator, authorized);
    }

    function batchAuthorizeOperators(
        address[] calldata operators,
        bool[] calldata authorizations
    ) external onlyRole(TREASURY_ADMIN) {
        require(
            operators.length == authorizations.length,
            "Array length mismatch"
        );
        require(operators.length <= 20, "Too many operators"); // PVM limit

        for (uint256 i = 0; i < operators.length; i++) {
            if (operators[i] != address(0)) {
                authorizedOperators[operators[i]] = authorizations[i];
                emit OperatorAuthorized(operators[i], authorizations[i]);
            }
        }
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(TREASURY_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(TREASURY_ADMIN) {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal function (admin only)
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");

        if (token == address(0)) {
            // Native token withdrawal
            _safeTransferNative(to, amount);
        } else {
            // ERC20 token withdrawal
            _safeTransfer(token, to, amount);
        }
    }

    // ===== INTEGRATION HELPERS =====

    /**
     * @dev Batch process multiple payments (for marketplace settlements)
     */
    function batchProcessPayments(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata purposes
    ) external nonReentrant onlyRole(OPERATOR_ROLE) {
        require(recipients.length == amounts.length, "Array length mismatch");
        require(recipients.length == purposes.length, "Array length mismatch");
        require(recipients.length <= 20, "Too many payments"); // PVM gas limit

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0 && recipients[i] != address(0)) {
                _safeTransfer(address(slawToken), recipients[i], amounts[i]);
                emit SecurePaymentProcessed(recipients[i], amounts[i], true);
            }
        }
    }

    // ===== RECEIVE FUNCTION =====

    receive() external payable {
        // Allow contract to receive native tokens for cross-chain operations
    }
}
