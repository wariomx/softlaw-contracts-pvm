// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockCopyrightNFT
 * @dev Simple NFT contract for testing IP wrapping functionality
 */
contract MockCopyrightNFT is ERC721 {
    uint256 private _tokenIdCounter = 0;
    mapping(uint256 => string) private _tokenMetadata;
    
    event TokenMinted(uint256 indexed tokenId, address indexed to, string metadata);
    
    constructor() ERC721("Mock Copyright NFT", "MCR") {}
    
    function mint(address to, string memory metadata) public returns (uint256) {
        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;
        
        _mint(to, tokenId);
        _tokenMetadata[tokenId] = metadata;
        
        emit TokenMinted(tokenId, to, metadata);
        return tokenId;
    }
    
    function getMetadata(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _tokenMetadata[tokenId];
    }
    
    function getCurrentTokenId() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    // Override tokenURI for testing
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return string(abi.encodePacked("https://mock-metadata.com/", Strings.toString(tokenId)));
    }
}
