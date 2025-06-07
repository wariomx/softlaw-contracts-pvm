// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../interfaces/ISoftlawTreasury.sol";

/**
 * @title SoftlawAttestations
 * @dev Comprehensive legal attestation and verification system
 * Features:
 * - Professional credential verification
 * - Legal document attestation
 * - IP authenticity verification
 * - Cross-jurisdictional compliance
 * - Oracle integration for external verification
 * - Reputation system for attesters
 * - Treasury integration for SLAW payments
 */
contract SoftlawAttestations is AccessControl, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    ISoftlawTreasury public immutable treasury;

    // Roles
    bytes32 public constant ATTESTER_ROLE = keccak256("ATTESTER_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant ATTESTATION_ADMIN = keccak256("ATTESTATION_ADMIN");

    // Attestation types
    enum AttestationType {
        LEGAL_PROFESSIONAL,     // Lawyer/Legal professional verification
        DOCUMENT_AUTHENTICITY,  // Legal document verification
        IP_OWNERSHIP,          // IP ownership verification
        PRIOR_ART,             // Prior art verification
        COMPLIANCE,            // Regulatory compliance
        EXPERT_OPINION,        // Expert technical opinion
        NOTARIZATION,          // Digital notarization
        TRANSLATION           // Certified translation
    }

    // Attestation status
    enum AttestationStatus {
        PENDING,               // Awaiting verification
        VERIFIED,              // Successfully verified
        REJECTED,              // Verification failed
        DISPUTED,              // Under dispute
        REVOKED,               // Attestation revoked
        EXPIRED                // Attestation expired
    }

    // Jurisdiction codes
    enum Jurisdiction {
        UNITED_STATES,
        EUROPEAN_UNION,
        UNITED_KINGDOM,
        CANADA,
        JAPAN,
        CHINA,
        INTERNATIONAL,
        OTHER
    }

    // Comprehensive attestation structure
    struct Attestation {
        uint256 id;
        AttestationType attestationType;
        AttestationStatus status;
        address requester;
        address attester;
        address verifier;
        Jurisdiction jurisdiction;
        string title;
        string description;
        string documentHash;        // IPFS hash of documents
        string evidenceHash;        // IPFS hash of supporting evidence
        uint256 requestDate;
        uint256 attestationDate;
        uint256 expiryDate;
        uint256 feeAmount;         // SLAW tokens paid
        string attestationData;    // JSON data of attestation details
        bytes attesterSignature;   // Digital signature
        bytes verifierSignature;   // Verifier signature
        mapping(uint256 => Challenge) challenges;
        uint256 challengeCount;
        uint256 reputationImpact;  // Impact on attester reputation
        bool isRevocable;
        string revocationReason;
    }

    // Challenge structure for disputed attestations
    struct Challenge {
        uint256 id;
        address challenger;
        string reason;
        string evidence;
        uint256 challengeDate;
        uint256 resolutionDate;
        bool isResolved;
        bool challengeUpheld;
        address resolver;
    }

    // Attester profile
    struct AttesterProfile {
        string name;
        string credentials;
        string jurisdiction;
        string[] specializations;
        uint256 reputationScore;
        uint256 attestationsCompleted;
        uint256 attestationsDisputed;
        uint256 joinDate;
        bool isActive;
        uint256 feePerAttestation;  // SLAW tokens
        string contactInfo;
        bytes32[] certificationHashes; // Professional certifications
    }

    // Storage
    mapping(uint256 => Attestation) public attestations;
    mapping(address => AttesterProfile) public attesters;
    mapping(address => uint256[]) public userAttestations;
    mapping(address => uint256[]) public attesterHistory;
    mapping(AttestationType => uint256[]) public typeAttestations;
    mapping(Jurisdiction => uint256[]) public jurisdictionAttestations;
    mapping(address => bool) public isQualifiedAttester;
    
    address[] public attesterList;
    uint256 public attestationCounter = 1;
    uint256 public challengeCounter = 1;

    // System configuration
    uint256 public constant ATTESTATION_FEE = 20 * 10**18;        // 20 SLAW
    uint256 public constant CHALLENGE_FEE = 50 * 10**18;          // 50 SLAW
    uint256 public constant VERIFICATION_FEE = 30 * 10**18;       // 30 SLAW
    uint256 public constant MIN_REPUTATION = 500;                 // Minimum reputation to attest
    uint256 public constant REPUTATION_PENALTY = 100;             // Penalty for disputed attestations
    uint256 public constant REPUTATION_REWARD = 10;               // Reward for successful attestations

    // Default expiry periods (in seconds)
    mapping(AttestationType => uint256) public defaultExpiry;

    // Events
    event AttestationRequested(
        uint256 indexed attestationId,
        address indexed requester,
        AttestationType attestationType,
        Jurisdiction jurisdiction
    );

    event AttestationCompleted(
        uint256 indexed attestationId,
        address indexed attester,
        AttestationStatus status
    );

    event AttestationChallenged(
        uint256 indexed attestationId,
        uint256 indexed challengeId,
        address indexed challenger
    );

    event AttesterRegistered(
        address indexed attester,
        string name,
        string jurisdiction
    );

    event ReputationUpdated(
        address indexed attester,
        uint256 oldReputation,
        uint256 newReputation
    );

    constructor(address _treasury, address _admin) {
        treasury = ISoftlawTreasury(_treasury);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ATTESTATION_ADMIN, _admin);
        
        // Set default expiry periods
        _setDefaultExpiries();
    }

    /**
     * @dev Request a new attestation
     * @param attestationType Type of attestation needed
     * @param jurisdiction Legal jurisdiction
     * @param attester Preferred attester (can be zero address for any)
     * @param title Attestation title
     * @param description Detailed description
     * @param documentHash IPFS hash of documents to be attested
     * @param evidenceHash IPFS hash of supporting evidence
     */
    function requestAttestation(
        AttestationType attestationType,
        Jurisdiction jurisdiction,
        address attester,
        string memory title,
        string memory description,
        string memory documentHash,
        string memory evidenceHash
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(documentHash).length > 0, "Document hash required");

        // Pay attestation fee
        treasury.payLicenseFee(address(0), msg.sender, 0, ATTESTATION_FEE);

        uint256 attestationId = attestationCounter++;

        Attestation storage attestation = attestations[attestationId];
        attestation.id = attestationId;
        attestation.attestationType = attestationType;
        attestation.status = AttestationStatus.PENDING;
        attestation.requester = msg.sender;
        attestation.attester = attester; // Can be zero address
        attestation.jurisdiction = jurisdiction;
        attestation.title = title;
        attestation.description = description;
        attestation.documentHash = documentHash;
        attestation.evidenceHash = evidenceHash;
        attestation.requestDate = block.timestamp;
        attestation.expiryDate = block.timestamp + defaultExpiry[attestationType];
        attestation.feeAmount = ATTESTATION_FEE;
        attestation.isRevocable = true;

        // Update mappings
        userAttestations[msg.sender].push(attestationId);
        typeAttestations[attestationType].push(attestationId);
        jurisdictionAttestations[jurisdiction].push(attestationId);

        emit AttestationRequested(attestationId, msg.sender, attestationType, jurisdiction);

        return attestationId;
    }

    /**
     * @dev Complete attestation (for qualified attesters)
     * @param attestationId Attestation ID
     * @param isApproved Whether attestation is approved
     * @param attestationData JSON data with attestation details
     * @param signature Digital signature of attester
     */
    function completeAttestation(
        uint256 attestationId,
        bool isApproved,
        string memory attestationData,
        bytes memory signature
    ) external nonReentrant whenNotPaused {
        Attestation storage attestation = attestations[attestationId];
        require(attestation.status == AttestationStatus.PENDING, "Not pending");
        require(
            attestation.attester == msg.sender || 
            (attestation.attester == address(0) && hasRole(ATTESTER_ROLE, msg.sender)),
            "Not authorized attester"
        );
        require(attesters[msg.sender].reputationScore >= MIN_REPUTATION, "Insufficient reputation");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            attestationId,
            isApproved,
            attestationData,
            block.timestamp
        )).toEthSignedMessageHash();
        
        require(messageHash.recover(signature) == msg.sender, "Invalid signature");

        // Update attestation
        attestation.attester = msg.sender;
        attestation.status = isApproved ? AttestationStatus.VERIFIED : AttestationStatus.REJECTED;
        attestation.attestationDate = block.timestamp;
        attestation.attestationData = attestationData;
        attestation.attesterSignature = signature;

        // Pay attester
        uint256 attesterFee = attesters[msg.sender].feePerAttestation;
        if (attesterFee > 0) {
            treasury.distributeIncentives(
                _asSingletonArray(msg.sender),
                _asSingletonArray(attesterFee)
            );
        }

        // Update reputation
        _updateReputation(msg.sender, REPUTATION_REWARD);

        // Update attester history
        attesterHistory[msg.sender].push(attestationId);
        attesters[msg.sender].attestationsCompleted++;

        emit AttestationCompleted(attestationId, msg.sender, attestation.status);
    }

    /**
     * @dev Verify attestation (for verifiers)
     * @param attestationId Attestation ID
     * @param verifierSignature Verifier's signature
     */
    function verifyAttestation(
        uint256 attestationId,
        bytes memory verifierSignature
    ) external onlyRole(VERIFIER_ROLE) nonReentrant {
        Attestation storage attestation = attestations[attestationId];
        require(attestation.status == AttestationStatus.VERIFIED, "Not verified status");

        // Pay verification fee
        treasury.payLicenseFee(address(0), msg.sender, attestationId, VERIFICATION_FEE);

        attestation.verifier = msg.sender;
        attestation.verifierSignature = verifierSignature;

        // Additional verification reward
        treasury.distributeIncentives(
            _asSingletonArray(msg.sender),
            _asSingletonArray(VERIFICATION_FEE / 2) // 50% of fee as reward
        );
    }

    /**
     * @dev Challenge an attestation
     * @param attestationId Attestation ID to challenge
     * @param reason Reason for challenge
     * @param evidence Supporting evidence for challenge
     */
    function challengeAttestation(
        uint256 attestationId,
        string memory reason,
        string memory evidence
    ) external nonReentrant whenNotPaused returns (uint256) {
        Attestation storage attestation = attestations[attestationId];
        require(attestation.status == AttestationStatus.VERIFIED, "Only verified attestations can be challenged");
        require(bytes(reason).length > 0, "Reason required");

        // Pay challenge fee
        treasury.payLicenseFee(address(0), msg.sender, attestationId, CHALLENGE_FEE);

        uint256 challengeId = challengeCounter++;

        Challenge storage challenge = attestation.challenges[attestation.challengeCount];
        challenge.id = challengeId;
        challenge.challenger = msg.sender;
        challenge.reason = reason;
        challenge.evidence = evidence;
        challenge.challengeDate = block.timestamp;

        attestation.challengeCount++;
        attestation.status = AttestationStatus.DISPUTED;

        emit AttestationChallenged(attestationId, challengeId, msg.sender);

        return challengeId;
    }

    /**
     * @dev Resolve challenge (admin function)
     * @param attestationId Attestation ID
     * @param challengeIndex Challenge index
     * @param challengeUpheld Whether challenge is upheld
     */
    function resolveChallenge(
        uint256 attestationId,
        uint256 challengeIndex,
        bool challengeUpheld
    ) external onlyRole(ATTESTATION_ADMIN) nonReentrant {
        Attestation storage attestation = attestations[attestationId];
        require(challengeIndex < attestation.challengeCount, "Invalid challenge");

        Challenge storage challenge = attestation.challenges[challengeIndex];
        require(!challenge.isResolved, "Challenge already resolved");

        challenge.isResolved = true;
        challenge.challengeUpheld = challengeUpheld;
        challenge.resolutionDate = block.timestamp;
        challenge.resolver = msg.sender;

        if (challengeUpheld) {
            // Challenge upheld - revoke attestation and penalize attester
            attestation.status = AttestationStatus.REVOKED;
            attestation.revocationReason = challenge.reason;
            
            _updateReputation(attestation.attester, -REPUTATION_PENALTY);
            attesters[attestation.attester].attestationsDisputed++;

            // Refund challenger
            treasury.distributeIncentives(
                _asSingletonArray(challenge.challenger),
                _asSingletonArray(CHALLENGE_FEE)
            );
        } else {
            // Challenge rejected - restore attestation
            attestation.status = AttestationStatus.VERIFIED;
            
            // Reward attester for false challenge
            treasury.distributeIncentives(
                _asSingletonArray(attestation.attester),
                _asSingletonArray(CHALLENGE_FEE / 2)
            );
        }
    }

    /**
     * @dev Register as qualified attester
     * @param name Attester name
     * @param credentials Professional credentials
     * @param jurisdiction Primary jurisdiction
     * @param specializations Areas of specialization
     * @param feePerAttestation Fee per attestation in SLAW
     * @param contactInfo Contact information
     */
    function registerAttester(
        string memory name,
        string memory credentials,
        string memory jurisdiction,
        string[] memory specializations,
        uint256 feePerAttestation,
        string memory contactInfo
    ) external {
        require(bytes(name).length > 0, "Name required");
        require(!isQualifiedAttester[msg.sender], "Already registered");

        attesters[msg.sender] = AttesterProfile({
            name: name,
            credentials: credentials,
            jurisdiction: jurisdiction,
            specializations: specializations,
            reputationScore: 1000, // Starting reputation
            attestationsCompleted: 0,
            attestationsDisputed: 0,
            joinDate: block.timestamp,
            isActive: true,
            feePerAttestation: feePerAttestation,
            contactInfo: contactInfo,
            certificationHashes: new bytes32[](0)
        });

        isQualifiedAttester[msg.sender] = true;
        attesterList.push(msg.sender);

        // Grant attester role
        _grantRole(ATTESTER_ROLE, msg.sender);

        emit AttesterRegistered(msg.sender, name, jurisdiction);
    }

    /**
     * @dev Add professional certification
     * @param certificationHash Hash of certification document
     */
    function addCertification(bytes32 certificationHash) external {
        require(isQualifiedAttester[msg.sender], "Not registered attester");
        attesters[msg.sender].certificationHashes.push(certificationHash);
    }

    // ===== VIEW FUNCTIONS =====

    function getAttestation(uint256 attestationId) external view returns (
        uint256 id,
        AttestationType attestationType,
        AttestationStatus status,
        address requester,
        address attester,
        Jurisdiction jurisdiction,
        string memory title,
        uint256 attestationDate,
        uint256 expiryDate
    ) {
        Attestation storage attestation = attestations[attestationId];
        return (
            attestation.id,
            attestation.attestationType,
            attestation.status,
            attestation.requester,
            attestation.attester,
            attestation.jurisdiction,
            attestation.title,
            attestation.attestationDate,
            attestation.expiryDate
        );
    }

    function getUserAttestations(address user) external view returns (uint256[] memory) {
        return userAttestations[user];
    }

    function getAttesterProfile(address attester) external view returns (AttesterProfile memory) {
        return attesters[attester];
    }

    function getAttestationsByType(AttestationType attestationType) external view returns (uint256[] memory) {
        return typeAttestations[attestationType];
    }

    function getAttestationsByJurisdiction(Jurisdiction jurisdiction) external view returns (uint256[] memory) {
        return jurisdictionAttestations[jurisdiction];
    }

    function getAllAttesters() external view returns (address[] memory) {
        return attesterList;
    }

    function getChallenge(uint256 attestationId, uint256 challengeIndex) external view returns (Challenge memory) {
        return attestations[attestationId].challenges[challengeIndex];
    }

    function isAttestationValid(uint256 attestationId) external view returns (bool) {
        Attestation storage attestation = attestations[attestationId];
        return attestation.status == AttestationStatus.VERIFIED && 
               block.timestamp <= attestation.expiryDate;
    }

    // ===== INTERNAL FUNCTIONS =====

    function _updateReputation(address attester, int256 change) internal {
        AttesterProfile storage profile = attesters[attester];
        uint256 oldReputation = profile.reputationScore;
        
        if (change < 0 && uint256(-change) > oldReputation) {
            profile.reputationScore = 0;
        } else {
            profile.reputationScore = uint256(int256(oldReputation) + change);
        }

        emit ReputationUpdated(attester, oldReputation, profile.reputationScore);
    }

    function _setDefaultExpiries() internal {
        defaultExpiry[AttestationType.LEGAL_PROFESSIONAL] = 365 days;
        defaultExpiry[AttestationType.DOCUMENT_AUTHENTICITY] = 180 days;
        defaultExpiry[AttestationType.IP_OWNERSHIP] = 730 days; // 2 years
        defaultExpiry[AttestationType.PRIOR_ART] = 365 days;
        defaultExpiry[AttestationType.COMPLIANCE] = 180 days;
        defaultExpiry[AttestationType.EXPERT_OPINION] = 365 days;
        defaultExpiry[AttestationType.NOTARIZATION] = 1095 days; // 3 years
        defaultExpiry[AttestationType.TRANSLATION] = 365 days;
    }

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

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(ATTESTATION_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(ATTESTATION_ADMIN) {
        _unpause();
    }

    function updateDefaultExpiry(AttestationType attestationType, uint256 newExpiry) external onlyRole(ATTESTATION_ADMIN) {
        defaultExpiry[attestationType] = newExpiry;
    }

    function deactivateAttester(address attester) external onlyRole(ATTESTATION_ADMIN) {
        attesters[attester].isActive = false;
        _revokeRole(ATTESTER_ROLE, attester);
    }

    function emergencyRevokeAttestation(uint256 attestationId, string memory reason) external onlyRole(ATTESTATION_ADMIN) {
        Attestation storage attestation = attestations[attestationId];
        attestation.status = AttestationStatus.REVOKED;
        attestation.revocationReason = reason;
    }
}
