// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SLAWToken.sol";

/**
 * @title SimpleLiquidityPair
 * @dev Lightweight LP token for PVM optimization
 */
contract SimpleLiquidityPair is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    address public immutable factory;
    address public immutable token0; // SLAW
    address public immutable token1; // Wrapped IP
    
    uint112 private reserve0; // SLAW reserves
    uint112 private reserve1; // Wrapped IP reserves
    uint32 private blockTimestampLast;
    
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed to, uint256 amount0, uint256 amount1);
    event Swap(address indexed to, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out);
    event Sync(uint112 reserve0, uint112 reserve1);
    
    constructor() {
        factory = msg.sender;
        (token0, token1) = (address(0), address(0)); // Will be set by factory
    }
    
    function initialize(address _token0, address _token1, string memory _name, string memory _symbol) external {
        require(msg.sender == factory, "Only factory");
        require(token0 == address(0), "Already initialized");
        
        // token0 should be SLAW, token1 should be Wrapped IP
        (token0, token1) = (_token0, _token1);
        name = _name;
        symbol = _symbol;
    }
    
    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
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
        
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(to, liquidity);
    }
    
    function burn(address to) external returns (uint256 amount0, uint256 amount1) {
        require(msg.sender == factory, "Only factory");
        
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));
        
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");
        
        _burn(address(this), liquidity);
        IERC20(_token0).transfer(to, amount0);
        IERC20(_token1).transfer(to, amount1);
        
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Burn(to, amount0, amount1);
    }
    
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "Overflow");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
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
 * @dev Manages liquidity pools for Wrapped IP tokens + SLAW
 * Features:
 * - Simplified Uniswap V2-style AMM
 * - LP token minting/burning
 * - Fee collection
 * - PVM-optimized design
 */
contract LiquidityManager is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant LIQUIDITY_ADMIN = keccak256("LIQUIDITY_ADMIN");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // System contracts
    SLAWToken public immutable slawToken;
    address public treasuryCore;
    
    // Pool tracking
    struct PoolInfo {
        address pairAddress;
        address wrappedIPToken;
        uint256 totalLiquidity;
        uint256 createdAt;
        bool isActive;
        address creator;
    }
    
    mapping(address => PoolInfo) public pools; // wrappedIPToken => PoolInfo
    mapping(address => address) public getWrappedIPToken; // pairAddress => wrappedIPToken
    address[] public allPairs;
    
    // System metrics
    uint256 public totalPools;
    uint256 public totalLiquidity;
    
    // Events
    event PoolCreated(
        address indexed wrappedIPToken,
        address indexed pairAddress,
        address indexed creator,
        uint256 slawAmount,
        uint256 ipAmount
    );
    
    event LiquidityAdded(
        address indexed pairAddress,
        address indexed provider,
        uint256 slawAmount,
        uint256 ipAmount,
        uint256 liquidityMinted
    );
    
    event LiquidityRemoved(
        address indexed pairAddress,
        address indexed provider,
        uint256 slawAmount,
        uint256 ipAmount,
        uint256 liquidityBurned
    );

    constructor(
        address _admin,
        address _slawToken,
        address _treasuryCore
    ) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_treasuryCore != address(0), "Invalid treasury core");
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(LIQUIDITY_ADMIN, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);
        
        slawToken = SLAWToken(_slawToken);
        treasuryCore = _treasuryCore;
    }

    // ===== POOL CREATION =====

    /**
     * @dev Create a new liquidity pool for Wrapped IP + SLAW
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
        
        // Deploy new pair contract
        SimpleLiquidityPair pair = new SimpleLiquidityPair();
        
        // Initialize pair
        string memory pairName = string(abi.encodePacked("SLAW-", IERC20(wrappedIPToken).symbol(), " LP"));
        string memory pairSymbol = string(abi.encodePacked("SLAW-", IERC20(wrappedIPToken).symbol()));
        pair.initialize(address(slawToken), wrappedIPToken, pairName, pairSymbol);
        
        pairAddress = address(pair);
        
        // Transfer tokens to pair
        require(slawToken.transferFrom(msg.sender, pairAddress, slawAmount), "SLAW transfer failed");
        require(IERC20(wrappedIPToken).transferFrom(msg.sender, pairAddress, ipAmount), "IP token transfer failed");
        
        // Mint initial LP tokens
        uint256 liquidityMinted = pair.mint(msg.sender);
        
        // Store pool info
        pools[wrappedIPToken] = PoolInfo({
            pairAddress: pairAddress,
            wrappedIPToken: wrappedIPToken,
            totalLiquidity: slawAmount + ipAmount, // Simplified calculation
            createdAt: block.timestamp,
            isActive: true,
            creator: msg.sender
        });
        
        getWrappedIPToken[pairAddress] = wrappedIPToken;
        allPairs.push(pairAddress);
        totalPools++;
        totalLiquidity += (slawAmount + ipAmount);
        
        emit PoolCreated(wrappedIPToken, pairAddress, msg.sender, slawAmount, ipAmount);
        emit LiquidityAdded(pairAddress, msg.sender, slawAmount, ipAmount, liquidityMinted);
    }

    // ===== LIQUIDITY MANAGEMENT =====

    /**
     * @dev Add liquidity to existing pool
     * @param wrappedIPToken Wrapped IP token address
     * @param slawAmount Amount of SLAW to add
     * @param ipAmount Amount of IP tokens to add
     */
    function addLiquidity(
        address wrappedIPToken,
        uint256 slawAmount,
        uint256 ipAmount
    ) external nonReentrant whenNotPaused returns (uint256 liquidityMinted) {
        PoolInfo storage pool = pools[wrappedIPToken];
        require(pool.isActive, "Pool not active");
        require(slawAmount > 0 && ipAmount > 0, "Amounts must be > 0");
        
        SimpleLiquidityPair pair = SimpleLiquidityPair(pool.pairAddress);
        
        // Transfer tokens to pair
        require(slawToken.transferFrom(msg.sender, pool.pairAddress, slawAmount), "SLAW transfer failed");
        require(IERC20(wrappedIPToken).transferFrom(msg.sender, pool.pairAddress, ipAmount), "IP token transfer failed");
        
        // Mint LP tokens
        liquidityMinted = pair.mint(msg.sender);
        
        // Update pool info
        pool.totalLiquidity += (slawAmount + ipAmount);
        totalLiquidity += (slawAmount + ipAmount);
        
        emit LiquidityAdded(pool.pairAddress, msg.sender, slawAmount, ipAmount, liquidityMinted);
    }

    /**
     * @dev Remove liquidity from pool
     * @param wrappedIPToken Wrapped IP token address
     * @param liquidityAmount Amount of LP tokens to burn
     */
    function removeLiquidity(
        address wrappedIPToken,
        uint256 liquidityAmount
    ) external nonReentrant whenNotPaused returns (uint256 slawAmount, uint256 ipAmount) {
        PoolInfo storage pool = pools[wrappedIPToken];
        require(pool.isActive, "Pool not active");
        require(liquidityAmount > 0, "Amount must be > 0");
        
        SimpleLiquidityPair pair = SimpleLiquidityPair(pool.pairAddress);
        
        // Transfer LP tokens to pair for burning
        require(pair.transferFrom(msg.sender, pool.pairAddress, liquidityAmount), "LP transfer failed");
        
        // Burn LP tokens and get underlying assets
        (slawAmount, ipAmount) = pair.burn(msg.sender);
        
        // Update pool info
        uint256 removedLiquidity = slawAmount + ipAmount;
        pool.totalLiquidity = pool.totalLiquidity > removedLiquidity ? 
            pool.totalLiquidity - removedLiquidity : 0;
        totalLiquidity = totalLiquidity > removedLiquidity ? 
            totalLiquidity - removedLiquidity : 0;
        
        emit LiquidityRemoved(pool.pairAddress, msg.sender, slawAmount, ipAmount, liquidityAmount);
    }

    // ===== POOL MANAGEMENT =====

    /**
     * @dev Toggle pool active status
     * @param wrappedIPToken Wrapped IP token address
     * @param isActive New active status
     */
    function togglePoolStatus(address wrappedIPToken, bool isActive) external onlyRole(LIQUIDITY_ADMIN) {
        PoolInfo storage pool = pools[wrappedIPToken];
        require(pool.pairAddress != address(0), "Pool not found");
        
        pool.isActive = isActive;
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * @dev Get pool info by wrapped IP token
     * @param wrappedIPToken Wrapped IP token address
     */
    function getPoolInfo(address wrappedIPToken) external view returns (PoolInfo memory) {
        return pools[wrappedIPToken];
    }

    /**
     * @dev Get pool reserves
     * @param wrappedIPToken Wrapped IP token address
     */
    function getPoolReserves(address wrappedIPToken) external view returns (
        uint112 slawReserve,
        uint112 ipReserve,
        uint32 blockTimestampLast
    ) {
        PoolInfo memory pool = pools[wrappedIPToken];
        require(pool.pairAddress != address(0), "Pool not found");
        
        SimpleLiquidityPair pair = SimpleLiquidityPair(pool.pairAddress);
        return pair.getReserves();
    }

    /**
     * @dev Get all pairs
     */
    function getAllPairs() external view returns (address[] memory) {
        return allPairs;
    }

    /**
     * @dev Get pairs with pagination
     * @param offset Starting index
     * @param limit Number of pairs to return
     */
    function getPairsPaginated(uint256 offset, uint256 limit) external view returns (
        address[] memory pairAddresses,
        PoolInfo[] memory poolInfos
    ) {
        if (offset >= allPairs.length) {
            return (new address[](0), new PoolInfo[](0));
        }
        
        uint256 end = offset + limit;
        if (end > allPairs.length) {
            end = allPairs.length;
        }
        
        uint256 length = end - offset;
        pairAddresses = new address[](length);
        poolInfos = new PoolInfo[](length);
        
        for (uint256 i = 0; i < length; i++) {
            address pairAddress = allPairs[offset + i];
            address wrappedIPToken = getWrappedIPToken[pairAddress];
            
            pairAddresses[i] = pairAddress;
            poolInfos[i] = pools[wrappedIPToken];
        }
    }

    /**
     * @dev Get system metrics
     */
    function getSystemMetrics() external view returns (
        uint256 _totalPools,
        uint256 _totalLiquidity,
        uint256 activePools
    ) {
        // Note: activePools would require iteration in full implementation
        return (totalPools, totalLiquidity, totalPools);
    }

    // ===== TREASURY INTEGRATION =====

    /**
     * @dev Update treasury core address
     * @param newTreasuryCore New treasury core address
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
     * @param token Token address
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        
        IERC20(token).transfer(treasuryCore, amount);
    }
}
