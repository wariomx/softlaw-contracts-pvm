// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SLAWToken.sol";
import "./WrappedIPManager.sol";

/**
 * @title ValuedLiquidityPair
 * @dev Enhanced LP token with creator branding and value tracking
 */
contract ValuedLiquidityPair is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    address public immutable factory;
    address public immutable token0; // SLAW
    address public immutable token1; // Wrapped IP
    
    // Enhanced pool information
    string public creatorName;
    string public ipTitle;
    address public creator;
    uint256 public poolValue; // Total value in SLAW terms
    uint256 public createdAt;
    
    // Pool metrics
    uint112 private reserve0; // SLAW reserves
    uint112 private reserve1; // Wrapped IP reserves
    uint32 private blockTimestampLast;
    
    uint256 public totalVolume; // Total trading volume
    uint256 public totalFees; // Total fees collected
    uint256 public swapCount; // Number of swaps
    
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    
    // Rewards tracking
    mapping(address => uint256) public rewardsEarned;
    mapping(address => uint256) public lastRewardClaim;
    uint256 public totalRewardsDistributed;
    
    event Mint(address indexed to, uint256 amount, uint256 value);
    event Burn(address indexed to, uint256 amount0, uint256 amount1, uint256 value);
    event Swap(
        address indexed to, 
        uint256 amount0In, 
        uint256 amount1In, 
        uint256 amount0Out, 
        uint256 amount1Out,
        uint256 volume
    );
    event Sync(uint112 reserve0, uint112 reserve1, uint256 poolValue);
    event RewardsClaimed(address indexed user, uint256 amount);
    
    constructor() {
        factory = msg.sender;
        (token0, token1) = (address(0), address(0)); // Will be set by factory
    }
    
    function initialize(
        address _token0, 
        address _token1, 
        string memory _name, 
        string memory _symbol,
        string memory _creatorName,
        string memory _ipTitle,
        address _creator
    ) external {
        require(msg.sender == factory, "Only factory");
        require(token0 == address(0), "Already initialized");
        
        token0 = _token0; // SLAW
        token1 = _token1; // Wrapped IP
        name = _name;
        symbol = _symbol;
        creatorName = _creatorName;
        ipTitle = _ipTitle;
        creator = _creator;
        createdAt = block.timestamp;
    }
    
    function getReserves() external view returns (
        uint112 _reserve0, 
        uint112 _reserve1, 
        uint32 _blockTimestampLast
    ) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
    
    function getPoolMetrics() external view returns (
        uint256 _poolValue,
        uint256 _totalVolume,
        uint256 _totalFees,
        uint256 _swapCount,
        uint256 _totalRewards,
        uint256 _age
    ) {
        _poolValue = poolValue;
        _totalVolume = totalVolume;
        _totalFees = totalFees;
        _swapCount = _swapCount;
        _totalRewards = totalRewardsDistributed;
        _age = block.timestamp - createdAt;
    }
    
    function mint(address to) external returns (uint256 liquidity) {
        require(msg.sender == factory, "Only factory");
        
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        
        if (_totalSupply == 0) {
            liquidity = _sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = _min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        
        require(liquidity > 0, "Insufficient liquidity minted");
        _mint(to, liquidity);
        
        // Calculate pool value (in SLAW terms)
        uint256 value = amount0; // SLAW amount
        if (amount1 > 0) {
            // Add IP token value (approximate based on current reserves ratio)
            value += (amount1 * _reserve0) / (_reserve1 > 0 ? _reserve1 : 1);
        }
        poolValue += value;
        
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(to, liquidity, value);
    }
    
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == factory, "Only factory");
        
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));
        
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");
        
        _burn(address(this), liquidity);
        IERC20(_token0).transfer(to, amount0);
        IERC20(_token1).transfer(to, amount1);
        
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        
        // Update pool value
        uint256 removedValue = amount0; // SLAW amount
        if (amount1 > 0 && _reserve1 > 0) {
            removedValue += (amount1 * _reserve0) / _reserve1;
        }
        poolValue = poolValue > removedValue ? poolValue - removedValue : 0;
        
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(to, amount0, amount1, removedValue);
    }
    
    function swap(
        uint256 amount0Out, 
        uint256 amount1Out, 
        address to
    ) external {
        require(msg.sender == factory, "Only factory");
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output amount");
        
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Insufficient liquidity");
        
        if (amount0Out > 0) IERC20(token0).transfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).transfer(to, amount1Out);
        
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "Insufficient input amount");
        
        // Calculate trading volume in SLAW terms
        uint256 volume = amount0In; // Direct SLAW volume
        if (amount1In > 0 && _reserve0 > 0 && _reserve1 > 0) {
            volume += (amount1In * _reserve0) / _reserve1; // Convert IP tokens to SLAW value
        }
        
        totalVolume += volume;
        swapCount++;
        
        // Apply 0.3% fee
        uint256 fee = volume * 3 / 1000;
        totalFees += fee;
        
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(to, amount0In, amount1In, amount0Out, amount1Out, volume);
    }
    
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        
        // Update pool value based on current reserves
        if (balance1 > 0) {
            poolValue = balance0 * 2; // Approximate total value
        } else {
            poolValue = balance0;
        }
        
        emit Sync(reserve0, reserve1, poolValue);
    }
    
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
    
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }
    
    // Standard ERC20 functions
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(from, msg.sender, currentAllowance - amount);
        }
        _transfer(from, to, amount);
        return true;
    }
    
    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function _burn(address from, uint256 amount) internal {
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

/**
 * @title LiquidityManager
 * @dev Enhanced liquidity pools for Wrapped IP tokens + SLAW with value tracking
 * Features:
 * - Creator-branded LP tokens
 * - Value tracking and metrics
 * - Reward distribution
 * - Pool rankings and analytics
 */
contract LiquidityManager is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant LIQUIDITY_ADMIN = keccak256("LIQUIDITY_ADMIN");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // System contracts
    SLAWToken public immutable slawToken;
    WrappedIPManager public immutable wrappedIPManager;
    address public treasuryCore;
    
    // Enhanced pool tracking
    struct PoolInfo {
        address pairAddress;
        address wrappedIPToken;
        address creator;
        string creatorName;
        string ipTitle;
        uint256 totalLiquidity;
        uint256 totalVolume;
        uint256 poolValue; // Total value in SLAW
        uint256 createdAt;
        bool isActive;
        bool isFeatured; // Featured pools get higher visibility
        uint256 rewardMultiplier; // Bonus rewards (100 = 1x, 200 = 2x)
    }
    
    // Pool rankings and metrics
    struct PoolMetrics {
        uint256 apy; // Estimated APY in basis points
        uint256 dailyVolume;
        uint256 weeklyVolume;
        uint256 liquidityProviders;
        uint256 totalFees;
        uint256 ranking;
    }
    
    mapping(address => PoolInfo) public pools; // wrappedIPToken => PoolInfo
    mapping(address => address) public getWrappedIPToken; // pairAddress => wrappedIPToken
    mapping(address => PoolMetrics) public poolMetrics; // pairAddress => metrics
    address[] public allPairs;
    address[] public featuredPairs;
    
    // Rewards system
    mapping(address => uint256) public poolRewardRates; // pairAddress => SLAW per block
    mapping(address => mapping(address => uint256)) public userRewards; // pair => user => pending rewards
    mapping(address => mapping(address => uint256)) public lastRewardUpdate; // pair => user => block
    
    // Creator incentives
    mapping(address => uint256) public creatorBonuses; // creator => total bonuses earned
    mapping(address => uint256) public creatorPoolCount; // creator => number of pools
    
    // System metrics
    uint256 public totalPools;
    uint256 public totalLiquidity;
    uint256 public totalVolume;
    uint256 public totalRewardsDistributed;
    
    // Events
    event PoolCreated(
        address indexed wrappedIPToken,
        address indexed pairAddress,
        address indexed creator,
        string creatorName,
        string ipTitle,
        uint256 slawAmount,
        uint256 ipAmount,
        uint256 poolValue
    );
    
    event LiquidityAdded(
        address indexed pairAddress,
        address indexed provider,
        uint256 slawAmount,
        uint256 ipAmount,
        uint256 liquidityMinted,
        uint256 totalValue
    );
    
    event LiquidityRemoved(
        address indexed pairAddress,
        address indexed provider,
        uint256 slawAmount,
        uint256 ipAmount,
        uint256 liquidityBurned,
        uint256 totalValue
    );
    
    event PoolFeatured(address indexed pairAddress, bool featured);
    event RewardsDistributed(address indexed user, address indexed pair, uint256 amount);
    event CreatorBonusPaid(address indexed creator, uint256 amount, string reason);

    constructor(
        address _admin,
        address _slawToken,
        address _wrappedIPManager,
        address _treasuryCore
    ) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_wrappedIPManager != address(0), "Invalid WrappedIPManager");
        require(_treasuryCore != address(0), "Invalid treasury core");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(LIQUIDITY_ADMIN, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);
        
        slawToken = SLAWToken(_slawToken);
        wrappedIPManager = WrappedIPManager(_wrappedIPManager);
        treasuryCore = _treasuryCore;
    }

    // ===== POOL CREATION =====

    /**
     * @dev Create a new liquidity pool for Wrapped IP + SLAW with creator branding
     * @param wrappedIPToken Address of the wrapped IP token
     * @param slawAmount Amount of SLAW to add initially
     * @param ipAmount Amount of IP tokens to add initially
     */
    function createPool(
        address wrappedIPToken,
        uint256 slawAmount,
        uint256 ipAmount
    ) external nonReentrant whenNotPaused returns (address pairAddress) {
        require(wrappedIPToken != address(0), "Invalid IP token");
        require(wrappedIPToken != address(slawToken), "Cannot pair with SLAW");
        require(pools[wrappedIPToken].pairAddress == address(0), "Pool already exists");
        require(slawAmount > 0 && ipAmount > 0, "Amounts must be > 0");
        
        // Get creator info from WrappedIPManager
        WrappedIPManager.WrappedIPInfo memory ipInfo = wrappedIPManager.getWrappedIPInfoByToken(wrappedIPToken);
        require(ipInfo.tokenAddress != address(0), "Invalid wrapped IP token");
        
        // Deploy new valued pair contract
        ValuedLiquidityPair pair = new ValuedLiquidityPair();
        
        // Create enhanced pair name with creator branding
        string memory pairName = string(abi.encodePacked(
            ipInfo.creatorName, "'s ", ipInfo.ipTitle, " / SLAW LP"
        ));
        string memory pairSymbol = string(abi.encodePacked(
            "LP-", ipInfo.creatorName, "-", ipInfo.ipTitle
        ));
        
        // Initialize pair with creator info
        pair.initialize(
            address(slawToken), 
            wrappedIPToken, 
            pairName, 
            pairSymbol,
            ipInfo.creatorName,
            ipInfo.ipTitle,
            ipInfo.creator
        );
        
        pairAddress = address(pair);
        
        // Transfer tokens to pair
        require(slawToken.transferFrom(msg.sender, pairAddress, slawAmount), "SLAW transfer failed");
        require(IERC20(wrappedIPToken).transferFrom(msg.sender, pairAddress, ipAmount), "IP token transfer failed");
        
        // Mint initial LP tokens
        uint256 liquidityMinted = pair.mint(msg.sender);
        
        // Calculate initial pool value
        uint256 poolValue = slawAmount * 2; // Approximate total value (both sides)
        
        // Store pool info with creator branding
        pools[wrappedIPToken] = PoolInfo({
            pairAddress: pairAddress,
            wrappedIPToken: wrappedIPToken,
            creator: ipInfo.creator,
            creatorName: ipInfo.creatorName,
            ipTitle: ipInfo.ipTitle,
            totalLiquidity: slawAmount + ipAmount,
            totalVolume: 0,
            poolValue: poolValue,
            createdAt: block.timestamp,
            isActive: true,
            isFeatured: false,
            rewardMultiplier: 100 // 1x base rewards
        });
        
        // Initialize pool metrics
        poolMetrics[pairAddress] = PoolMetrics({
            apy: 0,
            dailyVolume: 0,
            weeklyVolume: 0,
            liquidityProviders: 1,
            totalFees: 0,
            ranking: 0
        });
        
        getWrappedIPToken[pairAddress] = wrappedIPToken;
        allPairs.push(pairAddress);
        
        // Set initial reward rate based on pool value
        poolRewardRates[pairAddress] = _calculateRewardRate(poolValue);
        
        // Update system metrics
        totalPools++;
        totalLiquidity += poolValue;
        creatorPoolCount[ipInfo.creator]++;
        
        // Give creator bonus for creating first pool
        if (creatorPoolCount[ipInfo.creator] == 1) {
            uint256 creatorBonus = slawAmount / 100; // 1% bonus
            _distributeCreatorBonus(ipInfo.creator, creatorBonus, "FIRST_POOL_CREATED");
        }
        
        emit PoolCreated(
            wrappedIPToken, 
            pairAddress, 
            ipInfo.creator, 
            ipInfo.creatorName, 
            ipInfo.ipTitle, 
            slawAmount, 
            ipAmount, 
            poolValue
        );
        
        emit LiquidityAdded(pairAddress, msg.sender, slawAmount, ipAmount, liquidityMinted, poolValue);
    }

    // ===== LIQUIDITY MANAGEMENT =====

    /**
     * @dev Add liquidity to existing pool with reward tracking
     */
    function addLiquidity(
        address wrappedIPToken,
        uint256 slawAmount,
        uint256 ipAmount
    ) external nonReentrant whenNotPaused returns (uint256 liquidityMinted) {
        PoolInfo storage pool = pools[wrappedIPToken];
        require(pool.isActive, "Pool not active");
        require(slawAmount > 0 && ipAmount > 0, "Amounts must be > 0");
        
        ValuedLiquidityPair pair = ValuedLiquidityPair(pool.pairAddress);
        
        // Update rewards before adding liquidity
        _updateUserRewards(pool.pairAddress, msg.sender);
        
        // Transfer tokens to pair
        require(slawToken.transferFrom(msg.sender, pool.pairAddress, slawAmount), "SLAW transfer failed");
        require(IERC20(wrappedIPToken).transferFrom(msg.sender, pool.pairAddress, ipAmount), "IP token transfer failed");
        
        // Mint LP tokens
        liquidityMinted = pair.mint(msg.sender);
        
        // Update pool info
        uint256 addedValue = slawAmount * 2; // Approximate added value
        pool.totalLiquidity += (slawAmount + ipAmount);
        pool.poolValue += addedValue;
        totalLiquidity += addedValue;
        
        // Update metrics
        PoolMetrics storage metrics = poolMetrics[pool.pairAddress];
        metrics.liquidityProviders++;
        
        // Creator bonus for attracting liquidity
        uint256 creatorBonus = addedValue / 1000; // 0.1% bonus
        if (creatorBonus > 0) {
            _distributeCreatorBonus(pool.creator, creatorBonus, "LIQUIDITY_ATTRACTED");
        }
        
        emit LiquidityAdded(pool.pairAddress, msg.sender, slawAmount, ipAmount, liquidityMinted, addedValue);
    }

    /**
     * @dev Remove liquidity from pool with reward claiming
     */
    function removeLiquidity(
        address wrappedIPToken,
        uint256 liquidityAmount
    ) external nonReentrant whenNotPaused returns (uint256 slawAmount, uint256 ipAmount) {
        PoolInfo storage pool = pools[wrappedIPToken];
        require(pool.isActive, "Pool not active");
        require(liquidityAmount > 0, "Amount must be > 0");
        
        ValuedLiquidityPair pair = ValuedLiquidityPair(pool.pairAddress);
        
        // Claim pending rewards before removing liquidity
        _claimUserRewards(pool.pairAddress, msg.sender);
        
        // Transfer LP tokens to pair for burning
        require(pair.transferFrom(msg.sender, pool.pairAddress, liquidityAmount), "LP transfer failed");
        
        // Burn LP tokens and get underlying assets
        (slawAmount, ipAmount) = pair.burn(msg.sender);
        
        // Update pool info
        uint256 removedValue = slawAmount * 2; // Approximate removed value
        pool.totalLiquidity = pool.totalLiquidity > (slawAmount + ipAmount) ? 
            pool.totalLiquidity - (slawAmount + ipAmount) : 0;
        pool.poolValue = pool.poolValue > removedValue ? pool.poolValue - removedValue : 0;
        totalLiquidity = totalLiquidity > removedValue ? totalLiquidity - removedValue : 0;
        
        emit LiquidityRemoved(pool.pairAddress, msg.sender, slawAmount, ipAmount, liquidityAmount, removedValue);
    }

    // ===== REWARDS SYSTEM =====

    /**
     * @dev Calculate reward rate based on pool value and multipliers
     */
    function _calculateRewardRate(uint256 poolValue) internal pure returns (uint256) {
        // Base rate: 0.01% of pool value per block
        uint256 baseRate = poolValue / 10000;
        return baseRate > 0 ? baseRate : 1 ether; // Minimum 1 SLAW per block
    }

    /**
     * @dev Update user rewards for a pool
     */
    function _updateUserRewards(address pairAddress, address user) internal {
        ValuedLiquidityPair pair = ValuedLiquidityPair(pairAddress);
        uint256 userBalance = pair.balanceOf(user);
        
        if (userBalance > 0) {
            uint256 blocksSinceUpdate = block.number - lastRewardUpdate[pairAddress][user];
            if (blocksSinceUpdate > 0) {
                uint256 totalLP = pair.totalSupply();
                if (totalLP > 0) {
                    uint256 rewardRate = poolRewardRates[pairAddress];
                    PoolInfo memory pool = pools[getWrappedIPToken[pairAddress]];
                    
                    // Apply reward multiplier
                    uint256 multipliedRate = (rewardRate * pool.rewardMultiplier) / 100;
                    
                    uint256 userReward = (multipliedRate * blocksSinceUpdate * userBalance) / totalLP;
                    userRewards[pairAddress][user] += userReward;
                }
            }
        }
        
        lastRewardUpdate[pairAddress][user] = block.number;
    }

    /**
     * @dev Claim rewards for user
     */
    function _claimUserRewards(address pairAddress, address user) internal {
        _updateUserRewards(pairAddress, user);
        
        uint256 reward = userRewards[pairAddress][user];
        if (reward > 0) {
            userRewards[pairAddress][user] = 0;
            
            // Transfer rewards from treasury
            require(slawToken.balanceOf(address(this)) >= reward, "Insufficient reward balance");
            require(slawToken.transfer(user, reward), "Reward transfer failed");
            
            totalRewardsDistributed += reward;
            
            emit RewardsDistributed(user, pairAddress, reward);
        }
    }

    /**
     * @dev Distribute creator bonus
     */
    function _distributeCreatorBonus(address creator, uint256 amount, string memory reason) internal {
        if (amount > 0 && slawToken.balanceOf(address(this)) >= amount) {
            creatorBonuses[creator] += amount;
            require(slawToken.transfer(creator, amount), "Creator bonus transfer failed");
            
            emit CreatorBonusPaid(creator, amount, reason);
        }
    }

    /**
     * @dev Claim rewards for user (external function)
     */
    function claimRewards(address pairAddress) external nonReentrant {
        _claimUserRewards(pairAddress, msg.sender);
    }

    /**
     * @dev Batch claim rewards for multiple pools
     */
    function batchClaimRewards(address[] calldata pairAddresses) external nonReentrant {
        require(pairAddresses.length <= 10, "Too many pools"); // PVM memory limit
        
        for (uint256 i = 0; i < pairAddresses.length; i++) {
            _claimUserRewards(pairAddresses[i], msg.sender);
        }
    }

    // ===== POOL MANAGEMENT =====

    /**
     * @dev Set pool as featured (admin only)
     */
    function setPoolFeatured(address wrappedIPToken, bool featured) external onlyRole(LIQUIDITY_ADMIN) {
        PoolInfo storage pool = pools[wrappedIPToken];
        require(pool.pairAddress != address(0), "Pool not found");
        
        pool.isFeatured = featured;
        
        if (featured) {
            featuredPairs.push(pool.pairAddress);
            pool.rewardMultiplier = 150; // 1.5x rewards for featured pools
        } else {
            // Remove from featured list
            for (uint256 i = 0; i < featuredPairs.length; i++) {
                if (featuredPairs[i] == pool.pairAddress) {
                    featuredPairs[i] = featuredPairs[featuredPairs.length - 1];
                    featuredPairs.pop();
                    break;
                }
            }
            pool.rewardMultiplier = 100; // Back to 1x rewards
        }
        
        emit PoolFeatured(pool.pairAddress, featured);
    }

    /**
     * @dev Update reward rate for pool (admin only)
     */
    function updatePoolRewardRate(address pairAddress, uint256 newRate) external onlyRole(LIQUIDITY_ADMIN) {
        require(getWrappedIPToken[pairAddress] != address(0), "Pool not found");
        
        poolRewardRates[pairAddress] = newRate;
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @dev Get enhanced pool info
     */
    function getPoolInfo(address wrappedIPToken) external view returns (
        PoolInfo memory poolInfo,
        PoolMetrics memory metrics,
        uint256 rewardRate,
        bool isFeatured
    ) {
        poolInfo = pools[wrappedIPToken];
        metrics = poolMetrics[poolInfo.pairAddress];
        rewardRate = poolRewardRates[poolInfo.pairAddress];
        isFeatured = poolInfo.isFeatured;
    }

    /**
     * @dev Get user's pending rewards
     */
    function getPendingRewards(address pairAddress, address user) external view returns (uint256) {
        ValuedLiquidityPair pair = ValuedLiquidityPair(pairAddress);
        uint256 userBalance = pair.balanceOf(user);
        
        if (userBalance == 0) return userRewards[pairAddress][user];
        
        uint256 blocksSinceUpdate = block.number - lastRewardUpdate[pairAddress][user];
        uint256 totalLP = pair.totalSupply();
        
        if (blocksSinceUpdate == 0 || totalLP == 0) return userRewards[pairAddress][user];
        
        uint256 rewardRate = poolRewardRates[pairAddress];
        address wrappedIPToken = getWrappedIPToken[pairAddress];
        PoolInfo memory pool = pools[wrappedIPToken];
        
        // Apply reward multiplier
        uint256 multipliedRate = (rewardRate * pool.rewardMultiplier) / 100;
        
        uint256 newReward = (multipliedRate * blocksSinceUpdate * userBalance) / totalLP;
        return userRewards[pairAddress][user] + newReward;
    }

    /**
     * @dev Get featured pools
     */
    function getFeaturedPools() external view returns (address[] memory) {
        return featuredPairs;
    }

    /**
     * @dev Get top pools by value
     */
    function getTopPoolsByValue(uint256 limit) external view returns (
        address[] memory pairAddresses,
        string[] memory poolNames,
        uint256[] memory poolValues,
        string[] memory creatorNames
    ) {
        uint256 length = allPairs.length;
        if (length == 0) {
            return (new address[](0), new string[](0), new uint256[](0), new string[](0));
        }
        
        uint256 resultLength = limit > length ? length : limit;
        pairAddresses = new address[](resultLength);
        poolNames = new string[](resultLength);
        poolValues = new uint256[](resultLength);
        creatorNames = new string[](resultLength);
        
        // Simple sorting by pool value (in production, use more efficient algorithm)
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 maxValue = 0;
            uint256 maxIndex = 0;
            
            for (uint256 j = 0; j < length; j++) {
                address wrappedToken = getWrappedIPToken[allPairs[j]];
                uint256 value = pools[wrappedToken].poolValue;
                
                if (value > maxValue) {
                    bool alreadyIncluded = false;
                    for (uint256 k = 0; k < i; k++) {
                        if (pairAddresses[k] == allPairs[j]) {
                            alreadyIncluded = true;
                            break;
                        }
                    }
                    
                    if (!alreadyIncluded) {
                        maxValue = value;
                        maxIndex = j;
                    }
                }
            }
            
            if (maxValue > 0) {
                address wrappedToken = getWrappedIPToken[allPairs[maxIndex]];
                PoolInfo memory pool = pools[wrappedToken];
                
                pairAddresses[i] = allPairs[maxIndex];
                poolNames[i] = string(abi.encodePacked(pool.creatorName, "'s ", pool.ipTitle));
                poolValues[i] = pool.poolValue;
                creatorNames[i] = pool.creatorName;
            }
        }
    }

    /**
     * @dev Get creator's pools
     */
    function getCreatorPools(address creator) external view returns (
        address[] memory pairAddresses,
        PoolInfo[] memory poolInfos
    ) {
        uint256 count = 0;
        
        // Count creator's pools
        for (uint256 i = 0; i < allPairs.length; i++) {
            address wrappedToken = getWrappedIPToken[allPairs[i]];
            if (pools[wrappedToken].creator == creator) {
                count++;
            }
        }
        
        pairAddresses = new address[](count);
        poolInfos = new PoolInfo[](count);
        
        uint256 index = 0;
        for (uint256 i = 0; i < allPairs.length; i++) {
            address wrappedToken = getWrappedIPToken[allPairs[i]];
            if (pools[wrappedToken].creator == creator) {
                pairAddresses[index] = allPairs[i];
                poolInfos[index] = pools[wrappedToken];
                index++;
            }
        }
    }

    /**
     * @dev Get system metrics
     */
    function getSystemMetrics() external view returns (
        uint256 _totalPools,
        uint256 _totalLiquidity,
        uint256 _totalVolume,
        uint256 _totalRewards,
        uint256 _featuredPools
    ) {
        return (
            totalPools,
            totalLiquidity,
            totalVolume,
            totalRewardsDistributed,
            featuredPairs.length
        );
    }

    // ===== TREASURY INTEGRATION =====

    /**
     * @dev Fund rewards pool (admin only)
     */
    function fundRewardsPool(uint256 amount) external onlyRole(LIQUIDITY_ADMIN) {
        require(slawToken.transferFrom(msg.sender, address(this), amount), "Funding failed");
    }

    /**
     * @dev Update treasury core address
     */
    function updateTreasuryCore(address newTreasuryCore) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasuryCore != address(0), "Invalid treasury address");
        
        _revokeRole(TREASURY_ROLE, treasuryCore);
        treasuryCore = newTreasuryCore;
        _grantRole(TREASURY_ROLE, newTreasuryCore);
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(LIQUIDITY_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(LIQUIDITY_ADMIN) {
        _unpause();
    }

    /**
     * @dev Emergency function to recover stuck tokens
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        
        IERC20(token).transfer(treasuryCore, amount);
    }
}
