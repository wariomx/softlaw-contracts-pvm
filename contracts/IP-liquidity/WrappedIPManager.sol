// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SLAWToken.sol";

/**
 * @title PersonalizedWrappedIPToken
 * @dev Lightweight ERC20 token for PVM - optimized for memory constraints
 */
contract PersonalizedWrappedIPToken is ERC20 {
    uint256 public immutable nftId;
    address public immutable nftContract;
    address public immutable creator;
    address public immutable manager;
    uint256 public immutable createdAt;
    uint256 public pricePerToken; // Price in SLAW

    // Minimal storage for PVM
    string private _ipMetadata;
    string private _creatorName;
    uint256 public totalTradingVolume;
    uint256 public totalHolders;
    mapping(address => bool) public hasHeld;

    event TokenTraded(address indexed from, address indexed to, uint256 amount);
    event PriceUpdated(uint256 newPrice);

    constructor(
        uint256 _nftId,
        address _nftContract,
        address _creator,
        address _manager,
        uint256 _totalSupply,
        uint256 _pricePerToken,
        string memory _creatorName,
        string memory _ipTitle
    )
        ERC20(
            string(abi.encodePacked(_creatorName, "'s ", _ipTitle)),
            string(
                abi.encodePacked(_getPrefix(_creatorName), _getPrefix(_ipTitle))
            )
        )
    {
        nftId = _nftId;
        nftContract = _nftContract;
        creator = _creator;
        manager = _manager;
        _creatorName = _creatorName;
        createdAt = block.timestamp;
        pricePerToken = _pricePerToken;

        _mint(_creator, _totalSupply);
        hasHeld[_creator] = true;
        totalHolders = 1;
    }

    function _getPrefix(
        string memory _name
    ) internal pure returns (string memory) {
        bytes memory nameBytes = bytes(_name);
        if (nameBytes.length == 0) return "UNK";

        uint256 length = nameBytes.length > 3 ? 3 : nameBytes.length;
        bytes memory prefix = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            prefix[i] = nameBytes[i];
        }

        return string(prefix);
    }

    function updatePrice(uint256 newPrice) external {
        require(msg.sender == creator, "Only creator");
        require(newPrice > 0, "Price must be > 0");
        pricePerToken = newPrice;
        emit PriceUpdated(newPrice);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);

        if (from != address(0) && to != address(0)) {
            uint256 volume = (value * pricePerToken) / 10 ** 18;
            totalTradingVolume += volume;

            if (!hasHeld[to] && balanceOf(to) > 0) {
                hasHeld[to] = true;
                totalHolders++;
            }

            emit TokenTraded(from, to, value);
        }
    }

    function getValueMetrics()
        external
        view
        returns (
            uint256 currentPrice,
            uint256 tradingVolume,
            uint256 uniqueHolders,
            uint256 marketCap
        )
    {
        return (
            pricePerToken,
            totalTradingVolume,
            totalHolders,
            (totalSupply() * pricePerToken) / 10 ** 18
        );
    }

    function creatorName() external view returns (string memory) {
        return _creatorName;
    }

    function ipMetadata() external view returns (string memory) {
        return _ipMetadata;
    }

    function updateMetadata(string calldata newMetadata) external {
        require(msg.sender == manager, "Only manager");
        _ipMetadata = newMetadata;
    }
}

/**
 * @title WrappedIPManager
 * @dev PVM-optimized IP wrapping manager with ADR integration
 * Memory-efficient design for Polkadot Virtual Machine
 */
contract WrappedIPManager is
    AccessControl,
    ReentrancyGuard,
    Pausable,
    IERC721Receiver
{
    bytes32 public constant IP_MANAGER_ROLE = keccak256("IP_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    SLAWToken public immutable slawToken;
    address public treasuryCore;
    address public disputeResolver; // ADR integration

    // Optimized structs for PVM memory constraints
    struct CreatorProfile {
        string displayName;
        uint256 totalWrappedIPs;
        uint256 totalValueCreated;
        bool isVerified;
        uint256 joinedAt;
    }

    struct WrappedIPInfo {
        address tokenAddress;
        uint256 nftId;
        address nftContract;
        address creator;
        uint256 totalSupply;
        uint256 initialPrice;
        bool isActive;
        uint256 createdAt;
    }

    // Storage mappings
    mapping(bytes32 => WrappedIPInfo) public wrappedIPs;
    mapping(address => bytes32) public tokenToIPId;
    mapping(address => bytes32[]) public creatorIPs;
    mapping(address => CreatorProfile) public creatorProfiles;
    mapping(address => bool) public supportedNFTContracts;

    // Lightweight creator ranking
    address[] public topCreators;
    mapping(address => uint256) public creatorRankings;

    uint256 public totalWrappedIPs;
    uint256 public totalValueLocked;

    // Events
    event CreatorProfileCreated(address indexed creator, string displayName);
    event CreatorVerified(address indexed creator, bool verified);
    event IPWrapped(
        bytes32 indexed ipId,
        address indexed tokenAddress,
        address indexed creator,
        uint256 totalSupply
    );
    event IPUnwrapped(bytes32 indexed ipId, address indexed recipient);
    event DisputeInitiated(bytes32 indexed ipId, uint256 indexed disputeId);

    constructor(address _admin, address _slawToken, address _treasuryCore) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_treasuryCore != address(0), "Invalid treasury core");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(IP_MANAGER_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);

        slawToken = SLAWToken(_slawToken);
        treasuryCore = _treasuryCore;
    }

    // ===== CREATOR PROFILE MANAGEMENT =====

    function createCreatorProfile(string calldata displayName) external {
        require(bytes(displayName).length > 0, "Display name required");
        require(bytes(displayName).length <= 50, "Display name too long");

        CreatorProfile storage profile = creatorProfiles[msg.sender];
        bool isNew = bytes(profile.displayName).length == 0;

        profile.displayName = displayName;

        if (isNew) {
            profile.joinedAt = block.timestamp;
            profile.totalWrappedIPs = 0;
            profile.totalValueCreated = 0;
            profile.isVerified = false;

            emit CreatorProfileCreated(msg.sender, displayName);
        }
    }

    function verifyCreator(
        address creator,
        bool verified
    ) external onlyRole(IP_MANAGER_ROLE) {
        require(
            bytes(creatorProfiles[creator].displayName).length > 0,
            "Creator profile not found"
        );
        creatorProfiles[creator].isVerified = verified;
        emit CreatorVerified(creator, verified);
    }

    // ===== IP WRAPPING FUNCTIONS =====

    function wrapIP(
        address nftContract,
        uint256 nftId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string calldata ipTitle
    ) external nonReentrant whenNotPaused returns (address tokenAddress) {
        // Input validation
        require(
            supportedNFTContracts[nftContract],
            "NFT contract not supported"
        );
        require(totalSupply > 0, "Total supply must be > 0");
        require(pricePerToken > 0, "Price must be > 0");
        require(bytes(ipTitle).length > 0, "IP title required");

        bytes32 ipId = keccak256(abi.encodePacked(nftContract, nftId));
        require(
            wrappedIPs[ipId].tokenAddress == address(0),
            "IP already wrapped"
        );
        require(
            IERC721(nftContract).ownerOf(nftId) == msg.sender,
            "Not NFT owner"
        );
        require(
            bytes(creatorProfiles[msg.sender].displayName).length > 0,
            "Creator profile required"
        );

        // Get creator name (separate call to avoid stack too deep)
        string memory creatorName = creatorProfiles[msg.sender].displayName;

        // Transfer NFT to this contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), nftId);

        // Deploy token (separate function to avoid stack too deep)
        tokenAddress = _deployWrappedToken(
            nftId,
            nftContract,
            msg.sender,
            totalSupply,
            pricePerToken,
            creatorName,
            ipTitle
        );

        // Store wrapped IP info
        wrappedIPs[ipId] = WrappedIPInfo({
            tokenAddress: tokenAddress,
            nftId: nftId,
            nftContract: nftContract,
            creator: msg.sender,
            totalSupply: totalSupply,
            initialPrice: pricePerToken,
            isActive: true,
            createdAt: block.timestamp
        });

        // Update mappings and metrics
        _updateWrappingMetrics(ipId, msg.sender, totalSupply, pricePerToken);

        emit IPWrapped(ipId, tokenAddress, msg.sender, totalSupply);
    }

    // Separate function to avoid stack too deep
    function _deployWrappedToken(
        uint256 nftId,
        address nftContract,
        address creator,
        uint256 totalSupply,
        uint256 pricePerToken,
        string memory creatorName,
        string memory ipTitle
    ) internal returns (address) {
        return
            address(
                new PersonalizedWrappedIPToken(
                    nftId,
                    nftContract,
                    creator,
                    address(this),
                    totalSupply,
                    pricePerToken,
                    creatorName,
                    ipTitle
                )
            );
    }

    // Separate function to avoid stack too deep
    function _updateWrappingMetrics(
        bytes32 ipId,
        address creator,
        uint256 totalSupply,
        uint256 pricePerToken
    ) internal {
        tokenToIPId[address(wrappedIPs[ipId].tokenAddress)] = ipId;
        creatorIPs[creator].push(ipId);

        // Update creator metrics
        CreatorProfile storage profile = creatorProfiles[creator];
        profile.totalWrappedIPs++;

        uint256 initialValue = (totalSupply * pricePerToken) / 10 ** 18;
        profile.totalValueCreated += initialValue;
        totalValueLocked += initialValue;
        totalWrappedIPs++;

        // Update creator rankings (simplified for PVM)
        _updateCreatorRankings(creator);
    }

    function unwrapIP(bytes32 ipId) external nonReentrant whenNotPaused {
        WrappedIPInfo storage ipInfo = wrappedIPs[ipId];
        require(ipInfo.isActive, "IP not active");
        require(ipInfo.creator == msg.sender, "Only creator can unwrap");

        PersonalizedWrappedIPToken wrappedToken = PersonalizedWrappedIPToken(
            ipInfo.tokenAddress
        );
        require(
            wrappedToken.balanceOf(msg.sender) == ipInfo.totalSupply,
            "Must own all tokens"
        );

        // Burn tokens and return NFT
        IERC20(ipInfo.tokenAddress).transferFrom(
            msg.sender,
            address(this),
            ipInfo.totalSupply
        );
        IERC721(ipInfo.nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            ipInfo.nftId
        );

        // Update state
        ipInfo.isActive = false;
        _updateUnwrappingMetrics(
            msg.sender,
            ipInfo.totalSupply,
            ipInfo.initialPrice
        );

        emit IPUnwrapped(ipId, msg.sender);
    }

    function _updateUnwrappingMetrics(
        address creator,
        uint256 totalSupply,
        uint256 initialPrice
    ) internal {
        CreatorProfile storage profile = creatorProfiles[creator];
        if (profile.totalWrappedIPs > 0) {
            profile.totalWrappedIPs--;
        }

        uint256 valueReduction = (totalSupply * initialPrice) / 10 ** 18;
        if (profile.totalValueCreated >= valueReduction) {
            profile.totalValueCreated -= valueReduction;
        }
        if (totalValueLocked >= valueReduction) {
            totalValueLocked -= valueReduction;
        }
    }

    // ===== ADR INTEGRATION =====

    function setDisputeResolver(
        address _disputeResolver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_disputeResolver != address(0), "Invalid dispute resolver");
        disputeResolver = _disputeResolver;
    }

    function initiateDispute(
        bytes32 ipId,
        address defendant,
        uint8 disputeType,
        string calldata description,
        uint256 claimedDamages
    ) external nonReentrant returns (uint256 disputeId) {
        require(disputeResolver != address(0), "Dispute resolver not set");
        require(wrappedIPs[ipId].tokenAddress != address(0), "IP not found");

        // Call dispute resolver contract
        (bool success, bytes memory data) = disputeResolver.call(
            abi.encodeWithSignature(
                "fileDispute(uint8,address,uint256,address,string,string,uint256)",
                disputeType,
                defendant,
                uint256(ipId),
                address(this),
                "IP Dispute",
                description,
                claimedDamages
            )
        );

        require(success, "Failed to initiate dispute");
        disputeId = abi.decode(data, (uint256));

        emit DisputeInitiated(ipId, disputeId);
    }

    // ===== CREATOR RANKINGS (Simplified for PVM) =====

    function _updateCreatorRankings(address creator) internal {
        uint256 currentRank = creatorRankings[creator];

        if (currentRank == 0) {
            topCreators.push(creator);
            creatorRankings[creator] = topCreators.length;
        }

        // Simple bubble sort for top 10 only (PVM memory constraints)
        _sortTopCreators();
    }

    function _sortTopCreators() internal {
        uint256 length = topCreators.length;
        if (length <= 1) return;

        uint256 sortLength = length > 10 ? 10 : length;

        for (uint256 i = 0; i < sortLength - 1; i++) {
            for (uint256 j = 0; j < sortLength - i - 1; j++) {
                if (
                    creatorProfiles[topCreators[j]].totalValueCreated <
                    creatorProfiles[topCreators[j + 1]].totalValueCreated
                ) {
                    address temp = topCreators[j];
                    topCreators[j] = topCreators[j + 1];
                    topCreators[j + 1] = temp;
                }
            }
        }
    }

    // ===== VIEW FUNCTIONS =====

    function getCreatorProfile(
        address creator
    ) external view returns (CreatorProfile memory) {
        return creatorProfiles[creator];
    }

    function getTopCreators(
        uint256 limit
    )
        external
        view
        returns (
            address[] memory creators,
            string[] memory names,
            uint256[] memory values
        )
    {
        uint256 length = topCreators.length;
        if (length == 0) {
            return (new address[](0), new string[](0), new uint256[](0));
        }

        uint256 resultLength = limit > length ? length : limit;
        creators = new address[](resultLength);
        names = new string[](resultLength);
        values = new uint256[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            address creator = topCreators[i];
            creators[i] = creator;
            names[i] = creatorProfiles[creator].displayName;
            values[i] = creatorProfiles[creator].totalValueCreated;
        }
    }

    function getIPId(
        address nftContract,
        uint256 nftId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(nftContract, nftId));
    }

    function getWrappedIPInfo(
        bytes32 ipId
    ) external view returns (WrappedIPInfo memory) {
        return wrappedIPs[ipId];
    }

    function getSystemMetrics()
        external
        view
        returns (
            uint256 totalWrapped,
            uint256 valueLockedSLAW,
            uint256 totalCreators
        )
    {
        return (totalWrappedIPs, totalValueLocked, topCreators.length);
    }

    // ===== NFT CONTRACT MANAGEMENT =====

    function setSupportedNFTContract(
        address nftContract,
        bool supported
    ) external onlyRole(IP_MANAGER_ROLE) {
        require(nftContract != address(0), "Invalid NFT contract");
        supportedNFTContracts[nftContract] = supported;
    }

    function batchAddSupportedNFTContracts(
        address[] calldata nftContracts
    ) external onlyRole(IP_MANAGER_ROLE) {
        require(nftContracts.length <= 10, "Too many contracts"); // PVM limit

        for (uint256 i = 0; i < nftContracts.length; i++) {
            require(nftContracts[i] != address(0), "Invalid NFT contract");
            supportedNFTContracts[nftContracts[i]] = true;
        }
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(IP_MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(IP_MANAGER_ROLE) {
        _unpause();
    }

    function updateTreasuryCore(
        address newTreasuryCore
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasuryCore != address(0), "Invalid treasury address");
        _revokeRole(TREASURY_ROLE, treasuryCore);
        treasuryCore = newTreasuryCore;
        _grantRole(TREASURY_ROLE, newTreasuryCore);
    }

    function emergencyRecoverNFT(
        address nftContract,
        uint256 nftId,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        IERC721(nftContract).safeTransferFrom(address(this), to, nftId);
    }

    // ===== IERC721Receiver IMPLEMENTATION =====

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
