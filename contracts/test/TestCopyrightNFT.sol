// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title TestCopyrightNFT
 * @dev Simple test NFT contract for PVM testing
 * Features:
 * - Mintable copyright NFTs
 * - URI storage for metadata
 * - Pausable functionality
 * - Owner controls
 * - PVM-optimized lightweight design
 */
contract TestCopyrightNFT is ERC721, ERC721URIStorage, Ownable, Pausable {
    uint256 private _nextTokenId = 1;

    // Mapping from token ID to creator
    mapping(uint256 => address) public creators;

    // Mapping from token ID to copyright info
    mapping(uint256 => CopyrightInfo) public copyrightInfo;

    struct CopyrightInfo {
        string title;
        string description;
        string category; // "music", "art", "literature", "software", etc.
        uint256 creationDate;
        bool isRegistered;
    }

    event CopyrightMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string title,
        string category
    );

    event CopyrightRegistered(uint256 indexed tokenId, address indexed creator);

    constructor(
        address initialOwner
    ) ERC721("Test Copyright NFT", "TCNFT") Ownable(initialOwner) {}

    /**
     * @dev Mint a new copyright NFT
     * @param to Address to mint to
     * @param title Copyright title
     * @param description Copyright description
     * @param category Copyright category
     * @param uri Token URI for metadata
     */
    function mintCopyright(
        address to,
        string memory title,
        string memory description,
        string memory category,
        string memory uri
    ) external whenNotPaused returns (uint256) {
        require(to != address(0), "Cannot mint to zero address");
        require(bytes(title).length > 0, "Title required");
        require(bytes(category).length > 0, "Category required");

        uint256 tokenId = _nextTokenId++;

        // Store copyright info
        copyrightInfo[tokenId] = CopyrightInfo({
            title: title,
            description: description,
            category: category,
            creationDate: block.timestamp,
            isRegistered: false
        });

        creators[tokenId] = to;

        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit CopyrightMinted(tokenId, to, title, category);

        return tokenId;
    }

    /**
     * @dev Batch mint copyright NFTs for testing
     * @param to Address to mint to
     * @param count Number of NFTs to mint
     * @param baseTitle Base title for NFTs
     * @param category Copyright category
     * @param baseURI Base URI for metadata
     */
    function batchMintCopyright(
        address to,
        uint256 count,
        string memory baseTitle,
        string memory category,
        string memory baseURI
    ) external whenNotPaused returns (uint256[] memory tokenIds) {
        require(to != address(0), "Cannot mint to zero address");
        require(count > 0 && count <= 20, "Invalid count"); // PVM memory limit
        require(bytes(baseTitle).length > 0, "Title required");
        require(bytes(category).length > 0, "Category required");

        tokenIds = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = _nextTokenId++;

            string memory title = string(
                abi.encodePacked(baseTitle, " #", _toString(i + 1))
            );
            string memory description = string(
                abi.encodePacked("Test copyright NFT #", _toString(i + 1))
            );
            string memory uri = string(
                abi.encodePacked(baseURI, "/", _toString(tokenId))
            );

            copyrightInfo[tokenId] = CopyrightInfo({
                title: title,
                description: description,
                category: category,
                creationDate: block.timestamp,
                isRegistered: false
            });

            creators[tokenId] = to;
            tokenIds[i] = tokenId;

            _mint(to, tokenId);
            _setTokenURI(tokenId, uri);

            emit CopyrightMinted(tokenId, to, title, category);
        }

        return tokenIds;
    }

    /**
     * @dev Register copyright (simulate registry integration)
     * @param tokenId Token ID to register
     */
    function registerCopyright(uint256 tokenId) external {
        require(_ownerOf(tokenId) == msg.sender, "Not token owner");
        require(!copyrightInfo[tokenId].isRegistered, "Already registered");

        copyrightInfo[tokenId].isRegistered = true;

        emit CopyrightRegistered(tokenId, msg.sender);
    }

    /**
     * @dev Update token URI
     * @param tokenId Token ID
     * @param uri New URI
     */
    function updateTokenURI(uint256 tokenId, string memory uri) external {
        require(
            _ownerOf(tokenId) == msg.sender || msg.sender == owner(),
            "Not authorized"
        );
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        _setTokenURI(tokenId, uri);
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @dev Get copyright info for token
     * @param tokenId Token ID
     */
    function getCopyrightInfo(
        uint256 tokenId
    ) external view returns (CopyrightInfo memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return copyrightInfo[tokenId];
    }

    /**
     * @dev Get creator of token
     * @param tokenId Token ID
     */
    function getCreator(uint256 tokenId) external view returns (address) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return creators[tokenId];
    }

    /**
     * @dev Get tokens owned by address
     * @param owner Owner address
     */
    function getTokensByOwner(
        address owner
    ) external view returns (uint256[] memory) {
        require(owner != address(0), "Invalid owner address");

        uint256 ownerBalance = balanceOf(owner);
        if (ownerBalance == 0) {
            return new uint256[](0);
        }

        uint256[] memory ownedTokens = new uint256[](ownerBalance);
        uint256 currentIndex = 0;

        for (
            uint256 i = 1;
            i < _nextTokenId && currentIndex < ownerBalance;
            i++
        ) {
            if (_ownerOf(i) == owner) {
                ownedTokens[currentIndex] = i;
                currentIndex++;
            }
        }

        return ownedTokens;
    }

    /**
     * @dev Get total supply
     */
    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @dev Check if token exists
     * @param tokenId Token ID to check
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    // ===== CONVENIENCE FUNCTIONS FOR TESTING =====

    /**
     * @dev Mint test NFTs with predefined categories
     * @param to Address to mint to
     * @param category Category ("music", "art", "literature", "software")
     */
    function mintTestNFT(
        address to,
        string memory category
    ) external whenNotPaused returns (uint256) {
        string memory title;
        string memory description;
        string memory uri;

        if (keccak256(abi.encodePacked(category)) == keccak256("music")) {
            title = "Test Music Track";
            description = "A test music composition for PVM testing";
            uri = "https://test.example.com/music/1";
        } else if (keccak256(abi.encodePacked(category)) == keccak256("art")) {
            title = "Test Digital Art";
            description = "A test digital artwork for PVM testing";
            uri = "https://test.example.com/art/1";
        } else if (
            keccak256(abi.encodePacked(category)) == keccak256("literature")
        ) {
            title = "Test Literary Work";
            description = "A test literary piece for PVM testing";
            uri = "https://test.example.com/literature/1";
        } else if (
            keccak256(abi.encodePacked(category)) == keccak256("software")
        ) {
            title = "Test Software Code";
            description = "A test software component for PVM testing";
            uri = "https://test.example.com/software/1";
        } else {
            title = "Test Copyright Work";
            description = "A test copyright work for PVM testing";
            uri = "https://test.example.com/general/1";
        }

        return this.mintCopyright(to, title, description, category, uri);
    }

    /**
     * @dev Mint multiple test NFTs for comprehensive testing
     * @param to Address to mint to
     */
    function mintTestSuite(
        address to
    ) external whenNotPaused returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](4);

        tokenIds[0] = this.mintCopyright(
            to,
            "Test Music Album",
            "Complete album for testing",
            "music",
            "https://test.example.com/music/album1"
        );
        tokenIds[1] = this.mintCopyright(
            to,
            "Test Digital Painting",
            "Original digital artwork",
            "art",
            "https://test.example.com/art/painting1"
        );
        tokenIds[2] = this.mintCopyright(
            to,
            "Test Novel Chapter",
            "First chapter of test novel",
            "literature",
            "https://test.example.com/literature/novel1"
        );
        tokenIds[3] = this.mintCopyright(
            to,
            "Test Smart Contract",
            "Test contract implementation",
            "software",
            "https://test.example.com/software/contract1"
        );

        return tokenIds;
    }

    // ===== INTERNAL FUNCTIONS =====

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // /**
    //  * @dev Emergency function to recover stuck tokens (if any)
    //  * @param tokenAddress Token contract address
    //  * @param amount Amount to recover
    //  */
    // function emergencyRecoverToken(
    //     address tokenAddress,
    //     uint256 amount
    // ) external onlyOwner {
    //     require(tokenAddress != address(0), "Invalid token address");
    //     IERC20(tokenAddress).transfer(owner(), amount);
    // }

    // ===== OVERRIDES =====

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
