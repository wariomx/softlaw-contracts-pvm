// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/ISoftlawTreasury.sol";

/**
 * @title PatentRegistry
 * @dev Complete patent registration and management system with Treasury integration
 * Features:
 * - Patent NFT minting with comprehensive metadata
 * - Prior art validation system
 * - Patent lifecycle management (filing, examination, granted, expired)
 * - Integration with Treasury for SLAW payments
 * - Automatic tokenization capabilities
 * - Patent portfolio management
 */
contract PatentRegistry is ERC721URIStorage, ERC2981, Ownable, ReentrancyGuard, Pausable {
    
    ISoftlawTreasury public immutable treasury;
    
    // Patent lifecycle states
    enum PatentStatus {
        FILED,           // Patent application filed
        UNDER_EXAMINATION, // Under patent office review
        GRANTED,         // Patent granted
        EXPIRED,         // Patent expired
        ABANDONED,       // Patent abandoned
        REJECTED         // Patent rejected
    }

    // Patent classification
    enum PatentType {
        UTILITY,         // Utility patent
        DESIGN,          // Design patent
        PLANT,           // Plant patent
        PROVISIONAL      // Provisional patent
    }

    // Comprehensive patent structure
    struct Patent {
        string title;
        string description;
        string[] claims;
        string[] keywords;
        string inventorName;
        address inventorAddress;
        address currentOwner;
        PatentType patentType;
        PatentStatus status;
        uint256 filingDate;
        uint256 publicationDate;
        uint256 grantDate;
        uint256 expirationDate;
        string patentOffice; // USPTO, EPO, JPO, etc.
        string applicationNumber;
        string patentNumber;
        uint256 maintenanceFeesDue;
        bool isTokenized;
        address wrappedToken;
        string documentHash; // IPFS hash of patent documents
        uint256 priorArtCount;
        mapping(uint256 => string) priorArt; // Prior art references
    }

    // Storage
    mapping(uint256 => Patent) public patents;
    mapping(address => uint256[]) public inventorPatents;
    mapping(string => uint256) public applicationNumbers; // Application number to patent ID
    mapping(string => uint256) public patentNumbers; // Patent number to patent ID
    mapping(string => bool) public usedApplicationNumbers;
    
    uint256 public patentCounter = 1;
    
    // Fees (in SLAW tokens)
    uint256 public constant FILING_FEE = 200 * 10**18; // 200 SLAW
    uint256 public constant EXAMINATION_FEE = 150 * 10**18; // 150 SLAW
    uint256 public constant GRANT_FEE = 100 * 10**18; // 100 SLAW
    uint256 public constant MAINTENANCE_FEE = 75 * 10**18; // 75 SLAW (annual)
    uint256 public constant TOKENIZATION_REWARD = 300 * 10**18; // 300 SLAW

    // Events
    event PatentFiled(
        uint256 indexed patentId,
        address indexed inventor,
        string title,
        string applicationNumber
    );
    
    event PatentStatusUpdated(
        uint256 indexed patentId,
        PatentStatus oldStatus,
        PatentStatus newStatus
    );
    
    event PatentGranted(
        uint256 indexed patentId,
        string patentNumber,
        uint256 expirationDate
    );
    
    event PatentTokenized(
        uint256 indexed patentId,
        address indexed wrappedToken,
        uint256 totalSupply
    );
    
    event MaintenanceFeePaid(
        uint256 indexed patentId,
        address indexed payer,
        uint256 amount
    );
    
    event PriorArtAdded(
        uint256 indexed patentId,
        uint256 indexed priorArtIndex,
        string reference
    );

    constructor(
        address _treasury,
        address _owner
    ) ERC721("Softlaw Patent", "SLPAT") Ownable(_owner) {
        treasury = ISoftlawTreasury(_treasury);
    }

    /**
     * @dev File a new patent application
     * @param title Patent title
     * @param description Detailed description
     * @param claims Array of patent claims
     * @param keywords Search keywords
     * @param inventorName Name of inventor
     * @param patentType Type of patent
     * @param patentOffice Patent office (USPTO, EPO, etc.)
     * @param documentHash IPFS hash of patent documents
     * @param priorArtReferences Array of prior art references
     */
    function filePatent(
        string memory title,
        string memory description,
        string[] memory claims,
        string[] memory keywords,
        string memory inventorName,
        PatentType patentType,
        string memory patentOffice,
        string memory documentHash,
        string[] memory priorArtReferences
    ) external nonReentrant whenNotPaused returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(description).length > 0, "Description required");
        require(claims.length > 0, "At least one claim required");
        require(bytes(inventorName).length > 0, "Inventor name required");

        // Pay filing fee through Treasury
        treasury.payRegistrationFee(msg.sender, 0); // Use 0 as placeholder, will be updated

        uint256 patentId = patentCounter++;
        
        // Generate application number
        string memory applicationNumber = _generateApplicationNumber(patentId, patentOffice);
        require(!usedApplicationNumbers[applicationNumber], "Application number collision");

        // Create patent NFT
        _mint(msg.sender, patentId);
        _setTokenURI(patentId, _buildTokenURI(patentId, title, description));

        // Initialize patent data
        Patent storage patent = patents[patentId];
        patent.title = title;
        patent.description = description;
        patent.claims = claims;
        patent.keywords = keywords;
        patent.inventorName = inventorName;
        patent.inventorAddress = msg.sender;
        patent.currentOwner = msg.sender;
        patent.patentType = patentType;
        patent.status = PatentStatus.FILED;
        patent.filingDate = block.timestamp;
        patent.patentOffice = patentOffice;
        patent.applicationNumber = applicationNumber;
        patent.documentHash = documentHash;
        patent.priorArtCount = priorArtReferences.length;

        // Add prior art references
        for (uint256 i = 0; i < priorArtReferences.length; i++) {
            patent.priorArt[i] = priorArtReferences[i];
        }

        // Update mappings
        inventorPatents[msg.sender].push(patentId);
        applicationNumbers[applicationNumber] = patentId;
        usedApplicationNumbers[applicationNumber] = true;

        // Set royalty (2.5% to inventor)
        _setTokenRoyalty(patentId, msg.sender, 250);

        emit PatentFiled(patentId, msg.sender, title, applicationNumber);
        
        return patentId;
    }

    /**
     * @dev Move patent to examination phase (patent office function)
     * @param patentId Patent ID
     */
    function moveToExamination(uint256 patentId) external onlyOwner {
        Patent storage patent = patents[patentId];
        require(patent.status == PatentStatus.FILED, "Patent not in filed status");

        // Charge examination fee
        treasury.payLicenseFee(
            address(0),
            patent.currentOwner,
            patentId,
            EXAMINATION_FEE
        );

        PatentStatus oldStatus = patent.status;
        patent.status = PatentStatus.UNDER_EXAMINATION;

        emit PatentStatusUpdated(patentId, oldStatus, PatentStatus.UNDER_EXAMINATION);
    }

    /**
     * @dev Grant patent (patent office function)
     * @param patentId Patent ID
     * @param patentNumber Official patent number
     * @param expirationYears Years until expiration (typically 20)
     */
    function grantPatent(
        uint256 patentId,
        string memory patentNumber,
        uint256 expirationYears
    ) external onlyOwner {
        Patent storage patent = patents[patentId];
        require(patent.status == PatentStatus.UNDER_EXAMINATION, "Patent not under examination");
        require(bytes(patentNumber).length > 0, "Patent number required");

        // Charge grant fee
        treasury.payLicenseFee(
            address(0),
            patent.currentOwner,
            patentId,
            GRANT_FEE
        );

        patent.status = PatentStatus.GRANTED;
        patent.grantDate = block.timestamp;
        patent.expirationDate = block.timestamp + (expirationYears * 365 days);
        patent.patentNumber = patentNumber;

        patentNumbers[patentNumber] = patentId;

        // Reward for successful patent grant
        treasury.distributeIncentives(
            _asSingletonArray(patent.currentOwner),
            _asSingletonArray(TOKENIZATION_REWARD)
        );

        emit PatentGranted(patentId, patentNumber, patent.expirationDate);
        emit PatentStatusUpdated(patentId, PatentStatus.UNDER_EXAMINATION, PatentStatus.GRANTED);
    }

    /**
     * @dev Pay maintenance fees to keep patent active
     * @param patentId Patent ID
     */
    function payMaintenanceFee(uint256 patentId) external nonReentrant {
        Patent storage patent = patents[patentId];
        require(patent.status == PatentStatus.GRANTED, "Patent not granted");
        require(block.timestamp < patent.expirationDate, "Patent expired");

        // Pay maintenance fee through Treasury
        treasury.payLicenseFee(
            address(0),
            msg.sender,
            patentId,
            MAINTENANCE_FEE
        );

        patent.maintenanceFeesDue = block.timestamp + 365 days; // Next fee due in 1 year

        emit MaintenanceFeePaid(patentId, msg.sender, MAINTENANCE_FEE);
    }

    /**
     * @dev Tokenize patent into wrapped tokens
     * @param patentId Patent ID
     * @param totalSupply Total supply of wrapped tokens
     * @param pricePerToken Price per token in SLAW
     * @param metadata Additional metadata
     */
    function tokenizePatent(
        uint256 patentId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string memory metadata
    ) external nonReentrant returns (address) {
        require(ownerOf(patentId) == msg.sender, "Not patent owner");
        Patent storage patent = patents[patentId];
        require(patent.status == PatentStatus.GRANTED, "Patent not granted");
        require(!patent.isTokenized, "Patent already tokenized");

        // Approve treasury to handle the NFT
        approve(address(treasury), patentId);

        // Create wrapped token through Treasury
        address wrappedToken = treasury.wrapCopyrightNFT(
            address(this),
            patentId,
            totalSupply,
            pricePerToken,
            metadata
        );

        patent.isTokenized = true;
        patent.wrappedToken = wrappedToken;

        // Extra tokenization reward for patents (more complex than copyrights)
        treasury.distributeIncentives(
            _asSingletonArray(msg.sender),
            _asSingletonArray(TOKENIZATION_REWARD)
        );

        emit PatentTokenized(patentId, wrappedToken, totalSupply);

        return wrappedToken;
    }

    /**
     * @dev Add prior art reference
     * @param patentId Patent ID
     * @param priorArtReference Prior art reference
     */
    function addPriorArt(uint256 patentId, string memory priorArtReference) external {
        Patent storage patent = patents[patentId];
        require(
            msg.sender == patent.inventorAddress || msg.sender == owner(),
            "Not authorized"
        );

        uint256 index = patent.priorArtCount;
        patent.priorArt[index] = priorArtReference;
        patent.priorArtCount++;

        emit PriorArtAdded(patentId, index, priorArtReference);
    }

    /**
     * @dev Get comprehensive patent information
     * @param patentId Patent ID
     */
    function getPatentInfo(uint256 patentId) external view returns (
        string memory title,
        string memory description,
        string[] memory claims,
        address currentOwner,
        PatentType patentType,
        PatentStatus status,
        uint256 filingDate,
        uint256 expirationDate,
        bool isTokenized,
        address wrappedToken
    ) {
        Patent storage patent = patents[patentId];
        return (
            patent.title,
            patent.description,
            patent.claims,
            patent.currentOwner,
            patent.patentType,
            patent.status,
            patent.filingDate,
            patent.expirationDate,
            patent.isTokenized,
            patent.wrappedToken
        );
    }

    /**
     * @dev Get patent claims
     * @param patentId Patent ID
     */
    function getPatentClaims(uint256 patentId) external view returns (string[] memory) {
        return patents[patentId].claims;
    }

    /**
     * @dev Get prior art references
     * @param patentId Patent ID
     */
    function getPriorArt(uint256 patentId) external view returns (string[] memory) {
        Patent storage patent = patents[patentId];
        string[] memory priorArtArray = new string[](patent.priorArtCount);
        
        for (uint256 i = 0; i < patent.priorArtCount; i++) {
            priorArtArray[i] = patent.priorArt[i];
        }
        
        return priorArtArray;
    }

    /**
     * @dev Get patents by inventor
     * @param inventor Inventor address
     */
    function getPatentsByInventor(address inventor) external view returns (uint256[] memory) {
        return inventorPatents[inventor];
    }

    /**
     * @dev Check if patent needs maintenance fee
     * @param patentId Patent ID
     */
    function needsMaintenanceFee(uint256 patentId) external view returns (bool) {
        Patent storage patent = patents[patentId];
        return patent.status == PatentStatus.GRANTED && 
               block.timestamp >= patent.maintenanceFeesDue &&
               block.timestamp < patent.expirationDate;
    }

    /**
     * @dev Search patents by keyword
     * @param keyword Search keyword
     */
    function searchPatentsByKeyword(string memory keyword) external view returns (uint256[] memory) {
        // Note: This is a simplified search. In production, you'd use a more sophisticated indexing system
        uint256[] memory results = new uint256[](patentCounter - 1);
        uint256 resultCount = 0;

        for (uint256 i = 1; i < patentCounter; i++) {
            Patent storage patent = patents[i];
            for (uint256 j = 0; j < patent.keywords.length; j++) {
                if (keccak256(bytes(patent.keywords[j])) == keccak256(bytes(keyword))) {
                    results[resultCount] = i;
                    resultCount++;
                    break;
                }
            }
        }

        // Resize array to actual results
        uint256[] memory finalResults = new uint256[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            finalResults[i] = results[i];
        }

        return finalResults;
    }

    // ===== INTERNAL FUNCTIONS =====

    function _generateApplicationNumber(
        uint256 patentId,
        string memory patentOffice
    ) internal view returns (string memory) {
        return string(abi.encodePacked(
            patentOffice,
            "-",
            Strings.toString(block.timestamp),
            "-",
            Strings.toString(patentId)
        ));
    }

    function _buildTokenURI(
        uint256 patentId,
        string memory title,
        string memory description
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(bytes(abi.encodePacked(
                '{"name":"Patent #', Strings.toString(patentId), 
                '","description":"', description,
                '","title":"', title,
                '","attributes":[{"trait_type":"Type","value":"Patent"}]}'
            )))
        ));
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

    // ===== OVERRIDES =====

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            // Update current owner in patent data
            patents[tokenId].currentOwner = to;
        }
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721URIStorage, ERC2981) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function updatePatentStatus(uint256 patentId, PatentStatus newStatus) external onlyOwner {
        PatentStatus oldStatus = patents[patentId].status;
        patents[patentId].status = newStatus;
        emit PatentStatusUpdated(patentId, oldStatus, newStatus);
    }
}

// Helper library for base64 encoding
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        uint256 encodedLen = 4 * ((len + 2) / 3);

        bytes memory result = new bytes(encodedLen + 32);

        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {

            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)

                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)

                mstore(resultPtr, out)

                resultPtr := add(resultPtr, 4)
            }

            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }

            mstore(result, encodedLen)
        }

        return string(result);
    }
}
