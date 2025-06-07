// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ISoftlawTreasury.sol";

/**
 * @title SoftlawMarketplace
 * @dev Comprehensive marketplace for IP assets, licenses, and wrapped tokens
 * Features:
 * - IP NFT trading (copyrights, patents)
 * - License marketplace (buy/sell existing licenses)
 * - Wrapped IP token trading
 * - Auction system for rare IP
 * - Bulk trading capabilities
 * - Treasury integration for SLAW payments
 * - Revenue sharing with original creators
 * - Liquidity pool creation assistance
 */
contract SoftlawMarketplace is AccessControl, ReentrancyGuard, Pausable {
    
    ISoftlawTreasury public immutable treasury;
    
    // Roles
    bytes32 public constant MARKETPLACE_ADMIN = keccak256("MARKETPLACE_ADMIN");
    bytes32 public constant VERIFIED_SELLER = keccak256("VERIFIED_SELLER");

    // Listing types
    enum ListingType {
        FIXED_PRICE,        // Fixed price sale
        AUCTION,            // Time-based auction
        BUNDLE,             // Bundle of multiple items
        LICENSE_OFFER,      // License-specific offering
        BULK_TRADE          // Bulk token trading
    }

    // Asset types
    enum AssetType {
        COPYRIGHT_NFT,      // Copyright NFT
        PATENT_NFT,         // Patent NFT
        LICENSE,            // Existing license
        WRAPPED_IP_TOKEN,   // Wrapped IP ERC20 tokens
        IP_BUNDLE           // Bundle of multiple IP assets
    }

    // Listing status
    enum ListingStatus {
        ACTIVE,
        SOLD,
        CANCELLED,
        EXPIRED
    }

    // Marketplace listing structure
    struct Listing {
        uint256 id;
        ListingType listingType;
        AssetType assetType;
        ListingStatus status;
        address seller;
        address buyer;
        address assetContract;      // Contract address of the asset
        uint256 assetId;           // Token ID or identifier
        uint256 quantity;          // For ERC20 tokens
        uint256 priceInSLAW;       // Price in SLAW tokens
        uint256 reservePrice;      // Minimum price for auctions
        uint256 createdAt;
        uint256 expiresAt;
        uint256 soldAt;
        string title;
        string description;
        string[] tags;
        bool allowsOffers;
        mapping(address => Offer) offers;
        address[] offerAddresses;
        // Auction specific
        address highestBidder;
        uint256 highestBid;
        bool auctionEnded;
        // Bundle specific
        BundleItem[] bundleItems;
        // Revenue sharing
        address originalCreator;
        uint256 creatorRoyalty;    // Basis points (100 = 1%)
    }

    // Offer structure
    struct Offer {
        address offerer;
        uint256 amount;
        uint256 expiresAt;
        bool isActive;
        string terms;
    }

    // Bundle item structure
    struct BundleItem {
        address assetContract;
        uint256 assetId;
        AssetType assetType;
        uint256 quantity;
    }

    // Market statistics
    struct MarketStats {
        uint256 totalListings;
        uint256 totalSales;
        uint256 totalVolume;
        uint256 avgPrice;
        uint256 activeListings;
    }

    // Storage
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userPurchases;
    mapping(AssetType => uint256[]) public assetTypeListings;
    mapping(string => uint256[]) public tagListings;
    
    uint256 public listingCounter = 1;
    
    // Market configuration
    uint256 public constant MARKETPLACE_FEE = 250; // 2.5% in basis points
    uint256 public constant MAX_ROYALTY = 1000;    // 10% max royalty
    uint256 public constant LISTING_FEE = 10 * 10**18; // 10 SLAW
    uint256 public constant AUCTION_EXTENSION = 15 minutes;
    
    // Market statistics
    MarketStats public marketStats;

    // Events
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        AssetType assetType,
        uint256 price
    );
    
    event ItemSold(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );
    
    event OfferMade(
        uint256 indexed listingId,
        address indexed offerer,
        uint256 amount
    );
    
    event AuctionBid(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 amount
    );
    
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed seller
    );

    event BundleSold(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 totalPrice,
        uint256 itemCount
    );

    constructor(address _treasury, address _admin) {
        treasury = ISoftlawTreasury(_treasury);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MARKETPLACE_ADMIN, _admin);
    }

    /**
     * @dev Create a fixed price listing
     * @param assetType Type of asset
     * @param assetContract Contract address
     * @param assetId Asset ID
     * @param quantity Quantity (for ERC20 tokens)
     * @param priceInSLAW Price in SLAW
     * @param expiresIn Expiration time in seconds
     * @param title Listing title
     * @param description Listing description
     * @param tags Array of tags
     * @param originalCreator Original creator for royalties
     * @param creatorRoyalty Royalty percentage in basis points
     */
    function createFixedPriceListing(
        AssetType assetType,
        address assetContract,
        uint256 assetId,
        uint256 quantity,
        uint256 priceInSLAW,
        uint256 expiresIn,
        string memory title,
        string memory description,
        string[] memory tags,
        address originalCreator,
        uint256 creatorRoyalty
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(assetContract != address(0), "Invalid asset contract");
        require(priceInSLAW > 0, "Price must be > 0");
        require(creatorRoyalty <= MAX_ROYALTY, "Royalty too high");
        require(bytes(title).length > 0, "Title required");

        // Pay listing fee
        treasury.payLicenseFee(address(0), msg.sender, 0, LISTING_FEE);

        // Validate asset ownership
        _validateAssetOwnership(assetType, assetContract, assetId, quantity, msg.sender);

        uint256 listingId = listingCounter++;

        Listing storage listing = listings[listingId];
        listing.id = listingId;
        listing.listingType = ListingType.FIXED_PRICE;
        listing.assetType = assetType;
        listing.status = ListingStatus.ACTIVE;
        listing.seller = msg.sender;
        listing.assetContract = assetContract;
        listing.assetId = assetId;
        listing.quantity = quantity;
        listing.priceInSLAW = priceInSLAW;
        listing.createdAt = block.timestamp;
        listing.expiresAt = block.timestamp + expiresIn;
        listing.title = title;
        listing.description = description;
        listing.tags = tags;
        listing.allowsOffers = true;
        listing.originalCreator = originalCreator;
        listing.creatorRoyalty = creatorRoyalty;

        // Update mappings
        userListings[msg.sender].push(listingId);
        assetTypeListings[assetType].push(listingId);
        
        for (uint256 i = 0; i < tags.length; i++) {
            tagListings[tags[i]].push(listingId);
        }

        marketStats.totalListings++;
        marketStats.activeListings++;

        emit ListingCreated(listingId, msg.sender, assetType, priceInSLAW);

        return listingId;
    }

    /**
     * @dev Create an auction listing
     * @param assetType Type of asset
     * @param assetContract Contract address
     * @param assetId Asset ID
     * @param reservePrice Minimum bid price
     * @param auctionDuration Duration in seconds
     * @param title Auction title
     * @param description Auction description
     * @param originalCreator Original creator for royalties
     * @param creatorRoyalty Royalty percentage in basis points
     */
    function createAuction(
        AssetType assetType,
        address assetContract,
        uint256 assetId,
        uint256 reservePrice,
        uint256 auctionDuration,
        string memory title,
        string memory description,
        address originalCreator,
        uint256 creatorRoyalty
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(reservePrice > 0, "Reserve price must be > 0");
        require(auctionDuration >= 1 hours, "Auction too short");
        require(auctionDuration <= 30 days, "Auction too long");

        // Pay listing fee
        treasury.payLicenseFee(address(0), msg.sender, 0, LISTING_FEE);

        // Validate ownership
        _validateAssetOwnership(assetType, assetContract, assetId, 1, msg.sender);

        uint256 listingId = listingCounter++;

        Listing storage listing = listings[listingId];
        listing.id = listingId;
        listing.listingType = ListingType.AUCTION;
        listing.assetType = assetType;
        listing.status = ListingStatus.ACTIVE;
        listing.seller = msg.sender;
        listing.assetContract = assetContract;
        listing.assetId = assetId;
        listing.quantity = 1;
        listing.reservePrice = reservePrice;
        listing.createdAt = block.timestamp;
        listing.expiresAt = block.timestamp + auctionDuration;
        listing.title = title;
        listing.description = description;
        listing.originalCreator = originalCreator;
        listing.creatorRoyalty = creatorRoyalty;

        userListings[msg.sender].push(listingId);
        assetTypeListings[assetType].push(listingId);

        marketStats.totalListings++;
        marketStats.activeListings++;

        emit ListingCreated(listingId, msg.sender, assetType, reservePrice);

        return listingId;
    }

    /**
     * @dev Buy item at fixed price
     * @param listingId Listing ID
     */
    function buyFixedPrice(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.FIXED_PRICE, "Not fixed price listing");
        require(block.timestamp <= listing.expiresAt, "Listing expired");
        require(msg.sender != listing.seller, "Cannot buy own listing");

        uint256 totalPrice = listing.priceInSLAW;
        
        // Calculate fees and royalties
        uint256 marketplaceFee = (totalPrice * MARKETPLACE_FEE) / 10000;
        uint256 creatorRoyalty = (totalPrice * listing.creatorRoyalty) / 10000;
        uint256 sellerAmount = totalPrice - marketplaceFee - creatorRoyalty;

        // Process payment through Treasury
        treasury.payLicenseFee(listing.seller, msg.sender, listingId, totalPrice);

        // Transfer asset
        _transferAsset(
            listing.assetType,
            listing.assetContract,
            listing.assetId,
            listing.quantity,
            listing.seller,
            msg.sender
        );

        // Distribute payments
        if (creatorRoyalty > 0 && listing.originalCreator != address(0)) {
            treasury.distributeIncentives(
                _asSingletonArray(listing.originalCreator),
                _asSingletonArray(creatorRoyalty)
            );
        }

        // Update listing
        listing.status = ListingStatus.SOLD;
        listing.buyer = msg.sender;
        listing.soldAt = block.timestamp;

        // Update user mappings
        userPurchases[msg.sender].push(listingId);

        // Update market stats
        marketStats.totalSales++;
        marketStats.totalVolume += totalPrice;
        marketStats.activeListings--;
        marketStats.avgPrice = marketStats.totalVolume / marketStats.totalSales;

        emit ItemSold(listingId, listing.seller, msg.sender, totalPrice);
    }

    /**
     * @dev Place bid on auction
     * @param listingId Listing ID
     * @param bidAmount Bid amount in SLAW
     */
    function placeBid(uint256 listingId, uint256 bidAmount) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.listingType == ListingType.AUCTION, "Not auction listing");
        require(block.timestamp <= listing.expiresAt, "Auction ended");
        require(msg.sender != listing.seller, "Cannot bid on own auction");
        require(bidAmount >= listing.reservePrice, "Bid below reserve");
        require(bidAmount > listing.highestBid, "Bid too low");

        // Lock bid amount in this contract
        treasury.transferFrom(msg.sender, address(this), bidAmount);

        // Refund previous highest bidder
        if (listing.highestBidder != address(0)) {
            treasury.transfer(listing.highestBidder, listing.highestBid);
        }

        // Update auction state
        listing.highestBidder = msg.sender;
        listing.highestBid = bidAmount;

        // Extend auction if bid placed in last 15 minutes
        if (listing.expiresAt - block.timestamp < AUCTION_EXTENSION) {
            listing.expiresAt = block.timestamp + AUCTION_EXTENSION;
        }

        emit AuctionBid(listingId, msg.sender, bidAmount);
    }

    /**
     * @dev End auction and transfer assets
     * @param listingId Listing ID
     */
    function endAuction(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.listingType == ListingType.AUCTION, "Not auction");
        require(block.timestamp > listing.expiresAt, "Auction still active");
        require(!listing.auctionEnded, "Auction already ended");

        listing.auctionEnded = true;

        if (listing.highestBidder != address(0)) {
            // Calculate fees and royalties
            uint256 totalPrice = listing.highestBid;
            uint256 marketplaceFee = (totalPrice * MARKETPLACE_FEE) / 10000;
            uint256 creatorRoyalty = (totalPrice * listing.creatorRoyalty) / 10000;
            uint256 sellerAmount = totalPrice - marketplaceFee - creatorRoyalty;

            // Transfer asset to winner
            _transferAsset(
                listing.assetType,
                listing.assetContract,
                listing.assetId,
                listing.quantity,
                listing.seller,
                listing.highestBidder
            );

            // Pay seller
            treasury.transfer(listing.seller, sellerAmount);

            // Pay creator royalty
            if (creatorRoyalty > 0 && listing.originalCreator != address(0)) {
                treasury.transfer(listing.originalCreator, creatorRoyalty);
            }

            // Marketplace fee stays in contract

            listing.status = ListingStatus.SOLD;
            listing.buyer = listing.highestBidder;
            listing.soldAt = block.timestamp;

            userPurchases[listing.highestBidder].push(listingId);

            // Update market stats
            marketStats.totalSales++;
            marketStats.totalVolume += totalPrice;
            marketStats.avgPrice = marketStats.totalVolume / marketStats.totalSales;

            emit ItemSold(listingId, listing.seller, listing.highestBidder, totalPrice);
        } else {
            listing.status = ListingStatus.EXPIRED;
        }

        marketStats.activeListings--;
    }

    /**
     * @dev Make offer on listing
     * @param listingId Listing ID
     * @param offerAmount Offer amount in SLAW
     * @param expiresIn Offer expiration in seconds
     * @param terms Offer terms
     */
    function makeOffer(
        uint256 listingId,
        uint256 offerAmount,
        uint256 expiresIn,
        string memory terms
    ) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.allowsOffers, "Offers not allowed");
        require(offerAmount > 0, "Offer must be > 0");
        require(msg.sender != listing.seller, "Cannot offer on own listing");

        // Lock offer amount
        treasury.transferFrom(msg.sender, address(this), offerAmount);

        Offer storage offer = listing.offers[msg.sender];
        
        // Refund previous offer if exists
        if (offer.isActive) {
            treasury.transfer(msg.sender, offer.amount);
        } else {
            listing.offerAddresses.push(msg.sender);
        }

        offer.offerer = msg.sender;
        offer.amount = offerAmount;
        offer.expiresAt = block.timestamp + expiresIn;
        offer.isActive = true;
        offer.terms = terms;

        emit OfferMade(listingId, msg.sender, offerAmount);
    }

    /**
     * @dev Accept offer
     * @param listingId Listing ID
     * @param offerer Address of offerer
     */
    function acceptOffer(uint256 listingId, address offerer) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.seller, "Not seller");
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");

        Offer storage offer = listing.offers[offerer];
        require(offer.isActive, "Offer not active");
        require(block.timestamp <= offer.expiresAt, "Offer expired");

        uint256 totalPrice = offer.amount;
        
        // Calculate fees and royalties
        uint256 marketplaceFee = (totalPrice * MARKETPLACE_FEE) / 10000;
        uint256 creatorRoyalty = (totalPrice * listing.creatorRoyalty) / 10000;
        uint256 sellerAmount = totalPrice - marketplaceFee - creatorRoyalty;

        // Transfer asset
        _transferAsset(
            listing.assetType,
            listing.assetContract,
            listing.assetId,
            listing.quantity,
            listing.seller,
            offerer
        );

        // Pay seller
        treasury.transfer(listing.seller, sellerAmount);

        // Pay creator royalty
        if (creatorRoyalty > 0 && listing.originalCreator != address(0)) {
            treasury.transfer(listing.originalCreator, creatorRoyalty);
        }

        // Refund other offers
        _refundOtherOffers(listingId, offerer);

        // Update listing
        listing.status = ListingStatus.SOLD;
        listing.buyer = offerer;
        listing.soldAt = block.timestamp;

        userPurchases[offerer].push(listingId);

        // Update market stats
        marketStats.totalSales++;
        marketStats.totalVolume += totalPrice;
        marketStats.activeListings--;
        marketStats.avgPrice = marketStats.totalVolume / marketStats.totalSales;

        emit ItemSold(listingId, listing.seller, offerer, totalPrice);
    }

    // ===== VIEW FUNCTIONS =====

    function getListing(uint256 listingId) external view returns (
        uint256 id,
        ListingType listingType,
        AssetType assetType,
        ListingStatus status,
        address seller,
        uint256 priceInSLAW,
        uint256 expiresAt,
        string memory title
    ) {
        Listing storage listing = listings[listingId];
        return (
            listing.id,
            listing.listingType,
            listing.assetType,
            listing.status,
            listing.seller,
            listing.priceInSLAW,
            listing.expiresAt,
            listing.title
        );
    }

    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }

    function getUserPurchases(address user) external view returns (uint256[] memory) {
        return userPurchases[user];
    }

    function getListingsByAssetType(AssetType assetType) external view returns (uint256[] memory) {
        return assetTypeListings[assetType];
    }

    function getListingsByTag(string memory tag) external view returns (uint256[] memory) {
        return tagListings[tag];
    }

    function getMarketStats() external view returns (MarketStats memory) {
        return marketStats;
    }

    function getOffer(uint256 listingId, address offerer) external view returns (Offer memory) {
        return listings[listingId].offers[offerer];
    }

    // ===== INTERNAL FUNCTIONS =====

    function _validateAssetOwnership(
        AssetType assetType,
        address assetContract,
        uint256 assetId,
        uint256 quantity,
        address owner
    ) internal view {
        if (assetType == AssetType.COPYRIGHT_NFT || assetType == AssetType.PATENT_NFT) {
            require(IERC721(assetContract).ownerOf(assetId) == owner, "Not NFT owner");
        } else if (assetType == AssetType.WRAPPED_IP_TOKEN) {
            require(IERC20(assetContract).balanceOf(owner) >= quantity, "Insufficient tokens");
        }
        // Add more validation for other asset types
    }

    function _transferAsset(
        AssetType assetType,
        address assetContract,
        uint256 assetId,
        uint256 quantity,
        address from,
        address to
    ) internal {
        if (assetType == AssetType.COPYRIGHT_NFT || assetType == AssetType.PATENT_NFT) {
            IERC721(assetContract).safeTransferFrom(from, to, assetId);
        } else if (assetType == AssetType.WRAPPED_IP_TOKEN) {
            IERC20(assetContract).transferFrom(from, to, quantity);
        }
        // Handle other asset types
    }

    function _refundOtherOffers(uint256 listingId, address acceptedOfferer) internal {
        Listing storage listing = listings[listingId];
        
        for (uint256 i = 0; i < listing.offerAddresses.length; i++) {
            address offererAddr = listing.offerAddresses[i];
            if (offererAddr != acceptedOfferer) {
                Offer storage offer = listing.offers[offererAddr];
                if (offer.isActive) {
                    treasury.transfer(offererAddr, offer.amount);
                    offer.isActive = false;
                }
            }
        }
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

    function pause() external onlyRole(MARKETPLACE_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(MARKETPLACE_ADMIN) {
        _unpause();
    }

    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(
            msg.sender == listing.seller || hasRole(MARKETPLACE_ADMIN, msg.sender),
            "Not authorized"
        );
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");

        listing.status = ListingStatus.CANCELLED;
        marketStats.activeListings--;

        // Refund all offers
        _refundOtherOffers(listingId, address(0));

        emit ListingCancelled(listingId, listing.seller);
    }

    function withdrawMarketplaceFees() external onlyRole(MARKETPLACE_ADMIN) {
        uint256 balance = treasury.balanceOf(address(this));
        if (balance > 0) {
            treasury.transfer(msg.sender, balance);
        }
    }
}
