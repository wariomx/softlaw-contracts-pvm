// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SLAWToken.sol";

/**
 * @title PersonalizedWrappedIPToken
 * @dev Individual ERC20 token representing fractional ownership of an NFT
 * Features personalized naming based on creator
 */
contract PersonalizedWrappedIPToken is ERC20 {
    uint256 public immutable nftId;
    address public immutable nftContract;
    address public immutable creator;
    address public immutable manager;
    string public ipMetadata;
    string public creatorName;
    uint256 public immutable createdAt;
    uint256 public pricePerToken; // Price in SLAW
    
    // Value metrics
    uint256 public totalTradingVolume;
    uint256 public totalHolders;
    mapping(address => bool) public hasHeld; // Track unique holders
    
    event TokenTraded(address indexed from, address indexed to, uint256 amount, uint256 volume);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event ValueMetricsUpdated(uint256 volume, uint256 holders);
    
    constructor(
        uint256 _nftId,
        address _nftContract,
        address _creator,
        address _manager,
        uint256 _totalSupply,
        uint256 _pricePerToken,
        string memory _creatorName,
        string memory _ipTitle,
        string memory _metadata
    ) ERC20(
        string(abi.encodePacked(_creatorName, "'s ", _ipTitle)),
        string(abi.encodePacked(_getCreatorPrefix(_creatorName), _getTitlePrefix(_ipTitle)))
    ) {
        nftId = _nftId;
        nftContract = _nftContract;
        creator = _creator;
        manager = _manager;
        creatorName = _creatorName;
        ipMetadata = _metadata;
        createdAt = block.timestamp;
        pricePerToken = _pricePerToken;
        
        // Mint total supply to creator
        _mint(_creator, _totalSupply);
        
        // Track creator as first holder
        hasHeld[_creator] = true;
        totalHolders = 1;
    }
    
    /**
     * @dev Get creator prefix for symbol (first 3 chars)
     */
    function _getCreatorPrefix(string memory _creatorName) internal pure returns (string memory) {
        bytes memory nameBytes = bytes(_creatorName);
        if (nameBytes.length == 0) return "UNK";
        
        uint256 length = nameBytes.length > 3 ? 3 : nameBytes.length;
        bytes memory prefix = new bytes(length);
        
        for (uint256 i = 0; i < length; i++) {
            prefix[i] = nameBytes[i];
        }
        
        return string(prefix);
    }
    
    /**
     * @dev Get title prefix for symbol
     */
    function _getTitlePrefix(string memory _ipTitle) internal pure returns (string memory) {
        bytes memory titleBytes = bytes(_ipTitle);
        if (titleBytes.length == 0) return "IP";
        
        uint256 length = titleBytes.length > 2 ? 2 : titleBytes.length;
        bytes memory prefix = new bytes(length);
        
        for (uint256 i = 0; i < length; i++) {
            prefix[i] = titleBytes[i];
        }
        
        return string(prefix);
    }
    
    /**
     * @dev Update metadata (only manager)
     */
    function updateMetadata(string calldata newMetadata) external {
        require(msg.sender == manager, "Only manager can update");
        ipMetadata = newMetadata;
    }
    
    /**
     * @dev Update price per token (only creator)
     */
    function updatePrice(uint256 newPrice) external {
        require(msg.sender == creator, "Only creator can update price");
        require(newPrice > 0, "Price must be > 0");
        
        uint256 oldPrice = pricePerToken;
        pricePerToken = newPrice;
        
        emit PriceUpdated(oldPrice, newPrice);
    }
    
    /**
     * @dev Override transfer to track metrics
     */
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        
        // Skip if minting or burning
        if (from == address(0) || to == address(0)) return;
        
        // Track trading volume (approximate)
        uint256 volume = (value * pricePerToken) / 10**18;
        totalTradingVolume += volume;
        
        // Track new holders
        if (!hasHeld[to] && balanceOf(to) > 0) {
            hasHeld[to] = true;
            totalHolders++;
        }
        
        emit TokenTraded(from, to, value, volume);
        emit ValueMetricsUpdated(totalTradingVolume, totalHolders);
    }
    
    /**
     * @dev Get token value metrics
     */
    function getValueMetrics() external view returns (
        uint256 currentPrice,
        uint256 tradingVolume,
        uint256 uniqueHolders,
        uint256 marketCap,
        uint256 age
    ) {
        currentPrice = pricePerToken;
        tradingVolume = totalTradingVolume;
        uniqueHolders = totalHolders;
        marketCap = (totalSupply() * pricePerToken) / 10**18;
        age = block.timestamp - createdAt;
    }
    
    /**
     * @dev Get creator royalties info
     */
    function getCreatorInfo() external view returns (
        address creatorAddress,
        string memory creatorDisplayName,
        uint256 creatorBalance,
        uint256 creatorPercentage
    ) {
        creatorAddress = creator;
        creatorDisplayName = creatorName;
        creatorBalance = balanceOf(creator);
        creatorPercentage = (creatorBalance * 100) / totalSupply();
    }
}

/**
 * @title WrappedIPManager
 * @dev Manages wrapping of copyright NFTs into personalized ERC20 tokens
 * Features:
 * - NFT to ERC20 conversion with creator branding
 * - Personalized token names and symbols
 * - Creator value tracking
 * - PVM-optimized lightweight design
 */
contract WrappedIPManager is AccessControl, ReentrancyGuard, Pausable, IERC721Receiver {
    // Roles
    bytes32 public constant IP_MANAGER_ROLE = keccak256("IP_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // System contracts
    SLAWToken public immutable slawToken;
    address public treasuryCore;
    
    // Creator profiles
    struct CreatorProfile {
        string displayName;
        string bio;
        string avatar;
        uint256 totalWrappedIPs;
        uint256 totalValueCreated;
        bool isVerified;
        uint256 joinedAt;
    }
    
    // Wrapped IP tracking
    struct WrappedIPInfo {
        address tokenAddress;
        uint256 nftId;
        address nftContract;
        address creator;
        string creatorName;
        uint256 totalSupply;
        uint256 initialPrice; // Initial price in SLAW
        bool isActive;
        uint256 createdAt;
        string ipTitle;
        string category;
        string metadata;
    }
    
    // State mappings
    mapping(bytes32 => WrappedIPInfo) public wrappedIPs; // keccak256(nftContract, nftId) => info
    mapping(address => bytes32) public tokenToIPId; // token address => IP ID
    mapping(address => bytes32[]) public creatorIPs; // creator => array of IP IDs
    mapping(address => CreatorProfile) public creatorProfiles;
    mapping(address => bool) public supportedNFTContracts;
    
    // Creator leaderboard
    address[] public topCreators;
    mapping(address => uint256) public creatorRankings; // creator => ranking position
    
    // System metrics
    uint256 public totalWrappedIPs;
    uint256 public totalTokensCreated;
    uint256 public totalValueLocked;
    
    // Events
    event CreatorProfileCreated(address indexed creator, string displayName);
    event CreatorProfileUpdated(address indexed creator, string displayName);
    event CreatorVerified(address indexed creator, bool verified);
    
    event IPWrapped(
        bytes32 indexed ipId,
        address indexed tokenAddress,
        uint256 indexed nftId,
        address nftContract,
        address creator,
        string creatorName,
        string ipTitle,
        uint256 totalSupply,
        uint256 initialPrice
    );
    
    event IPUnwrapped(
        bytes32 indexed ipId,
        address indexed tokenAddress,
        address indexed recipient
    );
    
    event CreatorValueUpdated(
        address indexed creator,
        uint256 totalWrappedIPs,
        uint256 totalValueCreated
    );
    
    event IPMetadataUpdated(bytes32 indexed ipId, string newMetadata);
    event IPPriceUpdated(bytes32 indexed ipId, uint256 newPrice);
    event IPStatusUpdated(bytes32 indexed ipId, bool isActive);
    event NFTContractSupported(address indexed nftContract, bool supported);

    constructor(
        address _admin,
        address _slawToken,
        address _treasuryCore
    ) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_treasuryCore != address(0), "Invalid treasury core");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(IP_MANAGER_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);
        
        slawToken = SLAWToken(_slawToken);
        treasuryCore = _treasuryCore;
    }

    // ===== CREATOR PROFILE MANAGEMENT =====

    /**
     * @dev Create or update creator profile
     * @param displayName Creator's display name
     * @param bio Creator bio
     * @param avatar Avatar URL
     */
    function createCreatorProfile(
        string calldata displayName,
        string calldata bio,
        string calldata avatar
    ) external {
        require(bytes(displayName).length > 0, "Display name required");
        require(bytes(displayName).length <= 50, "Display name too long");
        
        CreatorProfile storage profile = creatorProfiles[msg.sender];
        bool isNew = bytes(profile.displayName).length == 0;
        
        profile.displayName = displayName;
        profile.bio = bio;
        profile.avatar = avatar;
        
        if (isNew) {
            profile.joinedAt = block.timestamp;
            profile.totalWrappedIPs = 0;
            profile.totalValueCreated = 0;
            profile.isVerified = false;
            
            emit CreatorProfileCreated(msg.sender, displayName);
        } else {
            emit CreatorProfileUpdated(msg.sender, displayName);
        }
    }

    /**
     * @dev Verify creator (admin only)
     * @param creator Creator address
     * @param verified Verification status
     */
    function verifyCreator(address creator, bool verified) external onlyRole(IP_MANAGER_ROLE) {
        require(bytes(creatorProfiles[creator].displayName).length > 0, "Creator profile not found");
        
        creatorProfiles[creator].isVerified = verified;
        
        emit CreatorVerified(creator, verified);
    }

    // ===== IP WRAPPING FUNCTIONS =====

    /**
     * @dev Wrap a copyright NFT into personalized ERC20 tokens
     * @param nftContract Address of the NFT contract
     * @param nftId Token ID of the NFT
     * @param totalSupply Total supply of wrapped tokens to create
     * @param pricePerToken Price per wrapped token in SLAW
     * @param ipTitle Title of the IP work
     * @param category Category (music, art, literature, etc.)
     * @param metadata Additional metadata for the wrapped IP
     */
    function wrapIP(
        address nftContract,
        uint256 nftId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string calldata ipTitle,
        string calldata category,
        string calldata metadata
    ) external nonReentrant whenNotPaused returns (address tokenAddress) {
        require(supportedNFTContracts[nftContract], "NFT contract not supported");
        require(totalSupply > 0, "Total supply must be > 0");
        require(pricePerToken > 0, "Price must be > 0");
        require(bytes(ipTitle).length > 0, "IP title required");
        require(bytes(category).length > 0, "Category required");
        
        bytes32 ipId = keccak256(abi.encodePacked(nftContract, nftId));
        require(wrappedIPs[ipId].tokenAddress == address(0), "IP already wrapped");
        
        // Verify NFT ownership
        require(IERC721(nftContract).ownerOf(nftId) == msg.sender, "Not NFT owner");
        
        // Ensure creator has profile
        require(bytes(creatorProfiles[msg.sender].displayName).length > 0, "Creator profile required");
        
        string memory creatorName = creatorProfiles[msg.sender].displayName;
        
        // Transfer NFT to this contract (treasury holds the asset)
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), nftId);
        
        // Deploy personalized wrapped IP token
        tokenAddress = address(new PersonalizedWrappedIPToken(
            nftId,
            nftContract,
            msg.sender,
            address(this),
            totalSupply,
            pricePerToken,
            creatorName,
            ipTitle,
            metadata
        ));
        
        // Store wrapped IP info
        wrappedIPs[ipId] = WrappedIPInfo({
            tokenAddress: tokenAddress,
            nftId: nftId,
            nftContract: nftContract,
            creator: msg.sender,
            creatorName: creatorName,
            totalSupply: totalSupply,
            initialPrice: pricePerToken,
            isActive: true,
            createdAt: block.timestamp,
            ipTitle: ipTitle,
            category: category,
            metadata: metadata
        });
        
        tokenToIPId[tokenAddress] = ipId;
        creatorIPs[msg.sender].push(ipId);
        
        // Update creator metrics
        CreatorProfile storage profile = creatorProfiles[msg.sender];
        profile.totalWrappedIPs++;
        
        uint256 initialValue = (totalSupply * pricePerToken) / 10**18;
        profile.totalValueCreated += initialValue;
        totalValueLocked += initialValue;
        
        totalWrappedIPs++;
        totalTokensCreated += totalSupply;
        
        // Update creator rankings
        _updateCreatorRankings(msg.sender);
        
        emit IPWrapped(
            ipId, 
            tokenAddress, 
            nftId, 
            nftContract, 
            msg.sender, 
            creatorName, 
            ipTitle, 
            totalSupply, 
            pricePerToken
        );
        
        emit CreatorValueUpdated(
            msg.sender,
            profile.totalWrappedIPs,
            profile.totalValueCreated
        );
    }

    /**
     * @dev Unwrap IP tokens back to original NFT (requires all tokens)
     * @param ipId ID of the wrapped IP
     */
    function unwrapIP(bytes32 ipId) external nonReentrant whenNotPaused {
        WrappedIPInfo storage ipInfo = wrappedIPs[ipId];
        require(ipInfo.isActive, "IP not active");
        require(ipInfo.creator == msg.sender, "Only creator can unwrap");
        
        PersonalizedWrappedIPToken wrappedToken = PersonalizedWrappedIPToken(ipInfo.tokenAddress);
        
        // Verify all tokens are held by creator
        require(wrappedToken.balanceOf(msg.sender) == ipInfo.totalSupply, "Must own all tokens");
        
        // Burn all wrapped tokens (transfer to this contract)
        IERC20(ipInfo.tokenAddress).transferFrom(msg.sender, address(this), ipInfo.totalSupply);
        
        // Return original NFT
        IERC721(ipInfo.nftContract).safeTransferFrom(address(this), msg.sender, ipInfo.nftId);
        
        // Deactivate wrapped IP
        ipInfo.isActive = false;
        
        // Update creator metrics
        CreatorProfile storage profile = creatorProfiles[msg.sender];
        if (profile.totalWrappedIPs > 0) {
            profile.totalWrappedIPs--;
        }
        
        uint256 valueReduction = (ipInfo.totalSupply * ipInfo.initialPrice) / 10**18;
        if (profile.totalValueCreated >= valueReduction) {
            profile.totalValueCreated -= valueReduction;
        }
        if (totalValueLocked >= valueReduction) {
            totalValueLocked -= valueReduction;
        }
        
        emit IPUnwrapped(ipId, ipInfo.tokenAddress, msg.sender);
        emit CreatorValueUpdated(msg.sender, profile.totalWrappedIPs, profile.totalValueCreated);
    }

    // ===== CREATOR RANKINGS =====

    /**
     * @dev Update creator rankings based on value created
     * @param creator Creator address to update
     */
    function _updateCreatorRankings(address creator) internal {
        // Simple ranking system - in production, use more sophisticated algorithm
        uint256 currentRank = creatorRankings[creator];
        
        if (currentRank == 0) {
            // New creator
            topCreators.push(creator);
            creatorRankings[creator] = topCreators.length;
        }
        
        // Bubble sort for top 10 (simple implementation for demo)
        _sortTopCreators();
    }
    
    /**
     * @dev Simple bubble sort for top creators (PVM memory-safe)
     */
    function _sortTopCreators() internal {
        uint256 length = topCreators.length;
        if (length <= 1) return;
        
        // Limit sorting to top 20 for PVM memory constraints
        uint256 sortLength = length > 20 ? 20 : length;
        
        for (uint256 i = 0; i < sortLength - 1; i++) {
            for (uint256 j = 0; j < sortLength - i - 1; j++) {
                if (creatorProfiles[topCreators[j]].totalValueCreated < 
                    creatorProfiles[topCreators[j + 1]].totalValueCreated) {
                    
                    // Swap
                    address temp = topCreators[j];
                    topCreators[j] = topCreators[j + 1];
                    topCreators[j + 1] = temp;
                    
                    // Update rankings
                    creatorRankings[topCreators[j]] = j + 1;
                    creatorRankings[topCreators[j + 1]] = j + 2;
                }
            }
        }
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @dev Get creator profile
     * @param creator Creator address
     */
    function getCreatorProfile(address creator) external view returns (CreatorProfile memory) {
        return creatorProfiles[creator];
    }

    /**
     * @dev Get top creators
     * @param limit Number of top creators to return
     */
    function getTopCreators(uint256 limit) external view returns (
        address[] memory creators,
        string[] memory names,
        uint256[] memory values,
        bool[] memory verified
    ) {
        uint256 length = topCreators.length;
        if (length == 0) {
            return (new address[](0), new string[](0), new uint256[](0), new bool[](0));
        }
        
        uint256 resultLength = limit > length ? length : limit;
        creators = new address[](resultLength);
        names = new string[](resultLength);
        values = new uint256[](resultLength);
        verified = new bool[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            address creator = topCreators[i];
            creators[i] = creator;
            names[i] = creatorProfiles[creator].displayName;
            values[i] = creatorProfiles[creator].totalValueCreated;
            verified[i] = creatorProfiles[creator].isVerified;
        }
    }

    /**
     * @dev Get IP ID from NFT contract and token ID
     * @param nftContract NFT contract address
     * @param nftId NFT token ID
     */
    function getIPId(address nftContract, uint256 nftId) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(nftContract, nftId));
    }

    /**
     * @dev Get wrapped IP info by IP ID
     * @param ipId IP ID
     */
    function getWrappedIPInfo(bytes32 ipId) external view returns (WrappedIPInfo memory) {
        return wrappedIPs[ipId];
    }

    /**
     * @dev Get wrapped IP info by token address
     * @param tokenAddress Wrapped IP token address
     */
    function getWrappedIPInfoByToken(address tokenAddress) external view returns (WrappedIPInfo memory) {
        bytes32 ipId = tokenToIPId[tokenAddress];
        return wrappedIPs[ipId];
    }

    /**
     * @dev Get creator's wrapped IPs with enhanced info
     * @param creator Creator address
     */
    function getCreatorIPsDetailed(address creator) external view returns (
        bytes32[] memory ipIds,
        WrappedIPInfo[] memory ipInfos,
        uint256[] memory currentPrices,
        uint256[] memory marketCaps
    ) {
        bytes32[] memory allIPs = creatorIPs[creator];
        uint256 length = allIPs.length;
        
        ipIds = new bytes32[](length);
        ipInfos = new WrappedIPInfo[](length);
        currentPrices = new uint256[](length);
        marketCaps = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            bytes32 ipId = allIPs[i];
            ipIds[i] = ipId;
            ipInfos[i] = wrappedIPs[ipId];
            
            if (wrappedIPs[ipId].isActive) {
                PersonalizedWrappedIPToken token = PersonalizedWrappedIPToken(wrappedIPs[ipId].tokenAddress);
                currentPrices[i] = token.pricePerToken();
                marketCaps[i] = (token.totalSupply() * token.pricePerToken()) / 10**18;
            }
        }
    }

    /**
     * @dev Get system metrics with creator stats
     */
    function getSystemMetrics() external view returns (
        uint256 totalWrapped,
        uint256 totalTokens,
        uint256 valueLockedSLAW,
        uint256 totalCreators,
        uint256 verifiedCreators
    ) {
        totalWrapped = totalWrappedIPs;
        totalTokens = totalTokensCreated;
        valueLockedSLAW = totalValueLocked;
        totalCreators = topCreators.length;
        
        // Count verified creators
        verifiedCreators = 0;
        for (uint256 i = 0; i < topCreators.length; i++) {
            if (creatorProfiles[topCreators[i]].isVerified) {
                verifiedCreators++;
            }
        }
    }

    // ===== NFT CONTRACT MANAGEMENT =====

    /**
     * @dev Add/remove supported NFT contracts
     * @param nftContract NFT contract address
     * @param supported Whether the contract is supported
     */
    function setSupportedNFTContract(
        address nftContract, 
        bool supported
    ) external onlyRole(IP_MANAGER_ROLE) {
        require(nftContract != address(0), "Invalid NFT contract");
        
        supportedNFTContracts[nftContract] = supported;
        
        emit NFTContractSupported(nftContract, supported);
    }

    /**
     * @dev Batch add supported NFT contracts
     * @param nftContracts Array of NFT contract addresses
     */
    function batchAddSupportedNFTContracts(
        address[] calldata nftContracts
    ) external onlyRole(IP_MANAGER_ROLE) {
        require(nftContracts.length <= 20, "Too many contracts"); // PVM memory limit
        
        for (uint256 i = 0; i < nftContracts.length; i++) {
            require(nftContracts[i] != address(0), "Invalid NFT contract");
            supportedNFTContracts[nftContracts[i]] = true;
            emit NFTContractSupported(nftContracts[i], true);
        }
    }

    // ===== TREASURY INTEGRATION =====

    /**
     * @dev Update treasury core address
     * @param newTreasuryCore New treasury core address
     */
    function updateTreasuryCore(address newTreasuryCore) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasuryCore != address(0), "Invalid treasury address");
        
        _revokeRole(TREASURY_ROLE, treasuryCore);
        treasuryCore = newTreasuryCore;
        _grantRole(TREASURY_ROLE, newTreasuryCore);
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(IP_MANAGER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(IP_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @dev Emergency function to recover stuck NFTs
     * @param nftContract NFT contract address
     * @param nftId NFT token ID
     * @param to Recipient address
     */
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
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
