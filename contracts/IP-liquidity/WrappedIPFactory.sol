// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ISoftlawTreasury.sol";

/**
 * @title WrappedIPToken
 * @dev ERC20 token backed by an NFT representing intellectual property
 */
contract WrappedIPToken is ERC20, Ownable {
    struct IPDetails {
        uint256 nftId;
        address nftContract;
        address creator;
        uint256 totalSupply;
        uint256 circulatingSupply;
        string metadata;
        bool isRedeemable;
    }

    IPDetails public ipDetails;
    address public treasury;
    
    // Redemption tracking
    mapping(address => uint256) public redemptionRequests;
    mapping(address => uint256) public redemptionTimestamps;
    uint256 public constant REDEMPTION_DELAY = 7 days;

    event RedemptionStarted(address indexed user, uint256 amount);
    event RedemptionCompleted(address indexed user, uint256 amount);
    event MetadataUpdated(string newMetadata);

    constructor(
        uint256 _nftId,
        address _nftContract,
        address _creator,
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        string memory _metadata,
        address _treasury
    ) ERC20(_name, _symbol) Ownable(_treasury) {
        ipDetails = IPDetails({
            nftId: _nftId,
            nftContract: _nftContract,
            creator: _creator,
            totalSupply: _totalSupply,
            circulatingSupply: 0,
            metadata: _metadata,
            isRedeemable: false
        });
        
        treasury = _treasury;
        
        // Mint initial supply to creator
        _mint(_creator, _totalSupply);
        ipDetails.circulatingSupply = _totalSupply;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(ipDetails.circulatingSupply + amount <= ipDetails.totalSupply, "Exceeds max supply");
        _mint(to, amount);
        ipDetails.circulatingSupply += amount;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        ipDetails.circulatingSupply -= amount;
    }

    function startRedemption(uint256 amount) external {
        require(ipDetails.isRedeemable, "Redemption not enabled");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(redemptionRequests[msg.sender] == 0, "Redemption already pending");
        
        redemptionRequests[msg.sender] = amount;
        redemptionTimestamps[msg.sender] = block.timestamp;
        
        // Lock tokens during redemption period
        _transfer(msg.sender, address(this), amount);
        
        emit RedemptionStarted(msg.sender, amount);
    }

    function completeRedemption() external {
        uint256 amount = redemptionRequests[msg.sender];
        require(amount > 0, "No redemption request");
        require(
            block.timestamp >= redemptionTimestamps[msg.sender] + REDEMPTION_DELAY,
            "Redemption delay not met"
        );

        redemptionRequests[msg.sender] = 0;
        redemptionTimestamps[msg.sender] = 0;
        
        // Burn the tokens
        _burn(address(this), amount);
        ipDetails.circulatingSupply -= amount;
        
        // If all tokens are redeemed, transfer NFT back to user
        if (ipDetails.circulatingSupply == 0) {
            IERC721(ipDetails.nftContract).transferFrom(treasury, msg.sender, ipDetails.nftId);
        }
        
        emit RedemptionCompleted(msg.sender, amount);
    }

    function setRedeemable(bool _redeemable) external onlyOwner {
        ipDetails.isRedeemable = _redeemable;
    }

    function updateMetadata(string memory newMetadata) external onlyOwner {
        ipDetails.metadata = newMetadata;
        emit MetadataUpdated(newMetadata);
    }

    // View functions
    function getIPDetails() external view returns (IPDetails memory) {
        return ipDetails;
    }

    function getNFTId() external view returns (uint256) {
        return ipDetails.nftId;
    }

    function getNFTContract() external view returns (address) {
        return ipDetails.nftContract;
    }

    function getCreator() external view returns (address) {
        return ipDetails.creator;
    }

    function isRedeemable() external view returns (bool) {
        return ipDetails.isRedeemable;
    }
}

/**
 * @title WrappedIPFactory
 * @dev Factory for creating wrapped IP tokens
 */
contract WrappedIPFactory is Ownable, ReentrancyGuard {
    mapping(bytes32 => address) public wrappedTokens; // keccak256(nftContract, nftId) => token address
    mapping(address => bool) public isValidWrappedToken;
    address[] public allWrappedTokens;
    
    address public treasury;
    uint256 public creationFee = 0.01 ether; // Fee in native currency
    
    event WrappedIPTokenCreated(
        address indexed tokenAddress,
        uint256 indexed nftId,
        address indexed nftContract,
        address creator
    );
    
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    constructor(address _treasury, address _owner) Ownable(_owner) {
        treasury = _treasury;
    }

    function createWrappedIPToken(
        uint256 nftId,
        address nftContract,
        uint256 totalSupply,
        address creator,
        string memory name,
        string memory symbol,
        string memory metadata
    ) external payable nonReentrant returns (address) {
        require(msg.value >= creationFee, "Insufficient creation fee");
        require(nftContract != address(0), "Invalid NFT contract");
        require(totalSupply > 0, "Total supply must be > 0");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        
        bytes32 key = keccak256(abi.encodePacked(nftContract, nftId));
        require(wrappedTokens[key] == address(0), "Token already exists");
        
        // Create new wrapped IP token
        WrappedIPToken newToken = new WrappedIPToken(
            nftId,
            nftContract,
            creator,
            totalSupply,
            name,
            symbol,
            metadata,
            treasury
        );
        
        address tokenAddress = address(newToken);
        
        // Register the token
        wrappedTokens[key] = tokenAddress;
        isValidWrappedToken[tokenAddress] = true;
        allWrappedTokens.push(tokenAddress);
        
        // Transfer creation fee to treasury
        if (msg.value > 0) {
            payable(treasury).transfer(msg.value);
        }
        
        emit WrappedIPTokenCreated(tokenAddress, nftId, nftContract, creator);
        
        return tokenAddress;
    }

    function getWrappedToken(uint256 nftId, address nftContract) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(nftContract, nftId));
        return wrappedTokens[key];
    }

    function getAllWrappedTokens() external view returns (address[] memory) {
        return allWrappedTokens;
    }

    function getWrappedTokensCount() external view returns (uint256) {
        return allWrappedTokens.length;
    }

    function setCreationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = creationFee;
        creationFee = newFee;
        emit CreationFeeUpdated(oldFee, newFee);
    }

    function updateTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    // Emergency function to recover stuck ETH
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
