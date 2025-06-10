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
 * @title WrappedIPToken
 * @dev Individual ERC20 token representing fractional ownership of an NFT
 */
contract WrappedIPToken is ERC20 {
    uint256 public immutable nftId;
    address public immutable nftContract;
    address public immutable creator;
    address public immutable manager;
    string public ipMetadata;
    
    constructor(
        uint256 _nftId,
        address _nftContract,
        address _creator,
        address _manager,
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        string memory _metadata
    ) ERC20(_name, _symbol) {
        nftId = _nftId;
        nftContract = _nftContract;
        creator = _creator;
        manager = _manager;
        ipMetadata = _metadata;
        
        // Mint total supply to creator
        _mint(_creator, _totalSupply);
    }
    
    function updateMetadata(string calldata newMetadata) external {
        require(msg.sender == manager, "Only manager can update");
        ipMetadata = newMetadata;
    }
}

/**
 * @title WrappedIPManager
 * @dev Manages wrapping of copyright NFTs into fungible ERC20 tokens
 * Features:
 * - NFT to ERC20 conversion
 * - Metadata management
 * - Creator verification
 * - PVM-optimized lightweight design
 */
contract WrappedIPManager is AccessControl, ReentrancyGuard, Pausable, IERC721Receiver {
    // Roles
    bytes32 public constant IP_MANAGER_ROLE = keccak256("IP_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // System contracts
    SLAWToken public immutable slawToken;
    address public treasuryCore;
    
    // Wrapped IP tracking
    struct WrappedIPInfo {
        address tokenAddress;
        uint256 nftId;
        address nftContract;
        address creator;
        uint256 totalSupply;
        uint256 pricePerToken; // Price in SLAW
        bool isActive;
        uint256 createdAt;
        string metadata;
    }
    
    // State mappings
    mapping(bytes32 => WrappedIPInfo) public wrappedIPs; // keccak256(nftContract, nftId) => info
    mapping(address => bytes32) public tokenToIPId; // token address => IP ID
    mapping(address => bytes32[]) public creatorIPs; // creator => array of IP IDs
    mapping(address => bool) public supportedNFTContracts;
    
    // System metrics
    uint256 public totalWrappedIPs;
    uint256 public totalTokensCreated;
    
    // Events
    event IPWrapped(
        bytes32 indexed ipId,
        address indexed tokenAddress,
        uint256 indexed nftId,
        address nftContract,
        address creator,
        uint256 totalSupply,
        uint256 pricePerToken
    );
    
    event IPUnwrapped(
        bytes32 indexed ipId,
        address indexed tokenAddress,
        address indexed recipient
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

    // ===== IP WRAPPING FUNCTIONS =====

    /**
     * @dev Wrap a copyright NFT into fungible ERC20 tokens
     * @param nftContract Address of the NFT contract
     * @param nftId Token ID of the NFT
     * @param totalSupply Total supply of wrapped tokens to create
     * @param pricePerToken Price per wrapped token in SLAW
     * @param tokenName Name for the wrapped token
     * @param tokenSymbol Symbol for the wrapped token
     * @param metadata Metadata for the wrapped IP
     */
    function wrapIP(
        address nftContract,
        uint256 nftId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string calldata tokenName,
        string calldata tokenSymbol,
        string calldata metadata
    ) external nonReentrant whenNotPaused returns (address tokenAddress) {
        require(supportedNFTContracts[nftContract], "NFT contract not supported");
        require(totalSupply > 0, "Total supply must be > 0");
        require(pricePerToken > 0, "Price must be > 0");
        require(bytes(tokenName).length > 0, "Name required");
        require(bytes(tokenSymbol).length > 0, "Symbol required");
        
        bytes32 ipId = keccak256(abi.encodePacked(nftContract, nftId));
        require(wrappedIPs[ipId].tokenAddress == address(0), "IP already wrapped");
        
        // Verify NFT ownership
        require(IERC721(nftContract).ownerOf(nftId) == msg.sender, "Not NFT owner");
        
        // Transfer NFT to this contract (treasury holds the asset)
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), nftId);
        
        // Deploy wrapped IP token
        tokenAddress = address(new WrappedIPToken(
            nftId,
            nftContract,
            msg.sender,
            address(this),
            totalSupply,
            tokenName,
            tokenSymbol,
            metadata
        ));
        
        // Store wrapped IP info
        wrappedIPs[ipId] = WrappedIPInfo({
            tokenAddress: tokenAddress,
            nftId: nftId,
            nftContract: nftContract,
            creator: msg.sender,
            totalSupply: totalSupply,
            pricePerToken: pricePerToken,
            isActive: true,
            createdAt: block.timestamp,
            metadata: metadata
        });
        
        tokenToIPId[tokenAddress] = ipId;
        creatorIPs[msg.sender].push(ipId);
        totalWrappedIPs++;
        totalTokensCreated += totalSupply;
        
        emit IPWrapped(ipId, tokenAddress, nftId, nftContract, msg.sender, totalSupply, pricePerToken);
    }

    /**
     * @dev Unwrap IP tokens back to original NFT (requires all tokens)
     * @param ipId ID of the wrapped IP
     */
    function unwrapIP(bytes32 ipId) external nonReentrant whenNotPaused {
        WrappedIPInfo storage ipInfo = wrappedIPs[ipId];
        require(ipInfo.isActive, "IP not active");
        require(ipInfo.creator == msg.sender, "Only creator can unwrap");
        
        WrappedIPToken wrappedToken = WrappedIPToken(ipInfo.tokenAddress);
        
        // Verify all tokens are held by creator
        require(wrappedToken.balanceOf(msg.sender) == ipInfo.totalSupply, "Must own all tokens");
        
        // Burn all wrapped tokens
        // Note: In a full implementation, you'd need a burn function in WrappedIPToken
        // For now, we'll transfer tokens to this contract as a form of "burning"
        IERC20(ipInfo.tokenAddress).transferFrom(msg.sender, address(this), ipInfo.totalSupply);
        
        // Return original NFT
        IERC721(ipInfo.nftContract).safeTransferFrom(address(this), msg.sender, ipInfo.nftId);
        
        // Deactivate wrapped IP
        ipInfo.isActive = false;
        
        emit IPUnwrapped(ipId, ipInfo.tokenAddress, msg.sender);
    }

    // ===== IP MANAGEMENT FUNCTIONS =====

    /**
     * @dev Update IP metadata
     * @param ipId ID of the wrapped IP
     * @param newMetadata New metadata
     */
    function updateIPMetadata(
        bytes32 ipId, 
        string calldata newMetadata
    ) external {
        WrappedIPInfo storage ipInfo = wrappedIPs[ipId];
        require(ipInfo.creator == msg.sender || hasRole(IP_MANAGER_ROLE, msg.sender), "Not authorized");
        require(ipInfo.isActive, "IP not active");
        
        ipInfo.metadata = newMetadata;
        
        // Update token metadata too
        WrappedIPToken(ipInfo.tokenAddress).updateMetadata(newMetadata);
        
        emit IPMetadataUpdated(ipId, newMetadata);
    }

    /**
     * @dev Update IP price per token
     * @param ipId ID of the wrapped IP
     * @param newPrice New price per token in SLAW
     */
    function updateIPPrice(bytes32 ipId, uint256 newPrice) external {
        WrappedIPInfo storage ipInfo = wrappedIPs[ipId];
        require(ipInfo.creator == msg.sender, "Only creator can update price");
        require(ipInfo.isActive, "IP not active");
        require(newPrice > 0, "Price must be > 0");
        
        ipInfo.pricePerToken = newPrice;
        
        emit IPPriceUpdated(ipId, newPrice);
    }

    /**
     * @dev Toggle IP active status (admin function)
     * @param ipId ID of the wrapped IP
     * @param isActive New active status
     */
    function toggleIPStatus(bytes32 ipId, bool isActive) external onlyRole(IP_MANAGER_ROLE) {
        WrappedIPInfo storage ipInfo = wrappedIPs[ipId];
        require(ipInfo.tokenAddress != address(0), "IP not found");
        
        ipInfo.isActive = isActive;
        
        emit IPStatusUpdated(ipId, isActive);
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

    // ===== VIEW FUNCTIONS =====

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
     * @dev Get creator's wrapped IPs
     * @param creator Creator address
     */
    function getCreatorIPs(address creator) external view returns (bytes32[] memory) {
        return creatorIPs[creator];
    }

    /**
     * @dev Get creator's wrapped IPs with pagination
     * @param creator Creator address
     * @param offset Starting index
     * @param limit Number of IPs to return
     */
    function getCreatorIPsPaginated(
        address creator, 
        uint256 offset, 
        uint256 limit
    ) external view returns (bytes32[] memory ipIds, WrappedIPInfo[] memory ipInfos) {
        bytes32[] memory allIPs = creatorIPs[creator];
        
        if (offset >= allIPs.length) {
            return (new bytes32[](0), new WrappedIPInfo[](0));
        }
        
        uint256 end = offset + limit;
        if (end > allIPs.length) {
            end = allIPs.length;
        }
        
        uint256 length = end - offset;
        ipIds = new bytes32[](length);
        ipInfos = new WrappedIPInfo[](length);
        
        for (uint256 i = 0; i < length; i++) {
            bytes32 ipId = allIPs[offset + i];
            ipIds[i] = ipId;
            ipInfos[i] = wrappedIPs[ipId];
        }
    }

    /**
     * @dev Check if NFT contract is supported
     * @param nftContract NFT contract address
     */
    function isNFTContractSupported(address nftContract) external view returns (bool) {
        return supportedNFTContracts[nftContract];
    }

    /**
     * @dev Get system metrics
     */
    function getSystemMetrics() external view returns (
        uint256 totalWrapped,
        uint256 totalTokens,
        uint256 activeIPs
    ) {
        // Note: activeIPs would require iteration in a full implementation
        // For PVM optimization, we're returning total wrapped as approximation
        return (totalWrappedIPs, totalTokensCreated, totalWrappedIPs);
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
