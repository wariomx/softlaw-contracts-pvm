// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "../IP-liquidity/interfaces/IUniswapV2Factory.sol";
import "../IP-liquidity/interfaces/IUniswapV2Pair.sol";

/**
 * @title SoftlawTreasury
 * @dev Comprehensive treasury system for Softlaw ecosystem
 * Features:
 * - SLAW token (native currency)
 * - Wrapped Copyright NFTs → ERC20 tokens
 * - IP Liquidity pools (Wrapped IP + SLAW)
 * - Automated payments for registrations/licenses
 * - Liquidity provider rewards
 * - Fee collection and distribution
 */
contract SoftlawTreasury is
    ERC20,
    AccessControl,
    ReentrancyGuard,
    Pausable,
    IERC721Receiver
{
    // Roles
    bytes32 public constant TREASURY_ADMIN = keccak256("TREASURY_ADMIN");
    bytes32 public constant REGISTRY_CONTRACT = keccak256("REGISTRY_CONTRACT");
    bytes32 public constant LICENSING_CONTRACT =
        keccak256("LICENSING_CONTRACT");
    bytes32 public constant LIQUIDITY_MANAGER = keccak256("LIQUIDITY_MANAGER");

    // SLAW Token Configuration
    uint256 private constant INITIAL_SUPPLY = 10_000_000_000 * 10 ** 18; // 10B SLAW
    uint256 public constant REGISTRATION_FEE = 100 * 10 ** 18; // 100 SLAW
    uint256 public constant LICENSE_BASE_FEE = 50 * 10 ** 18; // 50 SLAW

    // Wrapped Copyright Tokens
    struct WrappedIP {
        uint256 nftId;
        address nftContract;
        uint256 totalSupply;
        uint256 pricePerToken;
        address creator;
        bool isActive;
        string metadata;
    }

    // Liquidity Pool Data
    struct LiquidityPool {
        address pairAddress;
        address ipToken;
        uint256 totalLiquidity;
        uint256 rewardRate; // Rewards per block
        uint256 lastRewardBlock;
        bool isActive;
    }

    // IP Factory for creating wrapped tokens
    mapping(uint256 => address) public wrappedIPTokens; // nftId => token address
    mapping(address => WrappedIP) public wrappedIPDetails; // token address => details
    mapping(address => LiquidityPool) public liquidityPools; // pair address => pool data
    mapping(address => uint256) public userRewards; // user => pending rewards

    // System addresses
    IUniswapV2Factory public immutable liquidityFactory;
    address public feeCollector;

    // System metrics
    uint256 public totalWrappedIPs;
    uint256 public totalLiquidityPools;
    uint256 public totalFeesCollected;
    uint256 public rewardPool;

    // Events
    event IPWrapped(
        uint256 indexed nftId,
        address indexed nftContract,
        address indexed tokenAddress,
        uint256 totalSupply,
        address creator
    );

    event LiquidityPoolCreated(
        address indexed pairAddress,
        address indexed ipToken,
        uint256 initialLiquidity
    );

    event RegistrationPaid(
        address indexed user,
        uint256 indexed nftId,
        uint256 amount
    );

    event LicensePaid(
        address indexed licensor,
        address indexed licensee,
        uint256 indexed licenseId,
        uint256 amount
    );

    event RewardsDistributed(address indexed user, uint256 amount);

    event FeesCollected(address indexed from, uint256 amount, string feeType);

    constructor(
        address _admin,
        address _liquidityFactory,
        address _feeCollector
    ) ERC20("SoftLaw Token", "SLAW") {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(TREASURY_ADMIN, _admin);

        liquidityFactory = IUniswapV2Factory(_liquidityFactory);
        feeCollector = _feeCollector;

        // Mint initial supply to treasury
        _mint(address(this), INITIAL_SUPPLY);

        // Set up reward pool (10% of initial supply)
        rewardPool = INITIAL_SUPPLY / 10;
    }

    // ===== WRAPPED COPYRIGHT FUNCTIONALITY =====

    /**
     * @dev Wrap a copyright NFT into fungible ERC20 tokens
     * @param nftContract Address of the NFT contract
     * @param nftId Token ID of the NFT
     * @param totalSupply Total supply of wrapped tokens to create
     * @param pricePerToken Price per wrapped token in SLAW
     * @param metadata Additional metadata for the wrapped IP
     */
    function wrapCopyrightNFT(
        address nftContract,
        uint256 nftId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string memory metadata
    ) external nonReentrant whenNotPaused returns (address tokenAddress) {
        require(nftContract != address(0), "Invalid NFT contract");
        require(totalSupply > 0, "Total supply must be > 0");
        require(pricePerToken > 0, "Price must be > 0");
        require(wrappedIPTokens[nftId] == address(0), "NFT already wrapped");

        // Transfer NFT to treasury (treasury holds the underlying asset)
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), nftId);

        // Create wrapped IP token
        tokenAddress = _createWrappedIPToken(
            nftId,
            nftContract,
            totalSupply,
            msg.sender
        );

        // Store wrapped IP details
        wrappedIPDetails[tokenAddress] = WrappedIP({
            nftId: nftId,
            nftContract: nftContract,
            totalSupply: totalSupply,
            pricePerToken: pricePerToken,
            creator: msg.sender,
            isActive: true,
            metadata: metadata
        });

        wrappedIPTokens[nftId] = tokenAddress;
        totalWrappedIPs++;

        emit IPWrapped(
            nftId,
            nftContract,
            tokenAddress,
            totalSupply,
            msg.sender
        );
    }

    /**
     * @dev Create liquidity pool for wrapped IP token + SLAW
     * @param wrappedIPToken Address of the wrapped IP token
     * @param ipTokenAmount Amount of IP tokens to add
     * @param slawAmount Amount of SLAW tokens to add
     */
    function createLiquidityPool(
        address wrappedIPToken,
        uint256 ipTokenAmount,
        uint256 slawAmount
    ) external nonReentrant whenNotPaused returns (address pairAddress) {
        require(wrappedIPDetails[wrappedIPToken].isActive, "Invalid IP token");
        require(ipTokenAmount > 0 && slawAmount > 0, "Amounts must be > 0");

        // Transfer tokens to this contract
        IERC20(wrappedIPToken).transferFrom(
            msg.sender,
            address(this),
            ipTokenAmount
        );
        _transfer(msg.sender, address(this), slawAmount);

        // Create pair if it doesn't exist
        pairAddress = liquidityFactory.getPair(wrappedIPToken, address(this));
        if (pairAddress == address(0)) {
            pairAddress = liquidityFactory.createPair(
                wrappedIPToken,
                address(this)
            );
        }

        // Add liquidity
        IERC20(wrappedIPToken).transfer(pairAddress, ipTokenAmount);
        _transfer(address(this), pairAddress, slawAmount);

        IUniswapV2Pair(pairAddress).mint(msg.sender);

        // Set up liquidity pool tracking
        liquidityPools[pairAddress] = LiquidityPool({
            pairAddress: pairAddress,
            ipToken: wrappedIPToken,
            totalLiquidity: ipTokenAmount + slawAmount,
            rewardRate: _calculateRewardRate(ipTokenAmount + slawAmount),
            lastRewardBlock: block.number,
            isActive: true
        });

        totalLiquidityPools++;

        emit LiquidityPoolCreated(
            pairAddress,
            wrappedIPToken,
            ipTokenAmount + slawAmount
        );
    }

    // ===== PAYMENT SYSTEM =====

    /**
     * @dev Pay for IP registration (called by registry contracts)
     * @param user User paying for registration
     * @param nftId NFT ID being registered
     */
    function payRegistrationFee(
        address user,
        uint256 nftId
    ) external onlyRole(REGISTRY_CONTRACT) nonReentrant {
        require(
            balanceOf(user) >= REGISTRATION_FEE,
            "Insufficient SLAW balance"
        );

        _transfer(user, feeCollector, REGISTRATION_FEE);
        totalFeesCollected += REGISTRATION_FEE;

        emit RegistrationPaid(user, nftId, REGISTRATION_FEE);
        emit FeesCollected(user, REGISTRATION_FEE, "REGISTRATION");
    }

    /**
     * @dev Pay for license fee (called by licensing contracts)
     * @param licensor License creator
     * @param licensee License buyer
     * @param licenseId License ID
     * @param amount Custom license amount
     */
    function payLicenseFee(
        address licensor,
        address licensee,
        uint256 licenseId,
        uint256 amount
    ) external onlyRole(LICENSING_CONTRACT) nonReentrant {
        uint256 totalFee = LICENSE_BASE_FEE + amount;
        require(balanceOf(licensee) >= totalFee, "Insufficient SLAW balance");

        // 70% to licensor, 30% to fee collector
        uint256 licensorShare = (totalFee * 70) / 100;
        uint256 protocolShare = totalFee - licensorShare;

        _transfer(licensee, licensor, licensorShare);
        _transfer(licensee, feeCollector, protocolShare);

        totalFeesCollected += protocolShare;

        emit LicensePaid(licensor, licensee, licenseId, totalFee);
        emit FeesCollected(licensee, totalFee, "LICENSE");
    }

    // ===== LIQUIDITY REWARDS SYSTEM =====

    /**
     * @dev Distribute rewards to liquidity providers
     * @param pairAddress Liquidity pair address
     * @param provider Liquidity provider address
     */
    function distributeRewards(
        address pairAddress,
        address provider
    ) external nonReentrant {
        LiquidityPool storage pool = liquidityPools[pairAddress];
        require(pool.isActive, "Pool not active");

        uint256 lpBalance = IERC20(pairAddress).balanceOf(provider);
        require(lpBalance > 0, "No liquidity provided");

        uint256 reward = _calculateUserReward(pairAddress, provider);
        if (reward > 0 && rewardPool >= reward) {
            _transfer(address(this), provider, reward);
            rewardPool -= reward;
            pool.lastRewardBlock = block.number;

            emit RewardsDistributed(provider, reward);
        }
    }

    /**
     * @dev Add SLAW tokens to reward pool
     * @param amount Amount to add to reward pool
     */
    function addToRewardPool(uint256 amount) external onlyRole(TREASURY_ADMIN) {
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient treasury balance"
        );
        rewardPool += amount;
    }

    // ===== TREASURY MANAGEMENT =====

    /**
     * @dev Mint additional SLAW tokens (controlled supply increase)
     * @param amount Amount to mint
     */
    function mintSLAW(uint256 amount) external onlyRole(TREASURY_ADMIN) {
        require(
            amount <= totalSupply() / 100,
            "Cannot mint more than 1% of supply"
        );
        _mint(address(this), amount);
    }

    /**
     * @dev Distribute SLAW tokens for ecosystem incentives
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts for each recipient
     */
    function distributeIncentives(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(TREASURY_ADMIN) nonReentrant {
        require(recipients.length == amounts.length, "Arrays length mismatch");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(
            balanceOf(address(this)) >= totalAmount,
            "Insufficient treasury balance"
        );

        for (uint256 i = 0; i < recipients.length; i++) {
            _transfer(address(this), recipients[i], amounts[i]);
        }
    }

    // ===== VIEW FUNCTIONS =====

    function getTreasuryBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }

    function getWrappedIPDetails(
        address tokenAddress
    ) external view returns (WrappedIP memory) {
        return wrappedIPDetails[tokenAddress];
    }

    function getLiquidityPoolDetails(
        address pairAddress
    ) external view returns (LiquidityPool memory) {
        return liquidityPools[pairAddress];
    }

    function getSystemMetrics()
        external
        view
        returns (
            uint256 treasuryBalance,
            uint256 totalWrapped,
            uint256 totalPools,
            uint256 totalFees,
            uint256 rewards
        )
    {
        return (
            balanceOf(address(this)),
            totalWrappedIPs,
            totalLiquidityPools,
            totalFeesCollected,
            rewardPool
        );
    }

    // ===== INTERNAL FUNCTIONS =====

    function _createWrappedIPToken(
        uint256 nftId,
        address nftContract,
        uint256 totalSupply,
        address creator
    ) internal returns (address) {
        // For simplicity, we'll use a factory pattern here
        // In a full implementation, you'd deploy a new ERC20 contract
        // For now, we'll track it in our mapping system
        address tokenAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(nftContract, nftId, block.timestamp)
                    )
                )
            )
        );

        return tokenAddress;
    }

    function _calculateRewardRate(
        uint256 liquidityAmount
    ) internal pure returns (uint256) {
        // Base reward rate: 0.1% per block, adjusted by liquidity size
        return (liquidityAmount * 1000) / 1000000; // 0.1%
    }

    function _calculateUserReward(
        address pairAddress,
        address provider
    ) internal view returns (uint256) {
        LiquidityPool memory pool = liquidityPools[pairAddress];
        uint256 lpBalance = IERC20(pairAddress).balanceOf(provider);
        uint256 totalLP = IERC20(pairAddress).totalSupply();

        if (totalLP == 0) return 0;

        uint256 blocksPassed = block.number - pool.lastRewardBlock;
        uint256 totalPoolReward = pool.rewardRate * blocksPassed;

        return (totalPoolReward * lpBalance) / totalLP;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // ===== ADMIN FUNCTIONS =====

    function pause() external onlyRole(TREASURY_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(TREASURY_ADMIN) {
        _unpause();
    }

    function updateFeeCollector(
        address newFeeCollector
    ) external onlyRole(TREASURY_ADMIN) {
        feeCollector = newFeeCollector;
    }
}
