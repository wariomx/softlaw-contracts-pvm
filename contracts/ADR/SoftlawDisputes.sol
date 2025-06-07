// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/ISoftlawTreasury.sol";

/**
 * @title SoftlawDisputeResolution
 * @dev Comprehensive dispute resolution system for IP-related conflicts
 * Features:
 * - Multi-stage dispute process (filing, mediation, arbitration, appeal)
 * - Treasury integration for SLAW payments and escrow
 * - Qualified arbitrator network
 * - Evidence management system
 * - Automated enforcement
 * - Integration with IP contracts (copyrights, patents)
 */
contract SoftlawDisputeResolution is AccessControl, ReentrancyGuard, Pausable {
    ISoftlawTreasury public immutable treasury;

    // Roles
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
    bytes32 public constant MEDIATOR_ROLE = keccak256("MEDIATOR_ROLE");
    bytes32 public constant DISPUTE_ADMIN = keccak256("DISPUTE_ADMIN");

    // Dispute types
    enum DisputeType {
        COPYRIGHT_INFRINGEMENT,
        PATENT_INFRINGEMENT,
        LICENSE_BREACH,
        OWNERSHIP_DISPUTE,
        ROYALTY_DISPUTE,
        PRIOR_ART_CHALLENGE,
        TRADEMARK_DISPUTE
    }

    // Dispute status
    enum DisputeStatus {
        FILED, // Dispute filed, waiting for response
        MEDIATION, // In mediation phase
        ARBITRATION, // In arbitration phase
        APPEALED, // Under appeal
        RESOLVED, // Resolved (settled or decided)
        ENFORCED, // Decision enforced
        DISMISSED // Dismissed
    }

    // Evidence types
    enum EvidenceType {
        DOCUMENT,
        TESTIMONY,
        EXPERT_OPINION,
        PRIOR_ART,
        CONTRACT,
        COMMUNICATION,
        TECHNICAL_ANALYSIS
    }

    // Comprehensive dispute structure
    struct Dispute {
        uint256 id;
        DisputeType disputeType;
        DisputeStatus status;
        address plaintiff;
        address defendant;
        address assignedMediator;
        address assignedArbitrator;
        uint256 relatedIPId; // Related copyright/patent ID
        address relatedIPContract; // Copyright or Patent contract
        string title;
        string description;
        uint256 claimedDamages; // In SLAW tokens
        uint256 filingDate;
        uint256 responseDeadline;
        uint256 resolutionDate;
        string decision;
        address winner;
        uint256 awardAmount; // SLAW tokens awarded
        bool isAppealed;
        uint256 escrowAmount; // SLAW in escrow
        mapping(uint256 => Evidence) evidence;
        uint256 evidenceCount;
        mapping(address => bool) agreedToMediation;
        mapping(address => Vote) votes;
        bool enforceable;
    }

    // Evidence structure
    struct Evidence {
        uint256 id;
        address submittedBy;
        EvidenceType evidenceType;
        string title;
        string description;
        string documentHash; // IPFS hash
        uint256 submissionDate;
        bool isAdmitted;
        string rejectionReason;
    }

    // Voting structure for arbitration
    struct Vote {
        bool hasVoted;
        bool inFavorOfPlaintiff;
        string reasoning;
        uint256 voteDate;
    }

    // Arbitrator profile
    struct Arbitrator {
        string name;
        string credentials;
        string[] specializations;
        uint256 casesResolved;
        uint256 reputationScore;
        bool isActive;
        uint256 feePerCase; // SLAW tokens
        address walletAddress;
    }

    // Storage
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public userDisputes;
    mapping(uint256 => uint256[]) public ipDisputes; // IP ID => dispute IDs
    mapping(address => Arbitrator) public arbitrators;
    mapping(address => bool) public isQualifiedArbitrator;
    address[] public arbitratorList;

    uint256 public disputeCounter = 1;

    // Fees (in SLAW tokens)
    uint256 public constant FILING_FEE = 50 * 10 ** 18; // 50 SLAW
    uint256 public constant MEDIATION_FEE = 25 * 10 ** 18; // 25 SLAW
    uint256 public constant ARBITRATION_FEE = 100 * 10 ** 18; // 100 SLAW
    uint256 public constant APPEAL_FEE = 150 * 10 ** 18; // 150 SLAW
    uint256 public constant EVIDENCE_FEE = 5 * 10 ** 18; // 5 SLAW per evidence

    // Timeframes
    uint256 public constant RESPONSE_PERIOD = 14 days;
    uint256 public constant MEDIATION_PERIOD = 30 days;
    uint256 public constant ARBITRATION_PERIOD = 60 days;
    uint256 public constant APPEAL_PERIOD = 21 days;

    // Events
    event DisputeFiled(
        uint256 indexed disputeId,
        address indexed plaintiff,
        address indexed defendant,
        DisputeType disputeType,
        uint256 claimedDamages
    );

    event DisputeStatusChanged(
        uint256 indexed disputeId,
        DisputeStatus oldStatus,
        DisputeStatus newStatus
    );

    event EvidenceSubmitted(
        uint256 indexed disputeId,
        uint256 indexed evidenceId,
        address indexed submitter,
        EvidenceType evidenceType
    );

    event MediationStarted(uint256 indexed disputeId, address indexed mediator);

    event ArbitrationStarted(
        uint256 indexed disputeId,
        address indexed arbitrator
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        address indexed winner,
        uint256 awardAmount,
        string decision
    );

    event ArbitratorRegistered(
        address indexed arbitrator,
        string name,
        uint256 feePerCase
    );

    event EscrowDeposited(
        uint256 indexed disputeId,
        address indexed depositor,
        uint256 amount
    );

    constructor(address _treasury, address _admin) {
        treasury = ISoftlawTreasury(_treasury);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DISPUTE_ADMIN, _admin);
    }

    /**
     * @dev File a new dispute
     * @param disputeType Type of dispute
     * @param defendant Address of defendant
     * @param relatedIPId Related IP ID (copyright/patent)
     * @param relatedIPContract Address of IP contract
     * @param title Dispute title
     * @param description Detailed description
     * @param claimedDamages Damages claimed in SLAW
     */
    function fileDispute(
        DisputeType disputeType,
        address defendant,
        uint256 relatedIPId,
        address relatedIPContract,
        string memory title,
        string memory description,
        uint256 claimedDamages
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(defendant != address(0), "Invalid defendant");
        require(defendant != msg.sender, "Cannot dispute with yourself");
        require(bytes(title).length > 0, "Title required");
        require(claimedDamages > 0, "Damages must be > 0");

        // Pay filing fee
        treasury.payLicenseFee(address(0), msg.sender, 0, FILING_FEE);

        uint256 disputeId = disputeCounter++;

        Dispute storage dispute = disputes[disputeId];
        dispute.id = disputeId;
        dispute.disputeType = disputeType;
        dispute.status = DisputeStatus.FILED;
        dispute.plaintiff = msg.sender;
        dispute.defendant = defendant;
        dispute.relatedIPId = relatedIPId;
        dispute.relatedIPContract = relatedIPContract;
        dispute.title = title;
        dispute.description = description;
        dispute.claimedDamages = claimedDamages;
        dispute.filingDate = block.timestamp;
        dispute.responseDeadline = block.timestamp + RESPONSE_PERIOD;

        // Update mappings
        userDisputes[msg.sender].push(disputeId);
        userDisputes[defendant].push(disputeId);
        if (relatedIPId > 0) {
            ipDisputes[relatedIPId].push(disputeId);
        }

        emit DisputeFiled(
            disputeId,
            msg.sender,
            defendant,
            disputeType,
            claimedDamages
        );

        return disputeId;
    }

    /**
     * @dev Deposit funds into escrow for dispute
     * @param disputeId Dispute ID
     * @param amount Amount to deposit
     */
    function depositEscrow(
        uint256 disputeId,
        uint256 amount
    ) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(
            msg.sender == dispute.plaintiff || msg.sender == dispute.defendant,
            "Not a party to dispute"
        );
        require(dispute.status != DisputeStatus.DISMISSED, "Dispute dismissed");

        // Transfer SLAW to this contract as escrow
        treasury.payLicenseFee(address(0), msg.sender, disputeId, amount);
        dispute.escrowAmount += amount;

        emit EscrowDeposited(disputeId, msg.sender, amount);
    }

    /**
     * @dev Start mediation process
     * @param disputeId Dispute ID
     * @param mediator Address of mediator
     */
    function startMediation(
        uint256 disputeId,
        address mediator
    ) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(
            msg.sender == dispute.plaintiff ||
                msg.sender == dispute.defendant ||
                hasRole(DISPUTE_ADMIN, msg.sender),
            "Not authorized"
        );
        require(
            dispute.status == DisputeStatus.FILED,
            "Invalid status for mediation"
        );
        require(hasRole(MEDIATOR_ROLE, mediator), "Not qualified mediator");

        // Pay mediation fee (split between parties)
        uint256 feePerParty = MEDIATION_FEE / 2;
        treasury.payLicenseFee(
            address(0),
            dispute.plaintiff,
            disputeId,
            feePerParty
        );
        treasury.payLicenseFee(
            address(0),
            dispute.defendant,
            disputeId,
            feePerParty
        );

        dispute.status = DisputeStatus.MEDIATION;
        dispute.assignedMediator = mediator;

        emit DisputeStatusChanged(
            disputeId,
            DisputeStatus.FILED,
            DisputeStatus.MEDIATION
        );
        emit MediationStarted(disputeId, mediator);
    }

    /**
     * @dev Start arbitration process
     * @param disputeId Dispute ID
     * @param arbitrator Address of arbitrator
     */
    function startArbitration(
        uint256 disputeId,
        address arbitrator
    ) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(
            dispute.status == DisputeStatus.FILED ||
                dispute.status == DisputeStatus.MEDIATION,
            "Invalid status for arbitration"
        );
        require(
            hasRole(ARBITRATOR_ROLE, arbitrator),
            "Not qualified arbitrator"
        );

        // Pay arbitration fee + arbitrator fee
        uint256 totalFee = ARBITRATION_FEE + arbitrators[arbitrator].feePerCase;
        uint256 feePerParty = totalFee / 2;

        treasury.payLicenseFee(
            address(0),
            dispute.plaintiff,
            disputeId,
            feePerParty
        );
        treasury.payLicenseFee(
            address(0),
            dispute.defendant,
            disputeId,
            feePerParty
        );

        // Pay arbitrator
        treasury.payArbitratorFee(
            arbitrator,
            disputeId,
            arbitrators[arbitrator].feePerCase
        );

        dispute.status = DisputeStatus.ARBITRATION;
        dispute.assignedArbitrator = arbitrator;

        emit DisputeStatusChanged(
            disputeId,
            dispute.status,
            DisputeStatus.ARBITRATION
        );
        emit ArbitrationStarted(disputeId, arbitrator);
    }

    /**
     * @dev Submit evidence
     * @param disputeId Dispute ID
     * @param evidenceType Type of evidence
     * @param title Evidence title
     * @param description Evidence description
     * @param documentHash IPFS hash of evidence
     */
    function submitEvidence(
        uint256 disputeId,
        EvidenceType evidenceType,
        string memory title,
        string memory description,
        string memory documentHash
    ) external nonReentrant returns (uint256) {
        Dispute storage dispute = disputes[disputeId];
        require(
            msg.sender == dispute.plaintiff || msg.sender == dispute.defendant,
            "Not a party to dispute"
        );
        require(
            dispute.status == DisputeStatus.MEDIATION ||
                dispute.status == DisputeStatus.ARBITRATION,
            "Invalid status for evidence submission"
        );

        // Pay evidence fee
        treasury.payLicenseFee(address(0), msg.sender, disputeId, EVIDENCE_FEE);

        uint256 evidenceId = dispute.evidenceCount++;

        Evidence storage evidence = dispute.evidence[evidenceId];
        evidence.id = evidenceId;
        evidence.submittedBy = msg.sender;
        evidence.evidenceType = evidenceType;
        evidence.title = title;
        evidence.description = description;
        evidence.documentHash = documentHash;
        evidence.submissionDate = block.timestamp;
        evidence.isAdmitted = true; // Auto-admit for now, could require review

        emit EvidenceSubmitted(disputeId, evidenceId, msg.sender, evidenceType);

        return evidenceId;
    }

    /**
     * @dev Submit arbitration decision
     * @param disputeId Dispute ID
     * @param inFavorOfPlaintiff True if ruling in favor of plaintiff
     * @param awardAmount Award amount in SLAW
     * @param decision Written decision
     */
    function submitArbitrationDecision(
        uint256 disputeId,
        bool inFavorOfPlaintiff,
        uint256 awardAmount,
        string memory decision
    ) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(
            msg.sender == dispute.assignedArbitrator,
            "Not assigned arbitrator"
        );
        require(
            dispute.status == DisputeStatus.ARBITRATION,
            "Not in arbitration"
        );

        dispute.status = DisputeStatus.RESOLVED;
        dispute.resolutionDate = block.timestamp;
        dispute.decision = decision;
        dispute.awardAmount = awardAmount;
        dispute.winner = inFavorOfPlaintiff
            ? dispute.plaintiff
            : dispute.defendant;
        dispute.enforceable = true;

        // Update arbitrator reputation
        arbitrators[msg.sender].casesResolved++;

        emit DisputeResolved(disputeId, dispute.winner, awardAmount, decision);
        emit DisputeStatusChanged(
            disputeId,
            DisputeStatus.ARBITRATION,
            DisputeStatus.RESOLVED
        );
    }

    /**
     * @dev Execute dispute resolution (transfer escrow funds)
     * @param disputeId Dispute ID
     */
    function enforceAward(uint256 disputeId) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        require(
            dispute.status == DisputeStatus.RESOLVED,
            "Dispute not resolved"
        );
        require(dispute.winner != address(0), "No winner set");

        // Transfer award from escrow to winner
        if (dispute.awardAmount > 0) {
            treasury.distributeAward(
                dispute.winner,
                disputeId,
                dispute.awardAmount
            );
        }

        // Return remaining escrow to depositors (simplified - equal split)
        uint256 remaining = dispute.escrowAmount - dispute.awardAmount;
        if (remaining > 0) {
            uint256 halfRemaining = remaining / 2;
            treasury.refundEscrow(dispute.plaintiff, disputeId, halfRemaining);
            treasury.refundEscrow(
                dispute.defendant,
                disputeId,
                remaining - halfRemaining
            );
        }

        dispute.status = DisputeStatus.ENFORCED;
        emit DisputeStatusChanged(
            disputeId,
            DisputeStatus.RESOLVED,
            DisputeStatus.ENFORCED
        );
    }

    /**
     * @dev Register as qualified arbitrator
     * @param name Arbitrator name
     * @param credentials Credentials description
     * @param specializations Array of specialization areas
     * @param feePerCase Fee per case in SLAW
     */
    function registerArbitrator(
        string memory name,
        string memory credentials,
        string[] memory specializations,
        uint256 feePerCase
    ) external {
        require(bytes(name).length > 0, "Name required");
        require(feePerCase > 0, "Fee must be > 0");
        require(!isQualifiedArbitrator[msg.sender], "Already registered");

        arbitrators[msg.sender] = Arbitrator({
            name: name,
            credentials: credentials,
            specializations: specializations,
            casesResolved: 0,
            reputationScore: 1000, // Starting reputation
            isActive: true,
            feePerCase: feePerCase,
            walletAddress: msg.sender
        });

        isQualifiedArbitrator[msg.sender] = true;
        arbitratorList.push(msg.sender);

        // Grant arbitrator role
        _grantRole(ARBITRATOR_ROLE, msg.sender);

        emit ArbitratorRegistered(msg.sender, name, feePerCase);
    }

    // ===== VIEW FUNCTIONS =====

    function getDispute(
        uint256 disputeId
    )
        external
        view
        returns (
            uint256 id,
            DisputeType disputeType,
            DisputeStatus status,
            address plaintiff,
            address defendant,
            string memory title,
            uint256 claimedDamages,
            uint256 awardAmount,
            address winner
        )
    {
        Dispute storage dispute = disputes[disputeId];
        return (
            dispute.id,
            dispute.disputeType,
            dispute.status,
            dispute.plaintiff,
            dispute.defendant,
            dispute.title,
            dispute.claimedDamages,
            dispute.awardAmount,
            dispute.winner
        );
    }

    function getUserDisputes(
        address user
    ) external view returns (uint256[] memory) {
        return userDisputes[user];
    }

    function getIPDisputes(
        uint256 ipId
    ) external view returns (uint256[] memory) {
        return ipDisputes[ipId];
    }

    function getArbitratorInfo(
        address arbitrator
    ) external view returns (Arbitrator memory) {
        return arbitrators[arbitrator];
    }

    function getAllArbitrators() external view returns (address[] memory) {
        return arbitratorList;
    }

    function getEvidence(
        uint256 disputeId,
        uint256 evidenceId
    ) external view returns (Evidence memory) {
        return disputes[disputeId].evidence[evidenceId];
    }

    // ===== INTERNAL FUNCTIONS =====

    function _asSingletonArray(
        address element
    ) internal pure returns (address[] memory) {
        address[] memory array = new address[](1);
        array[0] = element;
        return array;
    }

    function _asSingletonArray(
        uint256 element
    ) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;
        return array;
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(DISPUTE_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(DISPUTE_ADMIN) {
        _unpause();
    }

    function grantMediatorRole(
        address mediator
    ) external onlyRole(DISPUTE_ADMIN) {
        _grantRole(MEDIATOR_ROLE, mediator);
    }

    function revokeMediatorRole(
        address mediator
    ) external onlyRole(DISPUTE_ADMIN) {
        _revokeRole(MEDIATOR_ROLE, mediator);
    }
}
