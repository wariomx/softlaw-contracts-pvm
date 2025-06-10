// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../IP-liquidity/SLAWToken.sol";

/**
 * @title TreasuryCore
 * @dev Core treasury functionality optimized for PVM
 * Features:
 * - Fee collection and distribution
 * - Payment processing for registrations/licenses
 * - Integration with other treasury modules
 * - PVM-safe withdrawal patterns
 */
contract TreasuryCore is AccessControl, ReentrancyGuard, Pausable {
    // Roles for modular integration
    bytes32 public constant TREASURY_ADMIN = keccak256("TREASURY_ADMIN");
    bytes32 public constant REGISTRY_CONTRACT = keccak256("REGISTRY_CONTRACT");
    bytes32 public constant LICENSING_CONTRACT =
        keccak256("LICENSING_CONTRACT");
    bytes32 public constant MARKETPLACE_CONTRACT =
        keccak256("MARKETPLACE_CONTRACT");

    // Core contracts
    SLAWToken public immutable slawToken;

    // System addresses
    address public feeCollector;
    address public wrappedIPManager;
    address public liquidityManager;
    address public rewardDistributor;

    // Fee structure
    struct FeeConfig {
        uint256 registrationFee;
        uint256 licensingBaseFee;
        uint256 marketplaceFeeRate; // basis points (100 = 1%)
        uint256 liquidityFeeRate; // basis points
        bool isActive;
    }

    FeeConfig public feeConfig;

    // System metrics
    uint256 public totalFeesCollected;
    uint256 public totalRegistrations;
    uint256 public totalLicenses;

    // Withdrawal tracking for PVM safety
    mapping(address => uint256) public pendingPayouts;
    mapping(address => uint256) public totalEarnings;

    // Events
    event FeeConfigUpdated(
        uint256 registrationFee,
        uint256 licensingBaseFee,
        uint256 marketplaceFeeRate,
        uint256 liquidityFeeRate
    );

    event SystemAddressUpdated(
        string indexed component,
        address indexed oldAddress,
        address indexed newAddress
    );

    event RegistrationPayment(
        address indexed user,
        uint256 indexed nftId,
        uint256 feeAmount,
        uint256 timestamp
    );

    event LicensePayment(
        address indexed licensor,
        address indexed licensee,
        uint256 indexed licenseId,
        uint256 totalAmount,
        uint256 licensorShare,
        uint256 protocolShare
    );

    event PayoutScheduled(
        address indexed recipient,
        uint256 amount,
        string reason
    );
    event PayoutProcessed(address indexed recipient, uint256 amount);

    event FeesCollected(address indexed from, uint256 amount, string feeType);

    constructor(address _admin, address _slawToken, address _feeCollector) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_feeCollector != address(0), "Invalid fee collector");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(TREASURY_ADMIN, _admin);

        slawToken = SLAWToken(_slawToken);
        feeCollector = _feeCollector;

        // Initialize default fees (100 SLAW registration, 50 SLAW base licensing)
        feeConfig = FeeConfig({
            registrationFee: 100 * 10 ** 18,
            licensingBaseFee: 50 * 10 ** 18,
            marketplaceFeeRate: 250, // 2.5%
            liquidityFeeRate: 30, // 0.3%
            isActive: true
        });

        emit FeeConfigUpdated(
            feeConfig.registrationFee,
            feeConfig.licensingBaseFee,
            feeConfig.marketplaceFeeRate,
            feeConfig.liquidityFeeRate
        );
    }

    // ===== PAYMENT PROCESSING =====

    /**
     * @dev Process registration payment (called by registry contracts)
     * @param user User paying for registration
     * @param nftId NFT ID being registered
     */
    function processRegistrationPayment(
        address user,
        uint256 nftId
    ) external onlyRole(REGISTRY_CONTRACT) nonReentrant whenNotPaused {
        require(feeConfig.isActive, "Fees not active");
        require(user != address(0), "Invalid user");

        uint256 feeAmount = feeConfig.registrationFee;
        require(
            slawToken.balanceOf(user) >= feeAmount,
            "Insufficient SLAW balance"
        );

        // Transfer fee to treasury
        bool success = slawToken.treasuryTransferFrom(
            user,
            address(this),
            feeAmount
        );
        require(success, "Fee transfer failed");

        // Transfer to fee collector
        success = slawToken.treasuryTransfer(feeCollector, feeAmount);
        require(success, "Fee collection failed");

        totalFeesCollected += feeAmount;
        totalRegistrations++;

        emit RegistrationPayment(user, nftId, feeAmount, block.timestamp);
        emit FeesCollected(user, feeAmount, "REGISTRATION");
    }

    /**
     * @dev Process license payment with revenue sharing
     * @param licensor License creator (receives 70%)
     * @param licensee License buyer (pays fee)
     * @param licenseId License ID
     * @param customAmount Additional license-specific amount
     */
    function processLicensePayment(
        address licensor,
        address licensee,
        uint256 licenseId,
        uint256 customAmount
    ) external onlyRole(LICENSING_CONTRACT) nonReentrant whenNotPaused {
        require(feeConfig.isActive, "Fees not active");
        require(
            licensor != address(0) && licensee != address(0),
            "Invalid addresses"
        );

        uint256 totalFee = feeConfig.licensingBaseFee + customAmount;
        require(
            slawToken.balanceOf(licensee) >= totalFee,
            "Insufficient SLAW balance"
        );

        // Calculate shares: 70% to licensor, 30% to protocol
        uint256 licensorShare = (totalFee * 70) / 100;
        uint256 protocolShare = totalFee - licensorShare;

        // Transfer from licensee to treasury
        bool success = slawToken.treasuryTransferFrom(
            licensee,
            address(this),
            totalFee
        );
        require(success, "Payment transfer failed");

        // Schedule payout to licensor (withdrawal pattern)
        _schedulePayout(licensor, licensorShare, "LICENSE_ROYALTY");

        // Transfer protocol share to fee collector
        success = slawToken.treasuryTransfer(feeCollector, protocolShare);
        require(success, "Protocol fee transfer failed");

        totalFeesCollected += protocolShare;
        totalEarnings[licensor] += licensorShare;
        totalLicenses++;

        emit LicensePayment(
            licensor,
            licensee,
            licenseId,
            totalFee,
            licensorShare,
            protocolShare
        );
        emit FeesCollected(licensee, totalFee, "LICENSE");
    }

    /**
     * @dev Process marketplace transaction fees
     * @param seller Seller receiving payment
     * @param buyer Buyer making payment
     * @param saleAmount Total sale amount
     * @param itemId Item being sold
     */
    function processMarketplaceFee(
        address seller,
        address buyer,
        uint256 saleAmount,
        uint256 itemId
    )
        external
        onlyRole(MARKETPLACE_CONTRACT)
        nonReentrant
        whenNotPaused
        returns (uint256 netAmount)
    {
        require(feeConfig.isActive, "Fees not active");
        require(
            seller != address(0) && buyer != address(0),
            "Invalid addresses"
        );
        require(saleAmount > 0, "Invalid sale amount");

        // Calculate marketplace fee
        uint256 marketplaceFee = (saleAmount * feeConfig.marketplaceFeeRate) /
            10000;
        netAmount = saleAmount - marketplaceFee;

        require(
            slawToken.balanceOf(buyer) >= saleAmount,
            "Insufficient buyer balance"
        );

        // Transfer total amount from buyer to treasury
        bool success = slawToken.treasuryTransferFrom(
            buyer,
            address(this),
            saleAmount
        );
        require(success, "Sale payment failed");

        // Schedule payout to seller (net amount)
        _schedulePayout(seller, netAmount, "MARKETPLACE_SALE");

        // Transfer marketplace fee to fee collector
        success = slawToken.treasuryTransfer(feeCollector, marketplaceFee);
        require(success, "Marketplace fee transfer failed");

        totalFeesCollected += marketplaceFee;
        totalEarnings[seller] += netAmount;

        emit FeesCollected(buyer, marketplaceFee, "MARKETPLACE");
    }

    // ===== WITHDRAWAL PATTERN (PVM SAFE) =====

    /**
     * @dev Schedule payout for recipient (withdrawal pattern)
     * @param recipient Address to receive payout
     * @param amount Amount to pay out
     * @param reason Reason for payout
     */
    function _schedulePayout(
        address recipient,
        uint256 amount,
        string memory reason
    ) internal {
        pendingPayouts[recipient] += amount;
        emit PayoutScheduled(recipient, amount, reason);
    }

    /**
     * @dev User claims their pending payouts
     */
    function claimPayout() external nonReentrant whenNotPaused {
        uint256 amount = pendingPayouts[msg.sender];
        require(amount > 0, "No pending payout");
        require(
            slawToken.balanceOf(address(this)) >= amount,
            "Insufficient treasury balance"
        );

        pendingPayouts[msg.sender] = 0;

        bool success = slawToken.treasuryTransfer(msg.sender, amount);
        require(success, "Payout transfer failed");

        emit PayoutProcessed(msg.sender, amount);
    }

    /**
     * @dev Admin can process payouts for users (gas optimization)
     * @param recipients Array of recipients to process payouts for
     */
    function batchProcessPayouts(
        address[] calldata recipients
    ) external onlyRole(TREASURY_ADMIN) nonReentrant whenNotPaused {
        require(recipients.length <= 50, "Too many recipients"); // PVM memory limit

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 amount = pendingPayouts[recipient];

            if (amount > 0 && slawToken.balanceOf(address(this)) >= amount) {
                pendingPayouts[recipient] = 0;

                bool success = slawToken.treasuryTransfer(recipient, amount);
                if (success) {
                    emit PayoutProcessed(recipient, amount);
                }
            }
        }
    }

    // ===== SYSTEM INTEGRATION =====

    /**
     * @dev Update system component addresses
     * @param component Component name
     * @param newAddress New address for component
     */
    function updateSystemAddress(
        string calldata component,
        address newAddress
    ) external onlyRole(TREASURY_ADMIN) {
        require(newAddress != address(0), "Invalid address");

        bytes32 componentHash = keccak256(abi.encodePacked(component));
        address oldAddress;

        if (componentHash == keccak256("feeCollector")) {
            oldAddress = feeCollector;
            feeCollector = newAddress;
        } else if (componentHash == keccak256("wrappedIPManager")) {
            oldAddress = wrappedIPManager;
            wrappedIPManager = newAddress;
        } else if (componentHash == keccak256("liquidityManager")) {
            oldAddress = liquidityManager;
            liquidityManager = newAddress;
        } else if (componentHash == keccak256("rewardDistributor")) {
            oldAddress = rewardDistributor;
            rewardDistributor = newAddress;
        } else {
            revert("Unknown component");
        }

        emit SystemAddressUpdated(component, oldAddress, newAddress);
    }

    /**
     * @dev Update fee configuration
     * @param _registrationFee New registration fee
     * @param _licensingBaseFee New base licensing fee
     * @param _marketplaceFeeRate New marketplace fee rate (basis points)
     * @param _liquidityFeeRate New liquidity fee rate (basis points)
     */
    function updateFeeConfig(
        uint256 _registrationFee,
        uint256 _licensingBaseFee,
        uint256 _marketplaceFeeRate,
        uint256 _liquidityFeeRate
    ) external onlyRole(TREASURY_ADMIN) {
        require(_marketplaceFeeRate <= 1000, "Marketplace fee too high"); // Max 10%
        require(_liquidityFeeRate <= 100, "Liquidity fee too high"); // Max 1%

        feeConfig.registrationFee = _registrationFee;
        feeConfig.licensingBaseFee = _licensingBaseFee;
        feeConfig.marketplaceFeeRate = _marketplaceFeeRate;
        feeConfig.liquidityFeeRate = _liquidityFeeRate;

        emit FeeConfigUpdated(
            _registrationFee,
            _licensingBaseFee,
            _marketplaceFeeRate,
            _liquidityFeeRate
        );
    }

    // ===== VIEW FUNCTIONS =====

    function getPendingPayout(address user) external view returns (uint256) {
        return pendingPayouts[user];
    }

    function getTotalEarnings(address user) external view returns (uint256) {
        return totalEarnings[user];
    }

    function getFeeConfig() external view returns (FeeConfig memory) {
        return feeConfig;
    }

    function getSystemMetrics()
        external
        view
        returns (
            uint256 feesCollected,
            uint256 registrations,
            uint256 licenses,
            uint256 treasuryBalance
        )
    {
        return (
            totalFeesCollected,
            totalRegistrations,
            totalLicenses,
            slawToken.balanceOf(address(this))
        );
    }

    function getSystemAddresses()
        external
        view
        returns (
            address _slawToken,
            address _feeCollector,
            address _wrappedIPManager,
            address _liquidityManager,
            address _rewardDistributor
        )
    {
        return (
            address(slawToken),
            feeCollector,
            wrappedIPManager,
            liquidityManager,
            rewardDistributor
        );
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(TREASURY_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(TREASURY_ADMIN) {
        _unpause();
    }

    function toggleFees(bool active) external onlyRole(TREASURY_ADMIN) {
        feeConfig.isActive = active;
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param amount Amount to recover
     */
    function emergencyWithdraw(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Invalid amount");
        require(
            slawToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        bool success = slawToken.treasuryTransfer(feeCollector, amount);
        require(success, "Emergency withdrawal failed");
    }
}
