// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CopyrightsRegistry
 * @dev Contract for wrapping NFTs with copyright protection metadata
 * Compliant with Berne Convention and international copyright law
 */
contract CopyrightsRegistry is ReentrancyGuard, ERC721, Ownable, Pausable {
    address public _contractOwner;

    // Registry
    uint256 public constant REGISTRY_FEE = 0.5 ether;

    uint256 internal _nextCopyrightId = 1;

    // This rights are activated at the moment of a license
    struct EconomicRights {
        bool reproduction; // right to prevent copying
        bool distribution; // right to sell copies
        bool rental; // right to rent\
        bool broadcasting;
        bool performance; // public performance
        bool translation;
        bool adaptation; // adapt/modify
        address owner; // owner f the economics rights
    }

    struct CopyrightWrapper {
        address author; // moral rights holder (inalienable)
        address economicRightsOwner; // economic rights holder (transferable)
        EconomicRights copyrights; //
        string name;
        string description;
        string image;
        uint256 registryDate;
        address originalNftContract;
        uint256 originalNftId;
        bool isWrapped;
        bool isValidated;
    }

    // Events
    event CopyrightProtected(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed author,
        address originalContract,
        uint256 originalTokenId
    );

    event CopyrightValidated(uint256 indexed tokenId);
    event CopyrightUnwrapped(uint256 indexed tokenId, address indexed owner);
    event EconomicRightsTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to
    );

    // Storage
    mapping(uint256 => CopyrightWrapper) public copyrights;
    mapping(uint256 => address) private _originalContracts;
    mapping(uint256 => uint256) private _originalIds;
    mapping(address => mapping(uint256 => uint256)) private _wrappedTokens; // original contract => original ID => wrapped ID

    // Fee recipient
    address public feeRecipient;

    modifier validTokenId(uint256 tokenId) {
        require(_exists(tokenId), "Token does not exist");
        _;
    }

    modifier onlyEconomicRightsOwner(uint256 tokenId) {
        require(
            copyrights[tokenId].economicRightsOwner == msg.sender,
            "Not economic rights owner"
        );
        _;
    }

    constructor(
        address _feeRecipient
    ) ERC721("Copyright Registry", "COPYRIGHT") Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Creates a copyright wrapper for an existing NFT
     * @param _author Address that holds moral rights (inalienable)
     * @param _economicRightsOwner Address that holds economic rights (transferable)
     * @param _name Name of the copyrighted work
     * @param _description Description of the work
     * @param _image IPFS hash or URL of the work image
     * @param _originalNftContract Original NFT contract address
     * @param _originalNftId Original NFT token ID
     * @return tokenId The newly created copyright token ID
     */
    function protectCopyright(
        address _author,
        address _economicRightsOwner,
        string memory _name,
        string memory _description,
        string memory _image,
        address _originalNftContract,
        uint256 _originalNftId
    ) external payable nonReentrant whenNotPaused returns (uint256) {
        require(msg.value >= REGISTRY_FEE, "Insufficient registration fee");
        require(_author != address(0), "Invalid author address");
        require(
            _economicRightsOwner != address(0),
            "Invalid economic rights owner"
        );
        require(_originalNftContract != address(0), "Invalid NFT contract");
        require(bytes(_name).length > 0, "Name cannot be empty");

        // Check that sender owns the original NFT
        IERC721 originalNft = IERC721(_originalNftContract);
        require(
            originalNft.ownerOf(_originalNftId) == msg.sender,
            "Not owner of original NFT"
        );

        // Check if already wrapped
        require(
            _wrappedTokens[_originalNftContract][_originalNftId] == 0,
            "NFT already wrapped"
        );

        // Check approval
        require(
            originalNft.getApproved(_originalNftId) == address(this) ||
                originalNft.isApprovedForAll(msg.sender, address(this)),
            "Transfer not approved"
        );

        // Transfer original NFT to this contract
        originalNft.safeTransferFrom(msg.sender, address(this), _originalNftId);

        // Create economic rights structure
        EconomicRights memory economicRights = EconomicRights({
            reproduction: true, // Default rights granted to owner
            distribution: true,
            rental: true,
            broadcasting: false, // Optional rights
            performance: false,
            translation: false,
            adaptation: false,
            owner: _economicRightsOwner
        });

        // Create copyright wrapper
        uint256 tokenId = _nextCopyrightId++;

        copyrights[tokenId] = CopyrightWrapper({
            author: _author,
            economicRightsOwner: _economicRightsOwner,
            copyrights: economicRights,
            name: _name,
            description: _description,
            image: _image,
            registryDate: block.timestamp,
            originalNftContract: _originalNftContract,
            originalNftId: _originalNftId,
            isWrapped: true,
            isValidated: false
        });

        // Store mappings
        _originalContracts[tokenId] = _originalNftContract;
        _originalIds[tokenId] = _originalNftId;
        _wrappedTokens[_originalNftContract][_originalNftId] = tokenId;

        // Mint copyright token to the sender
        _mint(msg.sender, tokenId);

        // Transfer fee to recipient
        _transferFee(msg.value);

        emit CopyrightProtected(
            tokenId,
            msg.sender,
            _author,
            _originalNftContract,
            _originalNftId
        );

        return tokenId;
    }

    /**
     * @dev Unwraps a copyright token and returns the original NFT
     * @param tokenId Token ID to unwrap
     */
    function unwrap(
        uint256 tokenId
    ) external nonReentrant validTokenId(tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Not owner of copyright token");
        require(copyrights[tokenId].isWrapped, "Token not wrapped");

        address originalContract = _originalContracts[tokenId];
        uint256 originalId = _originalIds[tokenId];

        // Update state before external calls
        copyrights[tokenId].isWrapped = false;
        _wrappedTokens[originalContract][originalId] = 0;

        // Burn the wrapper token
        _burn(tokenId);

        // Return the original NFT
        IERC721(originalContract).safeTransferFrom(
            address(this),
            msg.sender,
            originalId
        );

        emit CopyrightUnwrapped(tokenId, msg.sender);
    }

    /**
     * @dev Transfer economic rights to a new owner
     * @param tokenId Copyright token ID
     * @param newOwner New economic rights owner
     */
    function transferEconomicRights(
        uint256 tokenId,
        address newOwner
    ) external validTokenId(tokenId) onlyEconomicRightsOwner(tokenId) {
        require(newOwner != address(0), "Invalid new owner");
        require(
            newOwner != copyrights[tokenId].economicRightsOwner,
            "Same owner"
        );

        address oldOwner = copyrights[tokenId].economicRightsOwner;
        copyrights[tokenId].economicRightsOwner = newOwner;
        copyrights[tokenId].copyrights.owner = newOwner;

        emit EconomicRightsTransferred(tokenId, oldOwner, newOwner);
    }

    /**
     * @dev Validates a copyright claim (only contract owner)
     * @param tokenId Token ID to validate
     */
    function validateCopyright(
        uint256 tokenId
    ) external onlyOwner validTokenId(tokenId) {
        copyrights[tokenId].isValidated = true;
        emit CopyrightValidated(tokenId);
    }

    /**
     * @dev Update specific economic rights
     * @param tokenId Copyright token ID
     * @param rightType Type of right to update (0-6)
     * @param granted Whether the right is granted
     */
    function updateEconomicRight(
        uint256 tokenId,
        uint8 rightType,
        bool granted
    ) external validTokenId(tokenId) onlyEconomicRightsOwner(tokenId) {
        require(rightType <= 6, "Invalid right type");

        EconomicRights storage rights = copyrights[tokenId].copyrights;

        if (rightType == 0) rights.reproduction = granted;
        else if (rightType == 1) rights.distribution = granted;
        else if (rightType == 2) rights.rental = granted;
        else if (rightType == 3) rights.broadcasting = granted;
        else if (rightType == 4) rights.performance = granted;
        else if (rightType == 5) rights.translation = granted;
        else if (rightType == 6) rights.adaptation = granted;
    }

    /**
     * @dev Set new fee recipient
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        feeRecipient = newRecipient;
    }

    /**
     * @dev Update registry fee
     * @param newFee New fee amount in wei
     */
    function updateRegistryFee(uint256 newFee) external onlyOwner {
        // This would require updating the constant in a new contract version
        // For now, we can emit an event for off-chain tracking
    }

    /**
     * @dev Pause contract operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal function
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Get copyright details
     * @param tokenId Token ID to query
     * @return Copyright wrapper details
     */
    function getCopyrightDetails(
        uint256 tokenId
    ) external view validTokenId(tokenId) returns (CopyrightWrapper memory) {
        return copyrights[tokenId];
    }

    /**
     * @dev Check if an NFT is already wrapped
     * @param nftContract Original NFT contract
     * @param nftId Original NFT ID
     * @return copyrightId The copyright token ID (0 if not wrapped)
     */
    function getWrappedTokenId(
        address nftContract,
        uint256 nftId
    ) external view returns (uint256) {
        return _wrappedTokens[nftContract][nftId];
    }

    /**
     * @dev Get original NFT details for a copyright token
     * @param tokenId Copyright token ID
     * @return contract address and token ID of original NFT
     */
    function getOriginalNFT(
        uint256 tokenId
    ) external view validTokenId(tokenId) returns (address, uint256) {
        return (_originalContracts[tokenId], _originalIds[tokenId]);
    }

    /**
     * @dev Internal function to transfer fees
     * @param amount Amount to transfer
     */
    function _transferFee(uint256 amount) internal {
        if (amount > 0) {
            (bool success, ) = payable(feeRecipient).call{value: amount}("");
            require(success, "Fee transfer failed");
        }
    }

    /**
     * @dev Override _exists to make it available
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return
            tokenId > 0 &&
            tokenId < _nextCopyrightId &&
            copyrights[tokenId].registryDate > 0;
    }

    /**
     * @dev Override transfer ownership to make it available
     */
}
