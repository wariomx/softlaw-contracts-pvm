// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "../IP-liquidity/SLAWToken.sol";
import "../treasury/TreasuryCore.sol";

/**
 * @title MarketplaceCore
 * @dev PVM-optimized marketplace for NFTs and Wrapped IP tokens
 * Features:
 * - NFT and token trading
 * - SLAW-based payments
 * - Fee integration with treasury
 * - Withdrawal pattern (no .send/.transfer)
 * - Lightweight design for PVM
 */
contract MarketplaceCore is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant MARKETPLACE_ADMIN = keccak256("MARKETPLACE_ADMIN");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // System contracts
    SLAWToken public immutable slawToken;
    TreasuryCore public treasuryCore;

    // Listing types
    enum ListingType {
        NFT,
        TOKEN
    }
    enum ListingStatus {
        ACTIVE,
        SOLD,
        CANCELLED
    }

    // Listing structure
    struct Listing {
        uint256 listingId;
        address seller;
        ListingType listingType;
        address tokenContract; // NFT contract or ERC20 contract
        uint256 tokenId; // NFT ID (for NFTs) or amount (for tokens)
        uint256 price; // Price in SLAW
        ListingStatus status;
        uint256 createdAt;
        uint256 expiresAt;
        bool allowOffers;
    }

    // Offer structure
    struct Offer {
        uint256 offerId;
        uint256 listingId;
        address offerer;
        uint256 amount; // Offer amount in SLAW
        uint256 expiresAt;
        bool isActive;
        uint256 createdAt;
    }

    // State variables
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => uint256[]) public listingOffers; // listingId => offerIds[]
    mapping(address => uint256[]) public userListings; // seller => listingIds[]
    mapping(address => uint256[]) public userOffers; // offerer => offerIds[]

    // Counters
    uint256 public nextListingId = 1;
    uint256 public nextOfferId = 1;

    // System metrics
    uint256 public totalListings;
    uint256 public totalSales;
    uint256 public totalVolume;

    // Supported contracts
    mapping(address => bool) public supportedNFTContracts;
    mapping(address => bool) public supportedTokenContracts;

    // Events
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        ListingType listingType,
        address indexed tokenContract,
        uint256 tokenId,
        uint256 price
    );

    event ListingCancelled(uint256 indexed listingId, address indexed seller);

    event ItemSold(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        uint256 marketplaceFee
    );

    event OfferCreated(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed offerer,
        uint256 amount
    );

    event OfferAccepted(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed seller,
        address offerer,
        uint256 amount
    );

    event OfferCancelled(uint256 indexed offerId, address indexed offerer);

    event ContractSupportUpdated(
        address indexed contractAddress,
        bool isNFT,
        bool supported
    );

    constructor(address _admin, address _slawToken, address _treasuryCore) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_treasuryCore != address(0), "Invalid treasury core");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MARKETPLACE_ADMIN, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);

        slawToken = SLAWToken(_slawToken);
        treasuryCore = TreasuryCore(_treasuryCore);
    }

    // ===== LISTING FUNCTIONS =====

    /**
     * @dev Create NFT listing
     * @param nftContract NFT contract address
     * @param tokenId NFT token ID
     * @param price Price in SLAW
     * @param duration Duration in seconds
     * @param allowOffers Whether to allow offers
     */
    function createNFTListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 duration,
        bool allowOffers
    ) external nonReentrant whenNotPaused returns (uint256 listingId) {
        require(
            supportedNFTContracts[nftContract],
            "NFT contract not supported"
        );
        require(price > 0, "Price must be > 0");
        require(duration > 0 && duration <= 365 days, "Invalid duration");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not NFT owner"
        );
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
                IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved"
        );

        listingId = nextListingId++;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            listingType: ListingType.NFT,
            tokenContract: nftContract,
            tokenId: tokenId,
            price: price,
            status: ListingStatus.ACTIVE,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            allowOffers: allowOffers
        });

        userListings[msg.sender].push(listingId);
        totalListings++;

        emit ListingCreated(
            listingId,
            msg.sender,
            ListingType.NFT,
            nftContract,
            tokenId,
            price
        );
    }

    /**
     * @dev Create token listing
     * @param tokenContract Token contract address
     * @param amount Amount of tokens to sell
     * @param price Price in SLAW
     * @param duration Duration in seconds
     * @param allowOffers Whether to allow offers
     */
    function createTokenListing(
        address tokenContract,
        uint256 amount,
        uint256 price,
        uint256 duration,
        bool allowOffers
    ) external nonReentrant whenNotPaused returns (uint256 listingId) {
        require(
            supportedTokenContracts[tokenContract],
            "Token contract not supported"
        );
        require(amount > 0, "Amount must be > 0");
        require(price > 0, "Price must be > 0");
        require(duration > 0 && duration <= 365 days, "Invalid duration");
        require(
            IERC20(tokenContract).balanceOf(msg.sender) >= amount,
            "Insufficient token balance"
        );
        require(
            IERC20(tokenContract).allowance(msg.sender, address(this)) >=
                amount,
            "Insufficient allowance"
        );

        listingId = nextListingId++;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            listingType: ListingType.TOKEN,
            tokenContract: tokenContract,
            tokenId: amount, // Using tokenId field to store amount for tokens
            price: price,
            status: ListingStatus.ACTIVE,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            allowOffers: allowOffers
        });

        userListings[msg.sender].push(listingId);
        totalListings++;

        emit ListingCreated(
            listingId,
            msg.sender,
            ListingType.TOKEN,
            tokenContract,
            amount,
            price
        );
    }

    /**
     * @dev Buy item directly
     * @param listingId Listing ID to purchase
     */
    function buyItem(uint256 listingId) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(block.timestamp <= listing.expiresAt, "Listing expired");
        require(listing.seller != msg.sender, "Cannot buy own listing");

        uint256 totalPrice = listing.price;
        require(
            slawToken.balanceOf(msg.sender) >= totalPrice,
            "Insufficient SLAW balance"
        );

        // Process payment through treasury (handles fee calculation and distribution)
        uint256 netAmount = treasuryCore.processMarketplaceFee(
            listing.seller,
            msg.sender,
            totalPrice,
            listingId
        );

        // Transfer the item
        if (listing.listingType == ListingType.NFT) {
            IERC721(listing.tokenContract).safeTransferFrom(
                listing.seller,
                msg.sender,
                listing.tokenId
            );
        } else {
            require(
                IERC20(listing.tokenContract).transferFrom(
                    listing.seller,
                    msg.sender,
                    listing.tokenId // amount stored in tokenId field
                ),
                "Token transfer failed"
            );
        }

        // Update listing status
        listing.status = ListingStatus.SOLD;
        totalSales++;
        totalVolume += totalPrice;

        // Cancel all active offers for this listing
        _cancelAllOffers(listingId);

        emit ItemSold(
            listingId,
            listing.seller,
            msg.sender,
            totalPrice,
            totalPrice - netAmount
        );
    }

    /**
     * @dev Cancel listing
     * @param listingId Listing ID to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(
            listing.seller == msg.sender ||
                hasRole(MARKETPLACE_ADMIN, msg.sender),
            "Not authorized"
        );
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");

        listing.status = ListingStatus.CANCELLED;

        // Cancel all active offers for this listing
        _cancelAllOffers(listingId);

        emit ListingCancelled(listingId, listing.seller);
    }

    // ===== OFFER FUNCTIONS =====

    /**
     * @dev Make offer on listing
     * @param listingId Listing ID to make offer on
     * @param amount Offer amount in SLAW
     * @param duration Offer duration in seconds
     */
    function makeOffer(
        uint256 listingId,
        uint256 amount,
        uint256 duration
    ) external nonReentrant whenNotPaused returns (uint256 offerId) {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(listing.allowOffers, "Offers not allowed");
        require(block.timestamp <= listing.expiresAt, "Listing expired");
        require(listing.seller != msg.sender, "Cannot offer on own listing");
        require(amount > 0, "Amount must be > 0");
        require(duration > 0 && duration <= 30 days, "Invalid duration");
        require(
            slawToken.balanceOf(msg.sender) >= amount,
            "Insufficient SLAW balance"
        );

        offerId = nextOfferId++;

        offers[offerId] = Offer({
            offerId: offerId,
            listingId: listingId,
            offerer: msg.sender,
            amount: amount,
            expiresAt: block.timestamp + duration,
            isActive: true,
            createdAt: block.timestamp
        });

        listingOffers[listingId].push(offerId);
        userOffers[msg.sender].push(offerId);

        emit OfferCreated(offerId, listingId, msg.sender, amount);
    }

    /**
     * @dev Accept offer
     * @param offerId Offer ID to accept
     */
    function acceptOffer(uint256 offerId) external nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        Listing storage listing = listings[offer.listingId];

        require(offer.isActive, "Offer not active");
        require(block.timestamp <= offer.expiresAt, "Offer expired");
        require(listing.seller == msg.sender, "Not listing owner");
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");
        require(
            slawToken.balanceOf(offer.offerer) >= offer.amount,
            "Offerer insufficient balance"
        );

        // Process payment through treasury
        uint256 netAmount = treasuryCore.processMarketplaceFee(
            listing.seller,
            offer.offerer,
            offer.amount,
            offer.listingId
        );

        // Transfer the item
        if (listing.listingType == ListingType.NFT) {
            IERC721(listing.tokenContract).safeTransferFrom(
                listing.seller,
                offer.offerer,
                listing.tokenId
            );
        } else {
            require(
                IERC20(listing.tokenContract).transferFrom(
                    listing.seller,
                    offer.offerer,
                    listing.tokenId // amount stored in tokenId field
                ),
                "Token transfer failed"
            );
        }

        // Update states
        listing.status = ListingStatus.SOLD;
        offer.isActive = false;
        totalSales++;
        totalVolume += offer.amount;

        // Cancel all other offers for this listing
        _cancelAllOffers(offer.listingId);

        emit OfferAccepted(
            offerId,
            offer.listingId,
            listing.seller,
            offer.offerer,
            offer.amount
        );
        emit ItemSold(
            offer.listingId,
            listing.seller,
            offer.offerer,
            offer.amount,
            offer.amount - netAmount
        );
    }

    /**
     * @dev Cancel offer
     * @param offerId Offer ID to cancel
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(
            offer.offerer == msg.sender ||
                hasRole(MARKETPLACE_ADMIN, msg.sender),
            "Not authorized"
        );
        require(offer.isActive, "Offer not active");

        offer.isActive = false;

        emit OfferCancelled(offerId, offer.offerer);
    }

    // ===== INTERNAL FUNCTIONS =====

    /**
     * @dev Cancel all offers for a listing
     * @param listingId Listing ID
     */
    function _cancelAllOffers(uint256 listingId) internal {
        uint256[] memory offerIds = listingOffers[listingId];

        for (uint256 i = 0; i < offerIds.length; i++) {
            Offer storage offer = offers[offerIds[i]];
            if (offer.isActive) {
                offer.isActive = false;
                emit OfferCancelled(offerIds[i], offer.offerer);
            }
        }
    }

    // ===== CONTRACT MANAGEMENT =====

    /**
     * @dev Set supported NFT contract
     * @param nftContract NFT contract address
     * @param supported Whether supported
     */
    function setSupportedNFTContract(
        address nftContract,
        bool supported
    ) external onlyRole(MARKETPLACE_ADMIN) {
        require(nftContract != address(0), "Invalid contract address");

        supportedNFTContracts[nftContract] = supported;

        emit ContractSupportUpdated(nftContract, true, supported);
    }

    /**
     * @dev Set supported token contract
     * @param tokenContract Token contract address
     * @param supported Whether supported
     */
    function setSupportedTokenContract(
        address tokenContract,
        bool supported
    ) external onlyRole(MARKETPLACE_ADMIN) {
        require(tokenContract != address(0), "Invalid contract address");

        supportedTokenContracts[tokenContract] = supported;

        emit ContractSupportUpdated(tokenContract, false, supported);
    }

    /**
     * @dev Batch set supported contracts
     * @param contracts Array of contract addresses
     * @param isNFT Whether contracts are NFT contracts
     * @param supported Whether contracts are supported
     */
    function batchSetSupportedContracts(
        address[] calldata contracts,
        bool isNFT,
        bool supported
    ) external onlyRole(MARKETPLACE_ADMIN) {
        require(contracts.length <= 20, "Too many contracts"); // PVM memory limit

        for (uint256 i = 0; i < contracts.length; i++) {
            require(contracts[i] != address(0), "Invalid contract address");

            if (isNFT) {
                supportedNFTContracts[contracts[i]] = supported;
            } else {
                supportedTokenContracts[contracts[i]] = supported;
            }

            emit ContractSupportUpdated(contracts[i], isNFT, supported);
        }
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @dev Get listing details
     * @param listingId Listing ID
     */
    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return listings[listingId];
    }

    /**
     * @dev Get offer details
     * @param offerId Offer ID
     */
    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    /**
     * @dev Get user listings
     * @param user User address
     */
    function getUserListings(
        address user
    ) external view returns (uint256[] memory) {
        return userListings[user];
    }

    /**
     * @dev Get user offers
     * @param user User address
     */
    function getUserOffers(
        address user
    ) external view returns (uint256[] memory) {
        return userOffers[user];
    }

    /**
     * @dev Get listing offers
     * @param listingId Listing ID
     */
    function getListingOffers(
        uint256 listingId
    ) external view returns (uint256[] memory) {
        return listingOffers[listingId];
    }

    /**
     * @dev Get system metrics
     */
    function getSystemMetrics()
        external
        view
        returns (
            uint256 _totalListings,
            uint256 _totalSales,
            uint256 _totalVolume,
            uint256 activeListings
        )
    {
        // Note: activeListings would require iteration in full implementation
        return (
            totalListings,
            totalSales,
            totalVolume,
            totalListings - totalSales
        );
    }

    // ===== TREASURY INTEGRATION =====

    /**
     * @dev Update treasury core address
     * @param newTreasuryCore New treasury core address
     */
    function updateTreasuryCore(
        address newTreasuryCore
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasuryCore != address(0), "Invalid treasury address");

        _revokeRole(TREASURY_ROLE, address(treasuryCore));
        treasuryCore = TreasuryCore(newTreasuryCore);
        _grantRole(TREASURY_ROLE, newTreasuryCore);
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(MARKETPLACE_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(MARKETPLACE_ADMIN) {
        _unpause();
    }

    /**
     * @dev Emergency cancel listing (admin only)
     * @param listingId Listing ID to cancel
     */
    function emergencyCancelListing(
        uint256 listingId
    ) external onlyRole(MARKETPLACE_ADMIN) {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.ACTIVE, "Listing not active");

        listing.status = ListingStatus.CANCELLED;
        _cancelAllOffers(listingId);

        emit ListingCancelled(listingId, listing.seller);
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(
        address token,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");

        IERC20(token).transfer(address(treasuryCore), amount);
    }
}
