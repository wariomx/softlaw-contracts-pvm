// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SLAWToken.sol";

/**
 * @title OptimizedLiquidityManager
 * @dev PVM-optimized liquidity management for wrapped IP tokens
 * Replaces .send/.transfer with secure .call() pattern
 * Memory-efficient design for Polkadot Virtual Machine
 */
contract OptimizedLiquidityManager is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant LIQUIDITY_ADMIN = keccak256("LIQUIDITY_ADMIN");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    SLAWToken public immutable slawToken;
    address public treasuryCore;

    // Optimized structs for PVM
    struct LiquidityPool {
        address tokenA; // Wrapped IP token
        address tokenB; // SLAW token
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
        uint256 lastUpdate;
        bool isActive;
    }

    struct UserPosition {
        uint256 liquidityTokens;
        uint256 lastDeposit;
        uint256 totalFeesEarned;
    }

    // Storage
    mapping(bytes32 => LiquidityPool) public pools; // keccak256(tokenA, tokenB) => pool
    mapping(bytes32 => mapping(address => UserPosition)) public userPositions;
    mapping(address => bytes32[]) public userPools;

    uint256 public constant TRADING_FEE = 30; // 0.3% = 30/10000
    uint256 public constant PROTOCOL_FEE = 5; // 0.05% = 5/10000
    uint256 public constant MIN_LIQUIDITY = 10 ** 3; // Minimum liquidity tokens

    // Events
    event PoolCreated(
        bytes32 indexed poolId,
        address indexed tokenA,
        address indexed tokenB
    );
    event LiquidityAdded(
        bytes32 indexed poolId,
        address indexed user,
        uint256 amountA,
        uint256 amountB
    );
    event LiquidityRemoved(
        bytes32 indexed poolId,
        address indexed user,
        uint256 liquidity
    );
    event TokensSwapped(
        bytes32 indexed poolId,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut
    );
    event FeesCollected(
        bytes32 indexed poolId,
        address indexed user,
        uint256 feeAmount
    );
    event PaymentProcessed(
        address indexed recipient,
        uint256 amount,
        bool success
    );

    constructor(address _admin, address _slawToken, address _treasuryCore) {
        require(_slawToken != address(0), "Invalid SLAW token");
        require(_treasuryCore != address(0), "Invalid treasury");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(LIQUIDITY_ADMIN, _admin);
        _grantRole(TREASURY_ROLE, _treasuryCore);

        slawToken = SLAWToken(_slawToken);
        treasuryCore = _treasuryCore;
    }

    // ===== POOL MANAGEMENT =====

    function createPool(
        address tokenA,
        address tokenB
    ) external onlyRole(LIQUIDITY_ADMIN) returns (bytes32 poolId) {
        require(tokenA != tokenB, "Identical tokens");
        require(tokenA != address(0) && tokenB != address(0), "Zero address");

        // Ensure tokenB is always SLAW for consistency
        if (tokenB != address(slawToken)) {
            require(tokenA == address(slawToken), "One token must be SLAW");
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        poolId = keccak256(abi.encodePacked(tokenA, tokenB));
        require(!pools[poolId].isActive, "Pool already exists");

        pools[poolId] = LiquidityPool({
            tokenA: tokenA,
            tokenB: tokenB,
            reserveA: 0,
            reserveB: 0,
            totalLiquidity: 0,
            lastUpdate: block.timestamp,
            isActive: true
        });

        emit PoolCreated(poolId, tokenA, tokenB);
    }

    // ===== LIQUIDITY OPERATIONS =====

    function addLiquidity(
        bytes32 poolId,
        uint256 amountA,
        uint256 amountB
    ) external nonReentrant whenNotPaused returns (uint256 liquidity) {
        LiquidityPool storage pool = pools[poolId];
        require(pool.isActive, "Pool not active");
        require(amountA > 0 && amountB > 0, "Amounts must be > 0");

        // Calculate liquidity tokens to mint
        if (pool.totalLiquidity == 0) {
            liquidity = _sqrt(amountA * amountB) - MIN_LIQUIDITY;
            require(liquidity > 0, "Insufficient liquidity");
        } else {
            liquidity = _min(
                (amountA * pool.totalLiquidity) / pool.reserveA,
                (amountB * pool.totalLiquidity) / pool.reserveB
            );
        }

        require(liquidity > 0, "Insufficient liquidity minted");

        // Transfer tokens (secure pattern instead of .transfer)
        _safeTransferFrom(pool.tokenA, msg.sender, address(this), amountA);
        _safeTransferFrom(pool.tokenB, msg.sender, address(this), amountB);

        // Update pool reserves
        pool.reserveA += amountA;
        pool.reserveB += amountB;
        pool.totalLiquidity += liquidity;
        pool.lastUpdate = block.timestamp;

        // Update user position
        UserPosition storage position = userPositions[poolId][msg.sender];
        if (position.liquidityTokens == 0) {
            userPools[msg.sender].push(poolId);
        }
        position.liquidityTokens += liquidity;
        position.lastDeposit = block.timestamp;

        emit LiquidityAdded(poolId, msg.sender, amountA, amountB);
    }

    function removeLiquidity(
        bytes32 poolId,
        uint256 liquidity
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountA, uint256 amountB)
    {
        LiquidityPool storage pool = pools[poolId];
        require(pool.isActive, "Pool not active");
        require(liquidity > 0, "Amount must be > 0");

        UserPosition storage position = userPositions[poolId][msg.sender];
        require(
            position.liquidityTokens >= liquidity,
            "Insufficient liquidity"
        );

        // Calculate token amounts to return
        amountA = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountB = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountA > 0 && amountB > 0, "Insufficient amounts");

        // Update reserves
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.totalLiquidity -= liquidity;
        pool.lastUpdate = block.timestamp;

        // Update user position
        position.liquidityTokens -= liquidity;

        // Transfer tokens back (secure pattern)
        _safeTransfer(pool.tokenA, msg.sender, amountA);
        _safeTransfer(pool.tokenB, msg.sender, amountB);

        emit LiquidityRemoved(poolId, msg.sender, liquidity);
    }

    // ===== TRADING OPERATIONS =====

    function swapTokens(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        LiquidityPool storage pool = pools[poolId];
        require(pool.isActive, "Pool not active");
        require(amountIn > 0, "Amount must be > 0");
        require(
            tokenIn == pool.tokenA || tokenIn == pool.tokenB,
            "Invalid token"
        );

        // Calculate output amount
        amountOut = _getAmountOut(poolId, tokenIn, amountIn);
        require(amountOut >= minAmountOut, "Insufficient output amount");

        address tokenOut = tokenIn == pool.tokenA ? pool.tokenB : pool.tokenA;

        // Transfer input tokens
        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        // Calculate fees
        uint256 tradingFee = (amountIn * TRADING_FEE) / 10000;
        uint256 protocolFee = (amountIn * PROTOCOL_FEE) / 10000;
        uint256 netAmountIn = amountIn - tradingFee - protocolFee;

        // Update reserves
        if (tokenIn == pool.tokenA) {
            pool.reserveA += netAmountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += netAmountIn;
            pool.reserveA -= amountOut;
        }

        // Transfer output tokens
        _safeTransfer(tokenOut, msg.sender, amountOut);

        // Transfer protocol fee to treasury
        if (protocolFee > 0) {
            _safeTransfer(tokenIn, treasuryCore, protocolFee);
        }

        pool.lastUpdate = block.timestamp;

        emit TokensSwapped(poolId, msg.sender, amountIn, amountOut);
    }

    // ===== SECURE TRANSFER FUNCTIONS (Replacement for .send/.transfer) =====

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );

        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Transfer failed"
        );
        emit PaymentProcessed(to, amount, success);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                amount
            )
        );

        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferFrom failed"
        );
    }

    // Secure native token transfer (for ETH/native currency)
    function _safeTransferNative(address to, uint256 amount) internal {
        if (amount == 0) return;

        (bool success, ) = to.call{value: amount}("");
        require(success, "Native transfer failed");
        emit PaymentProcessed(to, amount, success);
    }

    // ===== CALCULATION FUNCTIONS =====

    function _getAmountOut(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn
    ) internal view returns (uint256) {
        LiquidityPool storage pool = pools[poolId];

        uint256 reserveIn = tokenIn == pool.tokenA
            ? pool.reserveA
            : pool.reserveB;
        uint256 reserveOut = tokenIn == pool.tokenA
            ? pool.reserveB
            : pool.reserveA;

        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        uint256 amountInWithFee = amountIn *
            (10000 - TRADING_FEE - PROTOCOL_FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10000 + amountInWithFee;

        return numerator / denominator;
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // ===== VIEW FUNCTIONS =====

    function getPool(
        bytes32 poolId
    ) external view returns (LiquidityPool memory) {
        return pools[poolId];
    }

    function getUserPosition(
        bytes32 poolId,
        address user
    ) external view returns (UserPosition memory) {
        return userPositions[poolId][user];
    }

    function getUserPools(
        address user
    ) external view returns (bytes32[] memory) {
        return userPools[user];
    }

    function getAmountOut(
        bytes32 poolId,
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256) {
        return _getAmountOut(poolId, tokenIn, amountIn);
    }

    function getPoolId(
        address tokenA,
        address tokenB
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(LIQUIDITY_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(LIQUIDITY_ADMIN) {
        _unpause();
    }

    function updateTreasuryCore(
        address newTreasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury");
        _revokeRole(TREASURY_ROLE, treasuryCore);
        treasuryCore = newTreasury;
        _grantRole(TREASURY_ROLE, newTreasury);
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid recipient");
        _safeTransfer(token, to, amount);
    }

    // ===== FEE COLLECTION =====

    function collectFees(
        bytes32 poolId
    ) external nonReentrant returns (uint256 feeAmount) {
        UserPosition storage position = userPositions[poolId][msg.sender];
        require(position.liquidityTokens > 0, "No liquidity position");

        // Calculate fees earned (simplified calculation)
        LiquidityPool storage pool = pools[poolId];
        uint256 userShare = (position.liquidityTokens * 10000) /
            pool.totalLiquidity;
        feeAmount = (userShare * pool.reserveB) / 10000; // Approximate fee calculation

        if (feeAmount > 0) {
            position.totalFeesEarned += feeAmount;
            _safeTransfer(pool.tokenB, msg.sender, feeAmount);
            emit FeesCollected(poolId, msg.sender, feeAmount);
        }
    }
}
