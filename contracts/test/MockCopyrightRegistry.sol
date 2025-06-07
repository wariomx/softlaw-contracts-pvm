// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockCopyrightRegistry
 * @dev Simple registry contract for testing treasury payment functionality
 */
contract MockCopyrightRegistry {
    interface ITreasury {
        function payRegistrationFee(address user, uint256 nftId) external;
    }
    
    ITreasury public treasury;
    mapping(uint256 => address) public registrations;
    mapping(address => uint256[]) public userRegistrations;
    uint256 public totalRegistrations;
    
    event RegistrationCompleted(uint256 indexed nftId, address indexed user);
    
    constructor(address _treasury) {
        treasury = ITreasury(_treasury);
    }
    
    /**
     * @dev Register an NFT and pay the fee through treasury
     * @param nftId NFT ID to register
     */
    function registerAndPay(uint256 nftId) external {
        require(registrations[nftId] == address(0), "NFT already registered");
        
        // Process payment through treasury
        treasury.payRegistrationFee(msg.sender, nftId);
        
        // Complete registration
        registrations[nftId] = msg.sender;
        userRegistrations[msg.sender].push(nftId);
        totalRegistrations++;
        
        emit RegistrationCompleted(nftId, msg.sender);
    }
    
    /**
     * @dev Get all registrations for a user
     * @param user User address
     * @return Array of NFT IDs registered by user
     */
    function getUserRegistrations(address user) external view returns (uint256[] memory) {
        return userRegistrations[user];
    }
    
    /**
     * @dev Check if NFT is registered
     * @param nftId NFT ID to check
     * @return True if registered
     */
    function isRegistered(uint256 nftId) external view returns (bool) {
        return registrations[nftId] != address(0);
    }
    
    /**
     * @dev Get owner of registered NFT
     * @param nftId NFT ID
     * @return Owner address
     */
    function getOwner(uint256 nftId) external view returns (address) {
        return registrations[nftId];
    }
}
