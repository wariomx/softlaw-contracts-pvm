// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IWrappedIPToken
 * @dev Interface for wrapped intellectual property tokens
 */
interface IWrappedIPToken is IERC20 {
    // Events
    event IPWrapped(
        uint256 indexed nftId,
        address indexed nftContract,
        uint256 totalSupply
    );
    event IPUnwrapped(uint256 indexed nftId, address indexed recipient);
    event RedemptionStarted(address indexed user, uint256 amount);
    event RedemptionCompleted(address indexed user, uint256 amount);

    // Structs
    struct IPDetails {
        uint256 nftId;
        address nftContract;
        address creator;
        uint256 totalSupply;
        uint256 circulatingSupply;
        string metadata;
        bool isRedeemable;
    }

    // View Functions
    function getIPDetails() external view returns (IPDetails memory);
    function getNFTId() external view returns (uint256);
    function getNFTContract() external view returns (address);
    function getCreator() external view returns (address);
    function isRedeemable() external view returns (bool);

    // Core Functions
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function startRedemption(uint256 amount) external;
    function completeRedemption() external;

    // Admin Functions
    function setRedeemable(bool _redeemable) external;
    function updateMetadata(string memory newMetadata) external;
}

/**
 * @title IWrappedIPFactory
 * @dev Interface for factory that creates wrapped IP tokens
 */
interface IWrappedIPFactory {
    event WrappedIPTokenCreated(
        address indexed tokenAddress,
        uint256 indexed nftId,
        address indexed nftContract,
        address creator
    );

    function createWrappedIPToken(
        uint256 nftId,
        address nftContract,
        uint256 totalSupply,
        address creator,
        string memory name,
        string memory symbol,
        string memory metadata
    ) external returns (address);

    function getWrappedToken(
        uint256 nftId,
        address nftContract
    ) external view returns (address);
    function isValidWrappedToken(
        address tokenAddress
    ) external view returns (bool);
}

/**
 * @title ISoftlawTreasury
 * @dev Interface for the Softlaw Treasury system
 */
interface ISoftlawTreasury {
    // Events
    event IPWrapped(
        uint256 indexed nftId,
        address indexed nftContract,
        address indexed tokenAddress
    );
    event LiquidityPoolCreated(
        address indexed pairAddress,
        address indexed ipToken
    );
    event RegistrationPaid(
        address indexed user,
        uint256 indexed nftId,
        uint256 amount
    );
    event LicensePaid(
        address indexed licensor,
        address indexed licensee,
        uint256 amount
    );
    event ArbitratorPaid(
        address indexed arbitrator,
        uint256 indexed disputeId,
        uint256 amount
    );
    event AwardDistributed(
        address indexed winner,
        uint256 indexed disputeId,
        uint256 amount
    );
    event EscrowRefunded(
        address indexed recipient,
        uint256 indexed disputeId,
        uint256 amount
    );
    event IncentivesDistributed(address indexed recipient, uint256 amount);

    // Structs
    struct WrappedIP {
        uint256 nftId;
        address nftContract;
        uint256 totalSupply;
        uint256 pricePerToken;
        address creator;
        bool isActive;
        string metadata;
    }

    struct LiquidityPool {
        address pairAddress;
        address ipToken;
        uint256 totalLiquidity;
        uint256 rewardRate;
        uint256 lastRewardBlock;
        bool isActive;
    }

    // Treasury Functions
    function wrapCopyrightNFT(
        address nftContract,
        uint256 nftId,
        uint256 totalSupply,
        uint256 pricePerToken,
        string memory metadata
    ) external returns (address tokenAddress);

    function createLiquidityPool(
        address wrappedIPToken,
        uint256 ipTokenAmount,
        uint256 slawAmount
    ) external returns (address pairAddress);

    // Payment Functions
    function payRegistrationFee(address user, uint256 nftId) external;
    function payLicenseFee(
        address licensor,
        address licensee,
        uint256 licenseId,
        uint256 amount
    ) external;
    function payArbitratorFee(
        address arbitrator,
        uint256 disputeId,
        uint256 amount
    ) external;
    function distributeAward(
        address winner,
        uint256 disputeId,
        uint256 amount
    ) external;
    function refundEscrow(
        address recipient,
        uint256 disputeId,
        uint256 amount
    ) external;
    function distributeIncentives(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external;

    // Reward Functions
    function distributeRewards(address pairAddress, address provider) external;
    function addToRewardPool(uint256 amount) external;

    // View Functions
    function getTreasuryBalance() external view returns (uint256);
    function getWrappedIPDetails(
        address tokenAddress
    ) external view returns (WrappedIP memory);
    function getLiquidityPoolDetails(
        address pairAddress
    ) external view returns (LiquidityPool memory);
    function getSystemMetrics()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}
