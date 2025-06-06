// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import "../Registries/RCopyright.sol";

/**
 * @title CopyrightLicensing
 * @dev Contract for licensing copyrighted works
 * Implements licensing under international copyright law
 */
contract CopyrightLicensing is CopyrightsRegistry, ERC2981 {
    uint256 public constant LICENSE_FEE = 0.5 ether;

    address public governanceContract;

    // License-specific data
    struct LicenseData {
        uint256 licenseId;
        uint256 licenseAmount;
        bool exists;
    }

    // Mapping for licensing proposal data
    mapping(uint256 => LicenseData) private _licenseData;

    // License types
    enum LicenseType {
        COMMERCIAL,
        NON_COMMERCIAL,
        EDUCATIONAL,
        UNLIMITED
    }
    enum LicenseStatus {
        OFFERED,
        ACCEPTED,
        REVOKED,
        EXPIRED,
        CANCELLED
    }

    struct License {
        uint256 ipId;
        address licensor;
        address licensee;
        LicenseType licenseType;
        LicenseStatus status;
        uint256 fee;
        uint256 duration; // in seconds, 0 = unlimited
        uint256 startTime;
        uint256 endTime;
        string terms;
        EconomicRights grantedRights;
        bool exclusive; // exclusive or non-exclusive license
        string territory; // geographical limitations
        uint256 royaltyPercentage; // basis points (100 = 1%)
    }

    // License storage
    mapping(uint256 => License) public licenses;
    mapping(uint256 => uint256[]) public copyrightLicenses; // copyright ID => license IDs
    mapping(uint256 => mapping(address => uint256[])) public licenseeOffers; // copyright ID => licensee => license IDs

    uint256 public licenseCounter = 1;

    // Events
    event LicenseOffered(
        uint256 indexed licenseId,
        uint256 indexed ipId,
        address indexed licensor,
        address licensee,
        LicenseType licenseType,
        uint256 fee,
        uint256 duration
    );

    event LicenseAccepted(
        uint256 indexed licenseId,
        uint256 indexed ipId,
        address indexed licensor
        //        address indexed licensee
    );

    event LicenseRevoked(uint256 indexed licenseId, address indexed licensor);
    event LicenseExpired(uint256 indexed licenseId);
    event LicenseCancelled(
        uint256 indexed licenseId,
        address indexed canceller
    );

    event LicenseProposalRegistered(
        uint256 indexed id,
        uint256 licenseId,
        uint256 licenseAmount
    );
    event LicenseProposalExecuted(
        uint256 indexed id,
        uint256 licenseId,
        uint256 amount
    );

    constructor(address _feeRecipient) CopyrightsRegistry(_feeRecipient) {}

    modifier validLicense(uint256 licenseId) {
        require(
            licenseId > 0 && licenseId < licenseCounter,
            "Invalid license ID"
        );
        _;
    }

    modifier onlyLicensor(uint256 licenseId) {
        require(licenses[licenseId].licensor == msg.sender, "Not the licensor");
        _;
    }

    modifier onlyLicensee(uint256 licenseId) {
        require(licenses[licenseId].licensee == msg.sender, "Not the licensee");
        _;
    }

    /**
     * @dev Offer a license for a copyrighted work
     * @param ipId Copyright token ID
     * @param licensee Address to offer license to
     * @param licenseType Type of license (commercial, non-commercial, etc.)
     * @param fee License fee in wei
     * @param duration Duration in seconds (0 = unlimited)
     * @param terms License terms and conditions
     * @param grantedRights Rights being licensed
     * @param exclusive Whether this is an exclusive license
     * @param territory Geographical limitations
     */
    function offerLicense(
        uint256 ipId,
        address licensee,
        LicenseType licenseType,
        uint256 fee,
        uint256 duration,
        string memory terms,
        EconomicRights memory grantedRights,
        bool exclusive,
        string memory territory
    ) external payable nonReentrant whenNotPaused validTokenId(ipId) {
        require(msg.value >= LICENSE_FEE, "Insufficient license fee");
        require(licensee != address(0), "Invalid licensee");
        require(licensee != msg.sender, "Cannot license to yourself");
        require(
            copyrights[ipId].economicRightsOwner == msg.sender,
            "Not economic rights owner"
        );
        require(bytes(terms).length > 0, "Terms cannot be empty");

        // Validate granted rights against owned rights
        _validateGrantedRights(ipId, grantedRights);

        uint256 licenseId = licenseCounter++;

        licenses[licenseId] = License({
            ipId: ipId,
            licensor: msg.sender,
            licensee: licensee,
            licenseType: licenseType,
            status: LicenseStatus.OFFERED,
            fee: fee,
            duration: duration,
            startTime: 0,
            endTime: 0,
            terms: terms,
            grantedRights: grantedRights,
            exclusive: exclusive,
            territory: territory,
            royaltyPercentage: 100
        });

        // Update mappings
        copyrightLicenses[ipId].push(licenseId);
        licenseeOffers[ipId][licensee].push(licenseId);

        // Transfer platform fee
        _transferFee(msg.value);

        emit LicenseOffered(
            licenseId,
            ipId,
            msg.sender,
            licensee,
            licenseType,
            fee,
            duration
        );
    }

    /**
     * @dev Accept a license offer
     * @param licenseId License ID to accept
     */
    function acceptLicense(
        uint256 licenseId
    )
        external
        payable
        nonReentrant
        whenNotPaused
        validLicense(licenseId)
        onlyLicensee(licenseId)
    {
        License storage license = licenses[licenseId];
        require(license.status == LicenseStatus.OFFERED, "License not offered");
        require(msg.value >= license.fee, "Insufficient payment");

        // Update license status
        license.status = LicenseStatus.ACCEPTED;
        license.startTime = block.timestamp;

        if (license.duration > 0) {
            license.endTime = block.timestamp + license.duration;
        }

        // Transfer payment to licensor
        if (license.fee > 0) {
            (bool success, ) = payable(license.licensor).call{
                value: license.fee
            }("");
            require(success, "Payment failed");
        }

        // Refund excess payment
        if (msg.value > license.fee) {
            (bool refundSuccess, ) = payable(msg.sender).call{
                value: msg.value - license.fee
            }("");
            require(refundSuccess, "Refund failed");
        }

        emit LicenseAccepted(licenseId, license.ipId, license.licensor);
    }

    /**
     * @dev Revoke an active license (licensor only)
     * @param licenseId License ID to revoke
     */
    function revokeLicense(
        uint256 licenseId
    ) external validLicense(licenseId) onlyLicensor(licenseId) {
        License storage license = licenses[licenseId];
        require(license.status == LicenseStatus.ACCEPTED, "License not active");

        license.status = LicenseStatus.REVOKED;
        emit LicenseRevoked(licenseId, msg.sender);
    }

    /**
     * @dev Cancel a license offer (licensor or licensee)
     * @param licenseId License ID to cancel
     */
    function cancelLicense(uint256 licenseId) external validLicense(licenseId) {
        License storage license = licenses[licenseId];
        require(
            license.status == LicenseStatus.OFFERED,
            "Can only cancel offered licenses"
        );
        require(
            license.licensor == msg.sender || license.licensee == msg.sender,
            "Not authorized to cancel"
        );

        license.status = LicenseStatus.CANCELLED;
        emit LicenseCancelled(licenseId, msg.sender);
    }

    /**
     * @dev Check and update expired licenses
     * @param licenseId License ID to check
     */
    function checkLicenseExpiry(
        uint256 licenseId
    ) external validLicense(licenseId) {
        License storage license = licenses[licenseId];
        require(license.status == LicenseStatus.ACCEPTED, "License not active");
        require(license.duration > 0, "License has no expiration");
        require(block.timestamp >= license.endTime, "License not expired");

        license.status = LicenseStatus.EXPIRED;
        emit LicenseExpired(licenseId);
    }

    /**
     * @dev Check if address has valid license for specific rights
     * @param ipId Copyright token ID
     * @param licensee Address to check
     * @param rightType Type of right to check (0-6)
     * @return bool Whether licensee has valid license for the right
     */
    function hasValidLicense(
        uint256 ipId,
        address licensee,
        uint8 rightType
    ) external view returns (bool) {
        require(rightType <= 6, "Invalid right type");

        uint256[] memory licenseIds = licenseeOffers[ipId][licensee];

        for (uint256 i = 0; i < licenseIds.length; i++) {
            License memory license = licenses[licenseIds[i]];

            if (
                license.status == LicenseStatus.ACCEPTED &&
                _isLicenseActive(license) &&
                _hasRight(license.grantedRights, rightType)
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Get all licenses for a copyright
     * @param ipId Copyright token ID
     * @return Array of license IDs
     */
    function getCopyrightLicenses(
        uint256 ipId
    ) external view validTokenId(ipId) returns (uint256[] memory) {
        return copyrightLicenses[ipId];
    }

    /**
     * @dev Get license details
     * @param licenseId License ID
     * @return License struct
     */
    function getLicense(
        uint256 licenseId
    ) external view validLicense(licenseId) returns (License memory) {
        return licenses[licenseId];
    }

    /**
     * @dev Get all license offers for a specific licensee
     * @param ipId Copyright token ID
     * @param licensee Licensee address
     * @return Array of license IDs
     */
    function getLicenseeOffers(
        uint256 ipId,
        address licensee
    ) external view returns (uint256[] memory) {
        return licenseeOffers[ipId][licensee];
    }

    /**
     * @dev Internal function to validate granted rights
     * @param ipId Copyright token ID
     * @param grantedRights Rights to validate
     */
    function _validateGrantedRights(
        uint256 ipId,
        EconomicRights memory grantedRights
    ) internal view {
        EconomicRights memory ownedRights = copyrights[ipId].copyrights;

        require(
            !grantedRights.reproduction || ownedRights.reproduction,
            "Reproduction right not owned"
        );
        require(
            !grantedRights.distribution || ownedRights.distribution,
            "Distribution right not owned"
        );
        require(
            !grantedRights.rental || ownedRights.rental,
            "Rental right not owned"
        );
        require(
            !grantedRights.broadcasting || ownedRights.broadcasting,
            "Broadcasting right not owned"
        );
        require(
            !grantedRights.performance || ownedRights.performance,
            "Performance right not owned"
        );
        require(
            !grantedRights.translation || ownedRights.translation,
            "Translation right not owned"
        );
        require(
            !grantedRights.adaptation || ownedRights.adaptation,
            "Adaptation right not owned"
        );
    }

    /**
     * @dev Check if license is currently active
     * @param license License to check
     * @return bool Whether license is active
     */
    function _isLicenseActive(
        License memory license
    ) internal view returns (bool) {
        if (license.duration == 0) {
            return true; // Unlimited duration
        }
        return block.timestamp < license.endTime;
    }

    /**
     * @dev Check if license grants specific right
     * @param rights Economic rights struct
     * @param rightType Right type to check (0-6)
     * @return bool Whether right is granted
     */
    function _hasRight(
        EconomicRights memory rights,
        uint8 rightType
    ) internal pure returns (bool) {
        if (rightType == 0) return rights.reproduction;
        if (rightType == 1) return rights.distribution;
        if (rightType == 2) return rights.rental;
        if (rightType == 3) return rights.broadcasting;
        if (rightType == 4) return rights.performance;
        if (rightType == 5) return rights.translation;
        if (rightType == 6) return rights.adaptation;
        return false;
    }

    /**
     * @dev Override to support ERC2981
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ====Governance

    /**
     * @dev Get license proposal data
     * @param _id The proposal ID
     * @return licenseId The license ID
     * @return licenseAmount The amount of licenses
     */
    function getLicenseData(
        uint256 _id
    ) external view returns (uint256 licenseId, uint256 licenseAmount) {
        require(_licenseData[_id].exists, "License proposal doesn't exist");

        LicenseData storage ld = _licenseData[_id];
        return (ld.licenseId, ld.licenseAmount);
    }

    /**
     * @dev Check if a license proposal exists
     * @param _id The proposal ID
     * @return Whether the proposal exists
     */
    function licenseProposalExists(uint256 _id) external view returns (bool) {
        return _licenseData[_id].exists;
    }
}
