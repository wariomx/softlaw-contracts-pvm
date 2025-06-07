const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("🏛️ Softlaw Treasury & IP Liquidity Integration", function () {
    let treasury, wrappedIPFactory, liquidityFactory, copyrightsRegistry;
    let owner, user1, user2, feeCollector;
    let mockNFT;

    // Test constants
    const INITIAL_SLAW_SUPPLY = ethers.parseEther("10000000000"); // 10B SLAW
    const REGISTRATION_FEE = ethers.parseEther("100"); // 100 SLAW
    const LICENSE_BASE_FEE = ethers.parseEther("50"); // 50 SLAW

    beforeEach(async function () {
        [owner, user1, user2, feeCollector] = await ethers.getSigners();

        console.log("\n🚀 Setting up Softlaw Ecosystem...");

        // Deploy mock NFT contract for testing
        const MockNFT = await ethers.getContractFactory("contracts/test/MockCopyrightNFT.sol:MockCopyrightNFT");
        mockNFT = await MockNFT.deploy();
        await mockNFT.waitForDeployment();

        // Deploy Uniswap V2 Factory
        const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
        liquidityFactory = await UniswapV2Factory.deploy(owner.address);
        await liquidityFactory.waitForDeployment();

        // Deploy Softlaw Treasury
        const SoftlawTreasury = await ethers.getContractFactory("SoftlawTreasury");
        treasury = await SoftlawTreasury.deploy(
            owner.address,
            await liquidityFactory.getAddress(),
            feeCollector.address
        );
        await treasury.waitForDeployment();

        // Deploy Wrapped IP Factory
        const WrappedIPFactory = await ethers.getContractFactory("WrappedIPFactory");
        wrappedIPFactory = await WrappedIPFactory.deploy(
            await treasury.getAddress(),
            owner.address
        );
        await wrappedIPFactory.waitForDeployment();

        // Deploy Copyright Registry (simplified for testing)
        const MockRegistry = await ethers.getContractFactory("contracts/test/MockCopyrightRegistry.sol:MockCopyrightRegistry");
        copyrightsRegistry = await MockRegistry.deploy(await treasury.getAddress());
        await copyrightsRegistry.waitForDeployment();

        // Setup permissions
        const REGISTRY_ROLE = await treasury.REGISTRY_CONTRACT();
        await treasury.grantRole(REGISTRY_ROLE, await copyrightsRegistry.getAddress());

        console.log("✅ Ecosystem setup complete!");
    });

    describe("💰 SLAW Token & Treasury", function () {
        it("Should have correct initial SLAW supply", async function () {
            const treasuryBalance = await treasury.getTreasuryBalance();
            expect(treasuryBalance).to.equal(INITIAL_SLAW_SUPPLY);
        });

        it("Should have correct token metadata", async function () {
            expect(await treasury.name()).to.equal("SoftLaw Token");
            expect(await treasury.symbol()).to.equal("SLAW");
            expect(await treasury.decimals()).to.equal(18);
        });

        it("Should distribute SLAW tokens correctly", async function () {
            const amount = ethers.parseEther("1000");
            
            await treasury.distributeIncentives([user1.address], [amount]);
            
            const user1Balance = await treasury.balanceOf(user1.address);
            expect(user1Balance).to.equal(amount);
        });
    });

    describe("🎁 IP Wrapping System", function () {
        let nftId;

        beforeEach(async function () {
            // Mint NFT to user1
            await mockNFT.connect(user1).mint(user1.address, "Test IP");
            nftId = 1; // First NFT ID
        });

        it("Should wrap copyright NFT into tokens", async function () {
            const totalSupply = ethers.parseEther("1000"); // 1000 IP tokens
            const pricePerToken = ethers.parseEther("1"); // 1 SLAW per IP token
            
            // Approve treasury to handle NFT
            await mockNFT.connect(user1).approve(await treasury.getAddress(), nftId);
            
            // Wrap the NFT
            const tx = await treasury.connect(user1).wrapCopyrightNFT(
                await mockNFT.getAddress(),
                nftId,
                totalSupply,
                pricePerToken,
                "Test Wrapped IP"
            );

            await expect(tx).to.emit(treasury, "IPWrapped");
            
            // Verify NFT is now owned by treasury
            expect(await mockNFT.ownerOf(nftId)).to.equal(await treasury.getAddress());
            
            // Verify wrapped IP details
            const wrappedTokenAddress = await treasury.wrappedIPTokens(nftId);
            const ipDetails = await treasury.getWrappedIPDetails(wrappedTokenAddress);
            
            expect(ipDetails.nftId).to.equal(nftId);
            expect(ipDetails.creator).to.equal(user1.address);
            expect(ipDetails.totalSupply).to.equal(totalSupply);
            expect(ipDetails.isActive).to.be.true;
        });

        it("Should prevent double wrapping of same NFT", async function () {
            const totalSupply = ethers.parseEther("1000");
            const pricePerToken = ethers.parseEther("1");
            
            await mockNFT.connect(user1).approve(await treasury.getAddress(), nftId);
            
            // First wrap
            await treasury.connect(user1).wrapCopyrightNFT(
                await mockNFT.getAddress(),
                nftId,
                totalSupply,
                pricePerToken,
                "Test IP"
            );
            
            // Try to wrap again - should fail
            await expect(
                treasury.connect(user1).wrapCopyrightNFT(
                    await mockNFT.getAddress(),
                    nftId,
                    totalSupply,
                    pricePerToken,
                    "Test IP 2"
                )
            ).to.be.revertedWith("NFT already wrapped");
        });
    });

    describe("🏊 Liquidity Pool Creation", function () {
        let wrappedIPToken, nftId;

        beforeEach(async function () {
            // Setup wrapped IP token
            nftId = 1;
            await mockNFT.connect(user1).mint(user1.address, "Test IP");
            await mockNFT.connect(user1).approve(await treasury.getAddress(), nftId);
            
            await treasury.connect(user1).wrapCopyrightNFT(
                await mockNFT.getAddress(),
                nftId,
                ethers.parseEther("1000"),
                ethers.parseEther("1"),
                "Test IP"
            );
            
            wrappedIPToken = await treasury.wrappedIPTokens(nftId);
            
            // Give user1 some SLAW tokens
            await treasury.distributeIncentives([user1.address], [ethers.parseEther("2000")]);
        });

        it("Should create liquidity pool successfully", async function () {
            const ipTokenAmount = ethers.parseEther("500");
            const slawAmount = ethers.parseEther("1000");
            
            // Note: In a real implementation, we'd need to handle the wrapped IP token transfers
            // For this test, we'll focus on the treasury interaction
            
            const tx = await treasury.connect(user1).createLiquidityPool(
                wrappedIPToken,
                ipTokenAmount,
                slawAmount
            );
            
            await expect(tx).to.emit(treasury, "LiquidityPoolCreated");
            
            // Verify liquidity pool creation
            const pairAddress = await liquidityFactory.getPair(wrappedIPToken, await treasury.getAddress());
            expect(pairAddress).to.not.equal(ethers.ZeroAddress);
            
            // Verify pool details
            const poolDetails = await treasury.getLiquidityPoolDetails(pairAddress);
            expect(poolDetails.isActive).to.be.true;
            expect(poolDetails.ipToken).to.equal(wrappedIPToken);
        });
    });

    describe("💳 Payment System", function () {
        beforeEach(async function () {
            // Give users SLAW tokens for payments
            await treasury.distributeIncentives(
                [user1.address, user2.address], 
                [ethers.parseEther("1000"), ethers.parseEther("1000")]
            );
        });

        it("Should process registration fee payment", async function () {
            const initialBalance = await treasury.balanceOf(user1.address);
            const initialCollectorBalance = await treasury.balanceOf(feeCollector.address);
            
            await treasury.connect(user1).approve(await copyrightsRegistry.getAddress(), REGISTRATION_FEE);
            
            const tx = await copyrightsRegistry.connect(user1).registerAndPay(1);
            
            await expect(tx).to.emit(treasury, "RegistrationPaid");
            
            // Verify balances
            expect(await treasury.balanceOf(user1.address)).to.equal(initialBalance - REGISTRATION_FEE);
            expect(await treasury.balanceOf(feeCollector.address)).to.equal(initialCollectorBalance + REGISTRATION_FEE);
        });

        it("Should process license fee payment with revenue split", async function () {
            const licenseAmount = ethers.parseEther("200");
            const totalFee = LICENSE_BASE_FEE + licenseAmount;
            const licensorShare = (totalFee * 70n) / 100n;
            const protocolShare = totalFee - licensorShare;
            
            await treasury.connect(user2).approve(await treasury.getAddress(), totalFee);
            
            const tx = await treasury.payLicenseFee(
                user1.address, // licensor
                user2.address, // licensee
                1, // license ID
                licenseAmount
            );
            
            await expect(tx).to.emit(treasury, "LicensePaid");
            
            // Verify 70/30 split
            expect(await treasury.balanceOf(user1.address)).to.equal(
                ethers.parseEther("1000") + licensorShare
            );
            expect(await treasury.balanceOf(feeCollector.address)).to.equal(protocolShare);
        });

        it("Should revert payment if insufficient balance", async function () {
            // Try to pay with user who has no tokens
            await expect(
                copyrightsRegistry.connect(owner).registerAndPay(1)
            ).to.be.revertedWith("Insufficient SLAW balance");
        });
    });

    describe("🎁 Reward System", function () {
        it("Should add to reward pool", async function () {
            const amount = ethers.parseEther("1000");
            const initialMetrics = await treasury.getSystemMetrics();
            
            await treasury.addToRewardPool(amount);
            
            const newMetrics = await treasury.getSystemMetrics();
            expect(newMetrics[4]).to.equal(initialMetrics[4] + amount); // Reward pool increased
        });

        it("Should track system metrics correctly", async function () {
            const metrics = await treasury.getSystemMetrics();
            
            expect(metrics[0]).to.equal(INITIAL_SLAW_SUPPLY); // Treasury balance
            expect(metrics[1]).to.equal(0); // Total wrapped IPs
            expect(metrics[2]).to.equal(0); // Total liquidity pools
            expect(metrics[3]).to.equal(0); // Total fees collected
            expect(metrics[4]).to.equal(INITIAL_SLAW_SUPPLY / 10n); // Reward pool (10% of initial)
        });
    });

    describe("🔐 Access Control", function () {
        it("Should prevent unauthorized minting", async function () {
            await expect(
                treasury.connect(user1).mintSLAW(ethers.parseEther("1000"))
            ).to.be.reverted;
        });

        it("Should prevent unauthorized role grants", async function () {
            const REGISTRY_ROLE = await treasury.REGISTRY_CONTRACT();
            await expect(
                treasury.connect(user1).grantRole(REGISTRY_ROLE, user2.address)
            ).to.be.reverted;
        });

        it("Should allow admin functions for owner", async function () {
            const amount = ethers.parseEther("1000");
            await expect(
                treasury.connect(owner).mintSLAW(amount)
            ).to.not.be.reverted;
        });
    });

    describe("🎬 Complete User Flow", function () {
        it("Should complete full IP → Liquidity flow", async function () {
            console.log("\n🎬 Testing complete user flow...");
            
            // 1. User registers IP
            console.log("1. 📄 Registering copyright NFT...");
            await mockNFT.connect(user1).mint(user1.address, "Innovation Patent");
            const nftId = 1;
            
            // Give user1 SLAW for fees
            await treasury.distributeIncentives([user1.address], [ethers.parseEther("5000")]);
            
            // 2. User wraps IP
            console.log("2. 🎁 Wrapping NFT into tokens...");
            await mockNFT.connect(user1).approve(await treasury.getAddress(), nftId);
            await treasury.connect(user1).wrapCopyrightNFT(
                await mockNFT.getAddress(),
                nftId,
                ethers.parseEther("1000"), // 1000 IP tokens
                ethers.parseEther("2"),     // 2 SLAW per IP token
                "Innovation Patent Tokens"
            );
            
            const wrappedToken = await treasury.wrappedIPTokens(nftId);
            console.log("   ✅ Wrapped token created:", wrappedToken);
            
            // 3. User creates liquidity pool
            console.log("3. 🏊 Creating liquidity pool...");
            await treasury.connect(user1).createLiquidityPool(
                wrappedToken,
                ethers.parseEther("500"),  // 500 IP tokens
                ethers.parseEther("1000")  // 1000 SLAW
            );
            
            // 4. Verify system state
            console.log("4. 📊 Verifying system state...");
            const metrics = await treasury.getSystemMetrics();
            expect(metrics[1]).to.equal(1); // 1 wrapped IP
            expect(metrics[2]).to.equal(1); // 1 liquidity pool
            
            console.log("   ✅ Treasury Balance:", ethers.formatEther(metrics[0]), "SLAW");
            console.log("   ✅ Total Wrapped IPs:", metrics[1].toString());
            console.log("   ✅ Total Liquidity Pools:", metrics[2].toString());
            
            console.log("🎉 Complete flow successful!");
        });
    });
});

// Helper function to create mock contracts for testing
async function deployMockContracts() {
    const MockNFT = await ethers.getContractFactory(`
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.19;
        
        import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
        
        contract MockCopyrightNFT is ERC721 {
            uint256 private _tokenId = 0;
            
            constructor() ERC721("Mock Copyright", "MCR") {}
            
            function mint(address to, string memory) public {
                _tokenId++;
                _mint(to, _tokenId);
            }
        }
    `);
    
    const MockRegistry = await ethers.getContractFactory(`
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.19;
        
        interface ITreasury {
            function payRegistrationFee(address user, uint256 nftId) external;
        }
        
        contract MockCopyrightRegistry {
            ITreasury public treasury;
            
            constructor(address _treasury) {
                treasury = ITreasury(_treasury);
            }
            
            function registerAndPay(uint256 nftId) external {
                treasury.payRegistrationFee(msg.sender, nftId);
            }
        }
    `);
    
    return { MockNFT, MockRegistry };
}
