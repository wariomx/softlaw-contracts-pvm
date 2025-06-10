// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SLAWToken (Softlaw Token)
 * @dev PVM-optimized ERC20 token for the Softlaw ecosystem
 * Replaces .send/.transfer with secure .call() pattern
 * Memory-efficient design for Polkadot Virtual Machine
 * Features:
 * - Role-based minting and burning
 * - Treasury integration
 * - Staking and rewards system
 * - Anti-whale mechanisms
 */
contract SLAWToken is ERC20, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Token parameters
    uint256 public constant MAX_SUPPLY = 100_000_000 * 10**18; // 100M SLAW
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18; // 1M SLAW initial
    
    // Anti-whale mechanism
    uint256 public maxTransferAmount = 100_000 * 10**18; // 100K SLAW max transfer
    uint256 public maxWalletAmount = 1_000_000 * 10**18; // 1M SLAW max wallet
    
    // Staking system
    struct StakeInfo {
        uint256 amount;
        uint256 stakingTime;
        uint256 lastRewardClaim;
        uint256 totalRewardsEarned;
    }
    
    mapping(address => StakeInfo) public stakes;
    mapping(address => bool) public isExcludedFromLimits;
    
    uint256 public totalStaked;
    uint256 public stakingRewardRate = 500; // 5% APY in basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
    
    // Treasury and distribution
    address public treasuryWallet;
    uint256 public treasuryReserve;
    
    // Events
    event TokensStaked(address indexed user, uint256 amount);
    event TokensUnstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event LimitsUpdated(uint256 maxTransfer, uint256 maxWallet);
    event SecurePaymentProcessed(address indexed recipient, uint256 amount, bool success);
    event StakingRateUpdated(uint256 oldRate, uint256 newRate);

    constructor(
        address _admin,
        uint256 _initialSupply
    ) ERC20("Softlaw Token", "SLAW") {
        require(_admin != address(0), "Invalid admin address");
        require(_initialSupply <= MAX_SUPPLY, "Initial supply exceeds maximum");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(BURNER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _admin);
        
        treasuryWallet = _admin;
        
        // Mint initial supply
        _mint(_admin, _initialSupply);
        
        // Exclude admin from limits
        isExcludedFromLimits[_admin] = true;
        isExcludedFromLimits[address(this)] = true;
    }
    
    // ===== MINTING AND BURNING =====
    
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "Cannot mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds maximum supply");
        
        _mint(to, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "Burn amount exceeds allowance");
        
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
    
    // ===== STAKING SYSTEM =====
    
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0 tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Claim pending rewards first
        if (stakes[msg.sender].amount > 0) {
            _claimRewards(msg.sender);
        }
        
        // Transfer tokens to contract
        _transfer(msg.sender, address(this), amount);
        
        // Update stake info
        StakeInfo storage userStake = stakes[msg.sender];
        userStake.amount += amount;
        userStake.stakingTime = block.timestamp;
        userStake.lastRewardClaim = block.timestamp;
        
        totalStaked += amount;
        
        emit TokensStaked(msg.sender, amount);
    }
    
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount >= amount, "Insufficient staked amount");
        
        // Claim pending rewards
        _claimRewards(msg.sender);
        
        // Update stake info
        userStake.amount -= amount;
        if (userStake.amount == 0) {
            userStake.stakingTime = 0;
            userStake.lastRewardClaim = 0;
        }
        
        totalStaked -= amount;
        
        // Transfer tokens back to user securely
        _safeTransfer(address(this), msg.sender, amount);
        
        emit TokensUnstaked(msg.sender, amount);
    }
    
    function claimRewards() external nonReentrant whenNotPaused {
        require(stakes[msg.sender].amount > 0, "No staked tokens");
        _claimRewards(msg.sender);
    }
    
    function _claimRewards(address user) internal {
        StakeInfo storage userStake = stakes[user];
        
        if (userStake.amount == 0 || userStake.lastRewardClaim == 0) {
            return;
        }
        
        uint256 stakingDuration = block.timestamp - userStake.lastRewardClaim;
        uint256 rewardAmount = (userStake.amount * stakingRewardRate * stakingDuration) / 
                              (BASIS_POINTS * SECONDS_PER_YEAR);
        
        if (rewardAmount > 0 && totalSupply() + rewardAmount <= MAX_SUPPLY) {
            // Mint rewards
            _mint(user, rewardAmount);
            
            userStake.totalRewardsEarned += rewardAmount;
            userStake.lastRewardClaim = block.timestamp;
            
            emit RewardsClaimed(user, rewardAmount);
        }
    }
    
    function calculatePendingRewards(address user) external view returns (uint256) {
        StakeInfo memory userStake = stakes[user];
        
        if (userStake.amount == 0 || userStake.lastRewardClaim == 0) {
            return 0;
        }
        
        uint256 stakingDuration = block.timestamp - userStake.lastRewardClaim;
        return (userStake.amount * stakingRewardRate * stakingDuration) / 
               (BASIS_POINTS * SECONDS_PER_YEAR);
    }
    
    // ===== SECURE TRANSFER OVERRIDE =====
    
    function _update(address from, address to, uint256 value) internal override {
        // Apply transfer limits (except for excluded addresses)
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            require(value <= maxTransferAmount, "Transfer exceeds limit");
            
            // Check wallet limit for recipients
            if (to != address(0) && balanceOf(to) + value > maxWalletAmount) {
                require(false, "Recipient wallet exceeds limit");
            }
        }
        
        super._update(from, to, value);
    }
    
    // ===== SECURE TRANSFER FUNCTIONS (Replacement for .send/.transfer) =====
    
    function _safeTransfer(address from, address to, uint256 amount) internal {
        if (amount == 0) return;
        
        if (from == address(this)) {
            // Transfer from contract
            _transfer(from, to, amount);
        } else {
            // Use transferFrom for external transfers
            (bool success, bytes memory data) = address(this).call(
                abi.encodeWithSelector(this.transferFrom.selector, from, to, amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
        }
        
        emit SecurePaymentProcessed(to, amount, true);
    }
    
    // ===== TREASURY FUNCTIONS =====
    
    function transferToTreasury(uint256 amount) external onlyRole(TREASURY_ROLE) {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _transfer(msg.sender, treasuryWallet, amount);
        treasuryReserve += amount;
    }
    
    function distributeTreasuryFunds(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(TREASURY_ROLE) {
        require(recipients.length == amounts.length, "Array length mismatch");
        require(recipients.length <= 50, "Too many recipients"); // PVM gas limit
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        require(totalAmount <= treasuryReserve, "Insufficient treasury reserve");
        require(balanceOf(treasuryWallet) >= totalAmount, "Insufficient treasury balance");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0 && recipients[i] != address(0)) {
                _transfer(treasuryWallet, recipients[i], amounts[i]);
                treasuryReserve -= amounts[i];
            }
        }
    }
    
    // ===== VIEW FUNCTIONS =====
    
    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakes[user];
    }
    
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }
    
    function getStakingAPY() external view returns (uint256) {
        return stakingRewardRate; // Returns basis points (500 = 5%)
    }
    
    function getTokenStats() external view returns (
        uint256 currentSupply,
        uint256 maxSupply,
        uint256 totalStaked_,
        uint256 circulatingSupply,
        uint256 stakingAPY
    ) {
        currentSupply = totalSupply();
        maxSupply = MAX_SUPPLY;
        totalStaked_ = totalStaked;
        circulatingSupply = currentSupply - totalStaked;
        stakingAPY = stakingRewardRate;
    }
    
    // ===== ADMIN FUNCTIONS =====
    
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    function updateTreasuryWallet(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury address");
        
        address oldTreasury = treasuryWallet;
        treasuryWallet = newTreasury;
        
        // Update exclusions
        isExcludedFromLimits[newTreasury] = true;
        isExcludedFromLimits[oldTreasury] = false;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    function updateTransferLimits(
        uint256 newMaxTransfer,
        uint256 newMaxWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMaxTransfer > 0, "Max transfer must be > 0");
        require(newMaxWallet > 0, "Max wallet must be > 0");
        require(newMaxTransfer <= MAX_SUPPLY, "Max transfer exceeds supply");
        require(newMaxWallet <= MAX_SUPPLY, "Max wallet exceeds supply");
        
        maxTransferAmount = newMaxTransfer;
        maxWalletAmount = newMaxWallet;
        
        emit LimitsUpdated(newMaxTransfer, newMaxWallet);
    }
    
    function updateStakingRewardRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRate <= 2000, "Rate too high"); // Max 20% APY
        
        uint256 oldRate = stakingRewardRate;
        stakingRewardRate = newRate;
        
        emit StakingRateUpdated(oldRate, newRate);
    }
    
    function excludeFromLimits(address account, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(account != address(0), "Invalid account");
        isExcludedFromLimits[account] = excluded;
    }
    
    // ===== EMERGENCY FUNCTIONS =====
    
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        
        if (token == address(this)) {
            // Emergency withdraw SLAW tokens
            _transfer(address(this), to, amount);
        } else if (token != address(0)) {
            // Emergency withdraw other ERC20 tokens
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
        }
    }
    
    // ===== GOVERNANCE INTEGRATION =====
    
    function getVotingPower(address account) external view returns (uint256) {
        // Voting power = balance + staked amount
        return balanceOf(account) + stakes[account].amount;
    }
    
    function delegate(address delegatee) external {
        // Placeholder for delegation functionality
        // Can be implemented with OpenZeppelin's ERC20Votes in future versions
        require(delegatee != address(0), "Invalid delegatee");
        // Implementation would go here
    }
    
    // ===== RECEIVE FUNCTION =====
    
    receive() external payable {
        // Allow contract to receive native tokens for cross-chain operations
        revert("Direct ETH transfers not supported");
    }
}
