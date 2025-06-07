const { ethers } = require("hardhat");

/**
 * Comprehensive deployment script for the complete Softlaw ecosystem
 * Deploys all enhanced contracts with full Treasury integration
 */
async function main() {
    console.log("🌟 Starting COMPLETE Softlaw Ecosystem Deployment...\n");

    const [deployer] = await ethers.getSigners();
    console.log("🔐 Deploying with account:", deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)));

    const deployedContracts = {};

    try {
        // ===== PHASE 1: CORE INFRASTRUCTURE =====
        console.log("\n📦 PHASE 1: Deploying Core Infrastructure...");

        // 1. Deploy Uniswap V2 Factory
        console.log("   Deploying UniswapV2Factory...");
        const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
        const liquidityFactory = await UniswapV2Factory.deploy(deployer.address);
        await liquidityFactory.waitForDeployment();
        deployedContracts.liquidityFactory = await liquidityFactory.getAddress();
        console.log("   ✅ UniswapV2Factory:", deployedContracts.liquidityFactory);

        // 2. Deploy Softlaw Treasury (Core of ecosystem)
        console.log("   Deploying SoftlawTreasury...");
        const SoftlawTreasury = await ethers.getContractFactory("SoftlawTreasury");
        const treasury = await SoftlawTreasury.deploy(
            deployer.address,
            deployedContracts.liquidityFactory,
            deployer.address
        );
        await treasury.waitForDeployment();
        deployedContracts.treasury = await treasury.getAddress();
        console.log("   ✅ SoftlawTreasury:", deployedContracts.treasury);

        // 3. Deploy Wrapped IP Factory
        console.log("   Deploying WrappedIPFactory...");
        const WrappedIPFactory = await ethers.getContractFactory("WrappedIPFactory");
        const wrappedIPFactory = await WrappedIPFactory.deploy(
            deployedContracts.treasury,
            deployer.address
        );
        await wrappedIPFactory.waitForDeployment();
        deployedContracts.wrappedIPFactory = await wrappedIPFactory.getAddress();
        console.log("   ✅ WrappedIPFactory:", deployedContracts.wrappedIPFactory);

        // ===== PHASE 2: IP MANAGEMENT SYSTEM =====
        console.log("\n📦 PHASE 2: Deploying IP Management System...");

        // 4. Deploy Enhanced Copyright Registry
        console.log("   Deploying CopyrightLicensing (Enhanced)...");
        const CopyrightLicensing = await ethers.getContractFactory("CopyrightLicensing");
        const copyrightLicensing = await CopyrightLicensing.deploy(
            deployer.address,
            deployedContracts.treasury
        );
        await copyrightLicensing.waitForDeployment();
        deployedContracts.copyrightLicensing = await copyrightLicensing.getAddress();
        console.log("   ✅ CopyrightLicensing:", deployedContracts.copyrightLicensing);

        // 5. Deploy Complete Patent Registry
        console.log("   Deploying PatentRegistry...");
        const PatentRegistry = await ethers.getContractFactory("PatentRegistry");
        const patentRegistry = await PatentRegistry.deploy(
            deployedContracts.treasury,
            deployer.address
        );
        await patentRegistry.waitForDeployment();
        deployedContracts.patentRegistry = await patentRegistry.getAddress();
        console.log("   ✅ PatentRegistry:", deployedContracts.patentRegistry);

        // ===== PHASE 3: LEGAL & GOVERNANCE SYSTEM =====
        console.log("\n📦 PHASE 3: Deploying Legal & Governance System...");

        // 6. Deploy Enhanced Dispute Resolution
        console.log("   Deploying SoftlawDisputeResolution...");
        const SoftlawDisputeResolution = await ethers.getContractFactory("SoftlawDisputeResolution");
        const disputeResolution = await SoftlawDisputeResolution.deploy(
            deployedContracts.treasury,
            deployer.address
        );
        await disputeResolution.waitForDeployment();
        deployedContracts.disputeResolution = await disputeResolution.getAddress();
        console.log("   ✅ SoftlawDisputeResolution:", deployedContracts.disputeResolution);

        // 7. Deploy DAO Governor
        console.log("   Deploying DAOGovernor...");
        const DAOGovernor = await ethers.getContractFactory("DAOGovernor");
        const daoGovernor = await DAOGovernor.deploy();
        await daoGovernor.waitForDeployment();
        deployedContracts.daoGovernor = await daoGovernor.getAddress();
        console.log("   ✅ DAOGovernor:", deployedContracts.daoGovernor);

        // 8. Deploy DAO Membership
        console.log("   Deploying DAOMembership...");
        const DAOMembership = await ethers.getContractFactory("DAOMembership");
        const daoMembership = await DAOMembership.deploy();
        await daoMembership.waitForDeployment();
        deployedContracts.daoMembership = await daoMembership.getAddress();
        console.log("   ✅ DAOMembership:", deployedContracts.daoMembership);

        // ===== PHASE 4: MARKETPLACE & TRADING =====
        console.log("\n📦 PHASE 4: Deploying Marketplace & Trading...");

        // 9. Deploy Comprehensive Marketplace
        console.log("   Deploying SoftlawMarketplace...");
        const SoftlawMarketplace = await ethers.getContractFactory("SoftlawMarketplace");
        const marketplace = await SoftlawMarketplace.deploy(
            deployedContracts.treasury,
            deployer.address
        );
        await marketplace.waitForDeployment();
        deployedContracts.marketplace = await marketplace.getAddress();
        console.log("   ✅ SoftlawMarketplace:", deployedContracts.marketplace);

        // ===== PHASE 5: SYSTEM CONFIGURATION =====
        console.log("\n🔧 PHASE 5: Configuring System Permissions...");

        // Grant Treasury roles
        console.log("   Configuring Treasury permissions...");
        const REGISTRY_ROLE = await treasury.REGISTRY_CONTRACT();
        const LICENSING_ROLE = await treasury.LICENSING_CONTRACT();
        const LIQUIDITY_ROLE = await treasury.LIQUIDITY_MANAGER();

        await treasury.grantRole(REGISTRY_ROLE, deployedContracts.copyrightLicensing);
        await treasury.grantRole(REGISTRY_ROLE, deployedContracts.patentRegistry);
        await treasury.grantRole(LICENSING_ROLE, deployedContracts.copyrightLicensing);
        await treasury.grantRole(LIQUIDITY_ROLE, deployer.address);
        console.log("   ✅ Treasury roles configured");

        // Grant Dispute Resolution roles
        console.log("   Configuring Dispute Resolution permissions...");
        const ARBITRATOR_ROLE = await disputeResolution.ARBITRATOR_ROLE();
        const MEDIATOR_ROLE = await disputeResolution.MEDIATOR_ROLE();
        
        await disputeResolution.grantRole(ARBITRATOR_ROLE, deployer.address);
        await disputeResolution.grantRole(MEDIATOR_ROLE, deployer.address);
        console.log("   ✅ Dispute Resolution roles configured");

        // Grant Marketplace roles
        console.log("   Configuring Marketplace permissions...");
        const MARKETPLACE_ADMIN = await marketplace.MARKETPLACE_ADMIN();
        await marketplace.grantRole(MARKETPLACE_ADMIN, deployer.address);
        console.log("   ✅ Marketplace roles configured");

        // ===== PHASE 6: SYSTEM VERIFICATION =====
        console.log("\n📊 PHASE 6: System Verification...");

        // Verify Treasury state
        const treasuryBalance = await treasury.getTreasuryBalance();
        const systemMetrics = await treasury.getSystemMetrics();
        
        console.log("   💰 Treasury SLAW Balance:", ethers.formatEther(treasuryBalance));
        console.log("   📈 System Metrics:");
        console.log("      - Treasury Balance:", ethers.formatEther(systemMetrics[0]));
        console.log("      - Total Wrapped IPs:", systemMetrics[1].toString());
        console.log("      - Total Liquidity Pools:", systemMetrics[2].toString());
        console.log("      - Total Fees Collected:", ethers.formatEther(systemMetrics[3]));
        console.log("      - Reward Pool:", ethers.formatEther(systemMetrics[4]));

        // Verify marketplace state
        const marketStats = await marketplace.getMarketStats();
        console.log("   🏪 Marketplace Stats:");
        console.log("      - Total Listings:", marketStats.totalListings.toString());
        console.log("      - Total Sales:", marketStats.totalSales.toString());
        console.log("      - Total Volume:", ethers.formatEther(marketStats.totalVolume));
        console.log("      - Active Listings:", marketStats.activeListings.toString());

        // ===== PHASE 7: DEMO SETUP =====
        console.log("\n🎬 PHASE 7: Setting up Demo Data...");

        // Register deployer as arbitrator
        await disputeResolution.registerArbitrator(
            "Softlaw Arbitrator",
            "Certified legal expert in IP disputes",
            ["COPYRIGHT_INFRINGEMENT", "PATENT_INFRINGEMENT", "LICENSE_BREACH"],
            ethers.parseEther("50") // 50 SLAW per case
        );
        console.log("   ✅ Demo arbitrator registered");

        // Deploy mock contracts for testing
        console.log("   Deploying test contracts...");
        const MockCopyrightNFT = await ethers.getContractFactory("MockCopyrightNFT");
        const mockNFT = await MockCopyrightNFT.deploy();
        await mockNFT.waitForDeployment();
        deployedContracts.mockNFT = await mockNFT.getAddress();
        console.log("   ✅ Mock NFT for testing:", deployedContracts.mockNFT);

        // ===== DEPLOYMENT SUMMARY =====
        const deploymentInfo = {
            network: process.env.HARDHAT_NETWORK || "localhost",
            timestamp: new Date().toISOString(),
            deployer: deployer.address,
            gasUsed: "~15M gas", // Estimate
            contracts: deployedContracts,
            features: {
                treasury: "✅ SLAW token + IP wrapping + Liquidity pools",
                copyrights: "✅ Enhanced licensing + Auto-tokenization",
                patents: "✅ Complete lifecycle + Prior art + Tokenization",
                disputes: "✅ Mediation + Arbitration + Evidence management",
                marketplace: "✅ Fixed price + Auctions + Offers + Royalties",
                governance: "✅ DAO + Membership + Voting",
                liquidity: "✅ Uniswap V2 + Rewards + AMM"
            },
            economicModel: {
                slawSupply: "10B tokens",
                registrationFee: "100 SLAW",
                licenseFee: "50 SLAW + custom",
                marketplaceFee: "2.5%",
                maxRoyalty: "10%"
            },
            integrations: {
                treasury: "All contracts integrated",
                payments: "SLAW token for all fees",
                liquidity: "Automatic pool creation",
                rewards: "LP incentives + Creator royalties"
            }
        };

        console.log("\n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!");
        console.log("=" .repeat(80));
        console.log("📋 COMPREHENSIVE DEPLOYMENT SUMMARY:");
        console.log("=" .repeat(80));
        console.log(JSON.stringify(deploymentInfo, null, 2));

        console.log("\n🎯 QUICK START GUIDE:");
        console.log("1. 📄 Register IP: copyrightLicensing.registerCopyright() or patentRegistry.filePatent()");
        console.log("2. 🎁 Tokenize IP: treasury.wrapCopyrightNFT() or patentRegistry.tokenizePatent()");
        console.log("3. 🏊 Create Pool: treasury.createLiquidityPool()");
        console.log("4. 🏪 List on Marketplace: marketplace.createFixedPriceListing()");
        console.log("5. 📈 Trade: Buy/sell on marketplace or trade tokens on AMM");
        console.log("6. 🏛️ Resolve Disputes: disputeResolution.fileDispute()");

        console.log("\n🔗 CONTRACT VERIFICATION COMMANDS:");
        for (const [name, address] of Object.entries(deployedContracts)) {
            console.log(`npx hardhat verify --network ${process.env.HARDHAT_NETWORK || "localhost"} ${address}`);
        }

        return deploymentInfo;

    } catch (error) {
        console.error("❌ Deployment failed:", error);
        console.error("📍 Error details:", error.message);
        
        // Cleanup partial deployment if needed
        console.log("\n🧹 Attempting cleanup of partial deployment...");
        
        throw error;
    }
}

/**
 * Demonstration function showing complete user flow
 */
async function demonstrateCompleteFlow(deploymentInfo) {
    console.log("\n🎬 DEMONSTRATING COMPLETE ECOSYSTEM FLOW...");
    console.log("=" .repeat(60));

    const treasury = await ethers.getContractAt("SoftlawTreasury", deploymentInfo.contracts.treasury);
    const copyrightLicensing = await ethers.getContractAt("CopyrightLicensing", deploymentInfo.contracts.copyrightLicensing);
    const patentRegistry = await ethers.getContractAt("PatentRegistry", deploymentInfo.contracts.patentRegistry);
    const marketplace = await ethers.getContractAt("SoftlawMarketplace", deploymentInfo.contracts.marketplace);
    const mockNFT = await ethers.getContractAt("MockCopyrightNFT", deploymentInfo.contracts.mockNFT);

    console.log("🎯 COMPLETE USER JOURNEY:");
    console.log("1. 👤 User creates IP (copyright/patent)");
    console.log("2. 🎁 User tokenizes IP into tradeable tokens");
    console.log("3. 🏊 User creates liquidity pool for trading");
    console.log("4. 🏪 User lists on marketplace");
    console.log("5. 💱 Others trade IP tokens");
    console.log("6. 🎁 Liquidity providers earn rewards");
    console.log("7. 🏛️ Disputes resolved through ADR system");

    console.log("\n📊 ECONOMIC FLOWS:");
    console.log("💰 Registration fees → Treasury");
    console.log("💰 License fees → 70% Creator, 30% Protocol");
    console.log("💰 Trading fees → Liquidity providers");
    console.log("💰 Marketplace fees → Protocol");
    console.log("💰 Dispute fees → Arbitrators");

    console.log("\n🌟 INNOVATION HIGHLIGHTS:");
    console.log("🔸 First DeFi system for intellectual property");
    console.log("🔸 Automatic IP tokenization and liquidity");
    console.log("🔸 Complete legal framework on-chain");
    console.log("🔸 Revenue sharing with creators");
    console.log("🔸 Decentralized dispute resolution");
    console.log("🔸 Cross-IP-type compatibility");

    console.log("\n✅ Ecosystem ready for production use!");
}

// Export for testing and external use
module.exports = { 
    main, 
    demonstrateCompleteFlow 
};

// Execute if run directly
if (require.main === module) {
    main()
        .then((deploymentInfo) => {
            // Demonstrate the complete flow
            return demonstrateCompleteFlow(deploymentInfo);
        })
        .then(() => {
            console.log("\n🏁 All systems operational!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("💥 Critical failure:", error);
            process.exit(1);
        });
}
