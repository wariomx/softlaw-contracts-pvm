// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title OptimizedMarketplaceCore
 * @dev PVM-optimized marketplace for IP trading and licensing
 * Replaces .send/.transfer with secure .call() pattern
 * Memory-efficient design for Polkadot Virtual Machine
 */
contract OptimizedMarketplaceCore is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MARKETPLACE_ADMIN = keccak256("MARKETPLACE_ADMIN");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    address public immutable slawToken;
    address public treasuryCore;
    
    // Platform fee (basis points)
    uint256 public constant PLATFORM_FEE = 250; // 2.5%
    uint256 public constant ROYALTY_FEE = 500;  // 5% max royalty
    uint256 public constant BASIS_POINTS = 10000;
    
    // Listing types
    enum ListingType {
        FIXED_PRICE,
        AUCTION,
        LICENSE
    }
    
    enum ListingStatus {
        ACTIVE,
        SOLD,
        CANCELLED,
        EXPIRED
    }
    
    // Optimized listing structure for PVM
    struct Listing {
        uint256 id;
        ListingType listingType;
        ListingStatus status;
        address seller;
        address tokenContract;
        uint256 tokenId;
        uint256 price; // In SLAW
        uint256 endTime;
        uint256 createdAt;
        address highestBidder;
        uint256 highestBid;
        uint256 royaltyPercentage;
        address royaltyRecipient;
    }
    
    // License terms for IP licensing
    struct LicenseTerms {
        uint256 duration; // In seconds
        uint256 price; // In SLAW
        bool isExclusive;
        bool isCommercial;
        string[] allowedUses;
        string[] restrictions;
    }
    
    // Storage
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => LicenseTerms) public licenseTerms;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256) public userEarnings;
    
    uint256 public listingCounter = 1;
    uint256 public totalTradingVolume;
    uint256 public totalPlatformFees;
    
    // Events
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 price,
        ListingType listingType
    );
    
    event ListingSold(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 price
    );
    
    event BidPlaced(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 bidAmount
    );
    
    event LicenseGranted(
        uint256 indexed listingId,
        address indexed licensee,
        uint256 duration,
        uint256 price
    );
    
    event PaymentProcessed(address indexed recipient, uint256 amount, bool success);
    event RoyaltyPaid(address indexed recipient, uint256 amount);

    constructor(
        address _admin,
        address _slawToken,
        address _treasuryCore
    ) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_treasuryCore != address(0), "Invalid treasury");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MARKETPLACE_ADMIN, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);
        
        slawToken = _slawToken;
        treasuryCore = _treasuryCore;
    }
    
    // ===== LISTING MANAGEMENT =====
    
    function createFixedPriceListing(
        address tokenContract,
        uint256 tokenId,
        uint256 price,
        uint256 royaltyPercentage,
        address royaltyRecipient
    ) external nonReentrant whenNotPaused returns (uint256 listingId) {
        require(price > 0, "Price must be > 0");
        require(royaltyPercentage <= ROYALTY_FEE, "Royalty too high");
        require(IERC721(tokenContract).ownerOf(tokenId) == msg.sender, "Not token owner");
        require(
            IERC721(tokenContract).getApproved(tokenId) == address(this) ||
            IERC721(tokenContract).isApprovedForAll(msg.sender, address(this)),
            "Contract not approved"
        );
        
        listingId = listingCounter++;
        
        listings[listingId] = Listing({
            id: listingId,
            listingType: ListingType.FIXED_PRICE,
            status: ListingStatus.ACTIVE,
            seller: msg.sender,
            tokenContract: tokenContract,
            tokenId: tokenId,
            price: price,
            endTime: 0, // No end time for fixed price
            createdAt: block.timestamp,
            highestBidder: address(0),
            highestBid: 0,
            royaltyPercentage: royaltyPercentage,
            royaltyRecipient: royaltyRecipient
        });
        
        userListings[msg.sender].push(listingId);
        
        emit ListingCreated(listingId, msg.sender, tokenContract, tokenId, price, ListingType.FIXED_PRICE);
    }
    
    function buyNow(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.FIXED_PRICE, "Not a fixed price listing");
        require(msg.sender != listing.seller, "Cannot buy own listing");
        
        uint256 totalPrice = listing.price;
        
        // Transfer SLAW from buyer
        _safeTransferFrom(slawToken, msg.sender, address(this), totalPrice);
        
        // Calculate fees and payments
        uint256 platformFee = (totalPrice * PLATFORM_FEE) / BASIS_POINTS;
        uint256 royaltyAmount = 0;
        
        if (listing.royaltyPercentage > 0 && listing.royaltyRecipient != address(0)) {
            royaltyAmount = (totalPrice * listing.royaltyPercentage) / BASIS_POINTS;
        }
        
        uint256 sellerAmount = totalPrice - platformFee - royaltyAmount;
        
        // Transfer NFT to buyer
        IERC721(listing.tokenContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );
        
        // Process payments securely
        _safeTransfer(slawToken, listing.seller, sellerAmount);
        _safeTransfer(slawToken, treasuryCore, platformFee);
        
        if (royaltyAmount > 0) {
            _safeTransfer(slawToken, listing.royaltyRecipient, royaltyAmount);
            emit RoyaltyPaid(listing.royaltyRecipient, royaltyAmount);
        }
        
        // Update state
        listing.status = ListingStatus.SOLD;
        userEarnings[listing.seller] += sellerAmount;
        totalTradingVolume += totalPrice;
        totalPlatformFees += platformFee;
        
        emit ListingSold(listingId, msg.sender, totalPrice);
    }
    
    // ===== SECURE TRANSFER FUNCTIONS (Replacement for .send/.transfer) =====
    
    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
        emit PaymentProcessed(to, amount, success);
    }
    
    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        if (amount == 0) return;
        
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
    
    // ===== VIEW FUNCTIONS =====
    
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }
    
    function getMarketplaceStats() external view returns (
        uint256 totalListings,
        uint256 totalVolume,
        uint256 platformFees
    ) {
        return (listingCounter - 1, totalTradingVolume, totalPlatformFees);
    }
    
    // ===== ADMIN FUNCTIONS =====
    
    function pause() external onlyRole(MARKETPLACE_ADMIN) {
        _pause();
    }
    
    function unpause() external onlyRole(MARKETPLACE_ADMIN) {
        _unpause();
    }
    
    function updateTreasuryCore(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury");
        _revokeRole(TREASURY_ROLE, treasuryCore);
        treasuryCore = newTreasury;
        _grantRole(TREASURY_ROLE, newTreasury);
    }
    
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        _safeTransfer(token, to, amount);
    }
}
