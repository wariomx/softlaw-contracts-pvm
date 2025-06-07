// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import "../Registries/RCopyright.sol";
import "../interfaces/ISoftlawTreasury.sol";

/**
 * @title CopyrightLicensing - Enhanced with Treasury Integration
 * @dev Advanced copyright licensing system integrated with Softlaw Treasury
 * Features:
 * - SLAW token payments for all transactions
 * - Automatic wrapped IP token creation
 * - Liquidity pool incentives for licensors
 * - Revenue sharing with Treasury
 * - Integration with IP tokenization system
 */
contract CopyrightLicensing is CopyrightsRegistry, ERC2981 {
    
    // Treasury integration
    ISoftlawTreasury public immutable treasury;
    
    // Enhanced fee structure (in SLAW tokens)
    uint256 public constant LICENSE_CREATION_FEE = 25 * 10**18; // 25 SLAW
    uint256 public constant LICENSE_ACCEPTANCE_FEE = 10 * 10**18; // 10 SLAW
    uint256 public constant TOKENIZATION_INCENTIVE = 100 * 10**18; // 100 SLAW reward

    // Wrapped token tracking
    mapping(uint256 => address) public copyrightWrappedTokens; // copyright ID => wrapped token
    mapping(uint256 => bool) public isTokenized; // copyright ID => tokenized status
    mapping(uint256 => uint256) public tokenizationRewards; // copyright ID => rewards earned

    // Enhanced license structure
    struct EnhancedLicense {
        uint256 ipId;
        address licensor;
        address licensee;
        LicenseType licenseType;
        LicenseStatus status;
        uint256 feeInSLAW; // Fee in SLAW tokens
        uint256 duration;
        uint256 startTime;
        uint256 endTime;
        string terms;
        EconomicRights grantedRights;
        bool exclusive;
        string territory;
        uint256 royaltyPercentage;
        bool autoTokenization; // Automatic wrapped token creation
        uint256 liquidityIncentive; // SLAW bonus for creating liquidity
    }

    // Enhanced mappings
    mapping(uint256 => EnhancedLicense) public enhancedLicenses;
    mapping(uint256 => uint256[]) public copyrightEnhancedLicenses;
    
    uint256 public enhancedLicenseCounter = 1;

    // New events for Treasury integration
    event TreasuryIntegrationEnabled(address indexed treasury);
    event LicenseCreatedWithSLAW(uint256 indexed licenseId, uint256 feeInSLAW);
    event AutoTokenizationTriggered(uint256 indexed copyrightId, address wrappedToken);
    event LiquidityIncentivePaid(address indexed licensor, uint256 amount);
    event RevenueSharedWithTreasury(uint256 licenseId, uint256 amount);

    constructor(
        address _feeRecipient,
        address _treasury
    ) CopyrightsRegistry(_feeRecipient) {
        treasury = ISoftlawTreasury(_treasury);
        emit TreasuryIntegrationEnabled(_treasury);
    }

    /**
     * @dev Enhanced license offering with Treasury integration
     * @param ipId Copyright token ID
     * @param licensee Address to offer license to
     * @param licenseType Type of license
     * @param feeInSLAW License fee in SLAW tokens
     * @param duration Duration in seconds
     * @param terms License terms
     * @param grantedRights Rights being licensed
     * @param exclusive Whether exclusive license
     * @param territory Geographical limitations
     * @param autoTokenization Whether to auto-create wrapped tokens
     */
    function offerEnhancedLicense(
        uint256 ipId,
        address licensee,
        LicenseType licenseType,
        uint256 feeInSLAW,
        uint256 duration,
        string memory terms,
        EconomicRights memory grantedRights,
        bool exclusive,
        string memory territory,
        bool autoTokenization
    ) external payable nonReentrant whenNotPaused validTokenId(ipId) returns (uint256) {
        require(licensee != address(0), "Invalid licensee");
        require(licensee != msg.sender, "Cannot license to yourself");
        require(copyrights[ipId].economicRightsOwner == msg.sender, "Not economic rights owner");
        require(feeInSLAW > 0, "Fee must be > 0");
        
        // Pay license creation fee in SLAW
        treasury.payLicenseFee(
            address(0), // No specific licensor yet
            msg.sender,
            0, // Temporary license ID
            LICENSE_CREATION_FEE
        );

        // Validate granted rights
        _validateGrantedRights(ipId, grantedRights);

        uint256 licenseId = enhancedLicenseCounter++;
        
        // Calculate liquidity incentive (10% of license fee)
        uint256 liquidityBonus = (feeInSLAW * 10) / 100;

        enhancedLicenses[licenseId] = EnhancedLicense({
            ipId: ipId,
            licensor: msg.sender,
            licensee: licensee,
            licenseType: licenseType,
            status: LicenseStatus.OFFERED,
            feeInSLAW: feeInSLAW,
            duration: duration,
            startTime: 0,
            endTime: 0,
            terms: terms,
            grantedRights: grantedRights,
            exclusive: exclusive,
            territory: territory,
            royaltyPercentage: 100,
            autoTokenization: autoTokenization,
            liquidityIncentive: liquidityBonus
        });

        copyrightEnhancedLicenses[ipId].push(licenseId);

        emit LicenseCreatedWithSLAW(licenseId, feeInSLAW);

        return licenseId;
    }

    /**
     * @dev Accept enhanced license with SLAW payment
     * @param licenseId License ID to accept
     */
    function acceptEnhancedLicense(
        uint256 licenseId
    ) external nonReentrant whenNotPaused {
        EnhancedLicense storage license = enhancedLicenses[licenseId];
        require(license.licensee == msg.sender, "Not the licensee");
        require(license.status == LicenseStatus.OFFERED, "License not offered");

        // Calculate total payment (license fee + acceptance fee)
        uint256 totalPayment = license.feeInSLAW + LICENSE_ACCEPTANCE_FEE;

        // Process SLAW payment through Treasury
        treasury.payLicenseFee(
            license.licensor,
            msg.sender,
            licenseId,
            totalPayment
        );

        // Update license
        license.status = LicenseStatus.ACCEPTED;
        license.startTime = block.timestamp;
        if (license.duration > 0) {
            license.endTime = block.timestamp + license.duration;
        }

        // Auto-tokenization if enabled
        if (license.autoTokenization && !isTokenized[license.ipId]) {
            _triggerAutoTokenization(license.ipId, license.licensor);
        }

        // Pay liquidity incentive to licensor
        if (license.liquidityIncentive > 0) {
            treasury.distributeIncentives(
                _asSingletonArray(license.licensor),
                _asSingletonArray(license.liquidityIncentive)
            );
            emit LiquidityIncentivePaid(license.licensor, license.liquidityIncentive);
        }

        emit LicenseAccepted(licenseId, license.ipId, license.licensor);
    }

    /**
     * @dev Manually tokenize copyright into wrapped tokens
     * @param copyrightId Copyright ID to tokenize
     * @param totalSupply Total supply of wrapped tokens
     * @param pricePerToken Price per token in SLAW
     * @param metadata Metadata for wrapped token
     */
    function tokenizeCopyright(
        uint256 copyrightId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string memory metadata
    ) external validTokenId(copyrightId) returns (address) {
        require(copyrights[copyrightId].economicRightsOwner == msg.sender, "Not owner");
        require(!isTokenized[copyrightId], "Already tokenized");
        require(totalSupply > 0, "Invalid supply");

        // Approve treasury to handle the NFT
        approve(address(treasury), copyrightId);

        // Create wrapped token through Treasury
        address wrappedToken = treasury.wrapCopyrightNFT(
            address(this), // This contract holds the copyright NFTs
            copyrightId,
            totalSupply,
            pricePerToken,
            metadata
        );

        // Update tracking
        copyrightWrappedTokens[copyrightId] = wrappedToken;
        isTokenized[copyrightId] = true;

        // Pay tokenization reward
        treasury.distributeIncentives(
            _asSingletonArray(msg.sender),
            _asSingletonArray(TOKENIZATION_INCENTIVE)
        );

        tokenizationRewards[copyrightId] = TOKENIZATION_INCENTIVE;

        emit AutoTokenizationTriggered(copyrightId, wrappedToken);

        return wrappedToken;
    }

    /**
     * @dev Create liquidity pool for tokenized copyright
     * @param copyrightId Copyright ID (must be tokenized)
     * @param ipTokenAmount Amount of IP tokens for liquidity
     * @param slawAmount Amount of SLAW tokens for liquidity
     */
    function createCopyrightLiquidityPool(
        uint256 copyrightId,
        uint256 ipTokenAmount,
        uint256 slawAmount
    ) external validTokenId(copyrightId) returns (address) {
        require(isTokenized[copyrightId], "Copyright not tokenized");
        require(copyrights[copyrightId].economicRightsOwner == msg.sender, "Not owner");

        address wrappedToken = copyrightWrappedTokens[copyrightId];
        
        // Create liquidity pool through Treasury
        address pairAddress = treasury.createLiquidityPool(
            wrappedToken,
            ipTokenAmount,
            slawAmount
        );

        // Additional liquidity incentive (50 SLAW)
        treasury.distributeIncentives(
            _asSingletonArray(msg.sender),
            _asSingletonArray(50 * 10**18)
        );

        return pairAddress;
    }

    /**
     * @dev Get comprehensive copyright info including tokenization status
     * @param copyrightId Copyright ID
     */
    function getCopyrightInfo(uint256 copyrightId) external view validTokenId(copyrightId) returns (
        Copyright memory copyright,
        bool tokenized,
        address wrappedToken,
        uint256 rewards,
        uint256[] memory licenseIds
    ) {
        return (
            copyrights[copyrightId],
            isTokenized[copyrightId],
            copyrightWrappedTokens[copyrightId],
            tokenizationRewards[copyrightId],
            copyrightEnhancedLicenses[copyrightId]
        );
    }

    /**
     * @dev Get enhanced license details
     * @param licenseId License ID
     */
    function getEnhancedLicense(uint256 licenseId) external view returns (EnhancedLicense memory) {
        return enhancedLicenses[licenseId];
    }

    /**
     * @dev Check if user can afford license fees
     * @param user User address
     * @param licenseId License ID
     */
    function canAffordLicense(address user, uint256 licenseId) external view returns (bool) {
        EnhancedLicense memory license = enhancedLicenses[licenseId];
        uint256 totalCost = license.feeInSLAW + LICENSE_ACCEPTANCE_FEE;
        return treasury.balanceOf(user) >= totalCost;
    }

    // ===== INTERNAL FUNCTIONS =====

    /**
     * @dev Trigger automatic tokenization for popular copyrights
     */
    function _triggerAutoTokenization(uint256 copyrightId, address owner) internal {
        if (isTokenized[copyrightId]) return;

        // Auto-create wrapped tokens with standard parameters
        uint256 defaultSupply = 1000 * 10**18; // 1000 tokens
        uint256 defaultPrice = 5 * 10**18;     // 5 SLAW per token

        try treasury.wrapCopyrightNFT(
            address(this),
            copyrightId,
            defaultSupply,
            defaultPrice,
            string(abi.encodePacked("Auto-wrapped Copyright #", copyrightId))
        ) returns (address wrappedToken) {
            copyrightWrappedTokens[copyrightId] = wrappedToken;
            isTokenized[copyrightId] = true;
            
            emit AutoTokenizationTriggered(copyrightId, wrappedToken);
        } catch {
            // Auto-tokenization failed, continue without it
        }
    }

    /**
     * @dev Helper function to create single-element arrays
     */
    function _asSingletonArray(address element) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;
        return array;
    }

    function _asSingletonArray(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;
        return array;
    }

    /**
     * @dev Override to support ERC2981 + Treasury integration
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ===== ADMIN FUNCTIONS =====

    /**
     * @dev Update Treasury address (admin only)
     */
    function updateTreasuryIntegration(address newTreasury) external onlyOwner {
        // Note: Treasury is immutable for security, this would require contract upgrade
        revert("Treasury address is immutable");
    }

    /**
     * @dev Emergency function to disable auto-tokenization
     */
    function emergencyDisableAutoTokenization(uint256 copyrightId) external onlyOwner {
        // This could be implemented if needed for emergency situations
        emit AutoTokenizationTriggered(copyrightId, address(0));
    }
}
