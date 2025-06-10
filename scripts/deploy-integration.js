const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🚀 Starting Softlaw PVM Integration Deployment with Creator Economy...\n");
    
    const [deployer] = await ethers.getSigners();
    console.log("📋 Deploying contracts with account:", deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

    const deploymentData = {
        network: hre.network.name,
        deployer: deployer.address,
        timestamp: new Date().toISOString(),
        contracts: {}
    };

    try {
        // ===== STEP 1: Deploy SLAW Token =====
        console.log("📦 1/6 Deploying SLAWToken...");
        const SLAWToken = await ethers.getContractFactory("SLAWToken");
        
        // Treasury core placeholder (will update after treasury deployment)
        const placeholderTreasury = deployer.address;
        
        const slawToken = await SLAWToken.deploy(
            deployer.address, // admin
            placeholderTreasury // treasury core (temporary)
        );
        await slawToken.waitForDeployment();
        
        const slawAddress = await slawToken.getAddress();
        console.log("✅ SLAWToken deployed to:", slawAddress);
        
        deploymentData.contracts.SLAWToken = {
            address: slawAddress,
            admin: deployer.address,
            treasuryCore: placeholderTreasury
        };

        // ===== STEP 2: Deploy Treasury Core =====
        console.log("\n📦 2/6 Deploying TreasuryCore...");
        const TreasuryCore = await ethers.getContractFactory("TreasuryCore");
        
        const treasuryCore = await TreasuryCore.deploy(
            deployer.address, // admin
            slawAddress, // SLAW token
            deployer.address // fee collector (can be changed later)
        );
        await treasuryCore.waitForDeployment();
        
        const treasuryCoreAddress = await treasuryCore.getAddress();
        console.log("✅ TreasuryCore deployed to:", treasuryCoreAddress);
        
        deploymentData.contracts.TreasuryCore = {
            address: treasuryCoreAddress,
            admin: deployer.address,
            slawToken: slawAddress,
            feeCollector: deployer.address
        };

        // ===== STEP 3: Update SLAW Token with correct Treasury =====
        console.log("\n🔧 3/6 Updating SLAWToken with TreasuryCore...");
        await slawToken.updateTreasuryCore(treasuryCoreAddress);
        console.log("✅ SLAWToken treasury updated");
        
        deploymentData.contracts.SLAWToken.treasuryCore = treasuryCoreAddress;

        // ===== STEP 4: Deploy Wrapped IP Manager =====
        console.log("\n📦 4/6 Deploying WrappedIPManager with Creator Profiles...");
        const WrappedIPManager = await ethers.getContractFactory("WrappedIPManager");
        
        const wrappedIPManager = await WrappedIPManager.deploy(
            deployer.address, // admin
            slawAddress, // SLAW token
            treasuryCoreAddress // treasury core
        );
        await wrappedIPManager.waitForDeployment();
        
        const wrappedIPManagerAddress = await wrappedIPManager.getAddress();
        console.log("✅ WrappedIPManager deployed to:", wrappedIPManagerAddress);
        
        deploymentData.contracts.WrappedIPManager = {
            address: wrappedIPManagerAddress,
            admin: deployer.address,
            slawToken: slawAddress,
            treasuryCore: treasuryCoreAddress
        };

        // ===== STEP 5: Deploy Enhanced Liquidity Manager =====
        console.log("\n📦 5/6 Deploying Enhanced LiquidityManager...");
        const LiquidityManager = await ethers.getContractFactory("LiquidityManager");
        
        const liquidityManager = await LiquidityManager.deploy(
            deployer.address, // admin
            slawAddress, // SLAW token
            wrappedIPManagerAddress, // wrapped IP manager
            treasuryCoreAddress // treasury core
        );
        await liquidityManager.waitForDeployment();
        
        const liquidityManagerAddress = await liquidityManager.getAddress();
        console.log("✅ Enhanced LiquidityManager deployed to:", liquidityManagerAddress);
        
        deploymentData.contracts.LiquidityManager = {
            address: liquidityManagerAddress,
            admin: deployer.address,
            slawToken: slawAddress,
            wrappedIPManager: wrappedIPManagerAddress,
            treasuryCore: treasuryCoreAddress
        };

        // ===== STEP 6: Deploy Marketplace Core =====
        console.log("\n📦 6/6 Deploying MarketplaceCore...");
        const MarketplaceCore = await ethers.getContractFactory("MarketplaceCore");
        
        const marketplaceCore = await MarketplaceCore.deploy(
            deployer.address, // admin
            slawAddress, // SLAW token
            treasuryCoreAddress // treasury core
        );
        await marketplaceCore.waitForDeployment();
        
        const marketplaceCoreAddress = await marketplaceCore.getAddress();
        console.log("✅ MarketplaceCore deployed to:", marketplaceCoreAddress);
        
        deploymentData.contracts.MarketplaceCore = {
            address: marketplaceCoreAddress,
            admin: deployer.address,
            slawToken: slawAddress,
            treasuryCore: treasuryCoreAddress
        };

        // ===== STEP 7: Configure Role-Based Access Control =====
        console.log("\n🔧 Configuring RBAC and System Integration...");
        
        // Grant treasury roles
        const REGISTRY_CONTRACT = ethers.keccak256(ethers.toUtf8Bytes("REGISTRY_CONTRACT"));
        const LICENSING_CONTRACT = ethers.keccak256(ethers.toUtf8Bytes("LICENSING_CONTRACT"));
        const MARKETPLACE_CONTRACT = ethers.keccak256(ethers.toUtf8Bytes("MARKETPLACE_CONTRACT"));
        
        // Grant marketplace contract role to MarketplaceCore
        await treasuryCore.grantRole(MARKETPLACE_CONTRACT, marketplaceCoreAddress);
        console.log("✅ Granted MARKETPLACE_CONTRACT role to MarketplaceCore");
        
        // Update treasury system addresses
        await treasuryCore.updateSystemAddress("wrappedIPManager", wrappedIPManagerAddress);
        await treasuryCore.updateSystemAddress("liquidityManager", liquidityManagerAddress);
        console.log("✅ Updated treasury system addresses");

        // ===== STEP 8: Initial SLAW Distribution and Rewards Setup =====
        console.log("\n💰 Setting up Creator Economy...");
        
        // Transfer initial SLAW to deployer for testing
        const testAmount = ethers.parseEther("1000000"); // 1M SLAW
        await slawToken.treasuryTransfer(deployer.address, testAmount);
        console.log("✅ Transferred 1M SLAW to deployer for testing");
        
        // Fund liquidity manager with rewards
        const rewardsAmount = ethers.parseEther("5000000"); // 5M SLAW for rewards
        await slawToken.treasuryTransfer(liquidityManagerAddress, rewardsAmount);
        console.log("✅ Funded LiquidityManager with 5M SLAW for rewards");
        
        // Create deployer creator profile
        await wrappedIPManager.createCreatorProfile(
            "System Admin",
            "Official Softlaw system administrator and first creator",
            "https://softlaw.example.com/avatar/admin"
        );
        console.log("✅ Created deployer creator profile");
        
        // Verify the deployer as first creator
        await wrappedIPManager.verifyCreator(deployer.address, true);
        console.log("✅ Verified deployer as official creator");

        // ===== STEP 9: Save Deployment Data =====
        console.log("\n💾 Saving deployment data with creator economy info...");
        
        const deploymentsDir = path.join(__dirname, "../deployments");
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        
        // Save main deployment file
        const deploymentPath = path.join(deploymentsDir, `integration-deployment-${hre.network.name}.json`);
        fs.writeFileSync(deploymentPath, JSON.stringify(deploymentData, null, 2));
        
        // Save contract addresses file
        const contractAddresses = {
            SLAWToken: slawAddress,
            TreasuryCore: treasuryCoreAddress,
            WrappedIPManager: wrappedIPManagerAddress,
            LiquidityManager: liquidityManagerAddress,
            MarketplaceCore: marketplaceCoreAddress
        };
        
        const addressPath = path.join(deploymentsDir, `contract-addresses-${hre.network.name}.json`);
        fs.writeFileSync(addressPath, JSON.stringify(contractAddresses, null, 2));
        
        // Save ABIs
        const contracts = ["SLAWToken", "TreasuryCore", "WrappedIPManager", "LiquidityManager", "MarketplaceCore"];
        for (const contractName of contracts) {
            const artifact = await hre.artifacts.readArtifact(contractName);
            const abiPath = path.join(deploymentsDir, `${contractName}-abi.json`);
            fs.writeFileSync(abiPath, JSON.stringify(artifact.abi, null, 2));
        }
        
        // Save PersonalizedWrappedIPToken ABI as well
        const wrappedTokenArtifact = await hre.artifacts.readArtifact("PersonalizedWrappedIPToken");
        const wrappedTokenAbiPath = path.join(deploymentsDir, "PersonalizedWrappedIPToken-abi.json");
        fs.writeFileSync(wrappedTokenAbiPath, JSON.stringify(wrappedTokenArtifact.abi, null, 2));
        
        // Save ValuedLiquidityPair ABI
        const lpArtifact = await hre.artifacts.readArtifact("ValuedLiquidityPair");
        const lpAbiPath = path.join(deploymentsDir, "ValuedLiquidityPair-abi.json");
        fs.writeFileSync(lpAbiPath, JSON.stringify(lpArtifact.abi, null, 2));
        
        console.log("✅ Deployment data saved to:", deploymentPath);
        console.log("✅ Contract addresses saved to:", addressPath);
        console.log("✅ ABIs saved to deployments directory");

        // ===== Get System Metrics =====
        const slawTotalSupply = await slawToken.totalSupply();
        const slawTreasuryBalance = await slawToken.getTreasuryBalance();
        const slawCirculating = await slawToken.getCirculatingSupply();
        
        const treasuryMetrics = await treasuryCore.getSystemMetrics();
        const ipMetrics = await wrappedIPManager.getSystemMetrics();
        const liquidityMetrics = await liquidityManager.getSystemMetrics();
        const marketplaceMetrics = await marketplaceCore.getSystemMetrics();
        
        // Get creator profile
        const creatorProfile = await wrappedIPManager.getCreatorProfile(deployer.address);

        // ===== DEPLOYMENT SUMMARY =====
        console.log("\n🎉 ========================================");
        console.log("🎉 SOFTLAW CREATOR ECONOMY DEPLOYMENT COMPLETE!");
        console.log("🎉 ========================================\n");
        
        console.log("📋 Contract Addresses:");
        console.log("├── SLAWToken:", slawAddress);
        console.log("├── TreasuryCore:", treasuryCoreAddress);
        console.log("├── WrappedIPManager:", wrappedIPManagerAddress);
        console.log("├── LiquidityManager:", liquidityManagerAddress);
        console.log("└── MarketplaceCore:", marketplaceCoreAddress);
        
        console.log("\n🔧 System Configuration:");
        console.log("├── Admin:", deployer.address);
        console.log("├── Fee Collector:", deployer.address);
        console.log("├── SLAW Total Supply:", ethers.formatEther(slawTotalSupply));
        console.log("├── SLAW Treasury Balance:", ethers.formatEther(slawTreasuryBalance));
        console.log("├── SLAW Circulating:", ethers.formatEther(slawCirculating));
        console.log("└── Network:", hre.network.name);
        
        console.log("\n🎨 Creator Economy Features:");
        console.log("├── Creator Profiles: ✅ Enabled");
        console.log("├── Personalized Tokens: ✅ Enabled");
        console.log("├── Creator-Branded Pools: ✅ Enabled");
        console.log("├── Creator Rankings: ✅ Enabled");
        console.log("├── Liquidity Rewards: ✅ Enabled");
        console.log("├── Creator Bonuses: ✅ Enabled");
        console.log("└── Value Tracking: ✅ Enabled");
        
        console.log("\n📊 System Metrics:");
        console.log("├── Treasury Fees Collected:", ethers.formatEther(treasuryMetrics[0]), "SLAW");
        console.log("├── Total Registrations:", treasuryMetrics[1].toString());
        console.log("├── Total Licenses:", treasuryMetrics[2].toString());
        console.log("├── Wrapped IPs:", ipMetrics[0].toString());
        console.log("├── Total IP Tokens:", ethers.formatEther(ipMetrics[1]));
        console.log("├── Total Value Locked:", ethers.formatEther(ipMetrics[2]), "SLAW");
        console.log("├── Total Creators:", ipMetrics[3].toString());
        console.log("├── Verified Creators:", ipMetrics[4].toString());
        console.log("├── Liquidity Pools:", liquidityMetrics[0].toString());
        console.log("├── Total Liquidity:", ethers.formatEther(liquidityMetrics[1]));
        console.log("├── Total Rewards Distributed:", ethers.formatEther(liquidityMetrics[3]));
        console.log("├── Featured Pools:", liquidityMetrics[4].toString());
        console.log("├── Marketplace Listings:", marketplaceMetrics[0].toString());
        console.log("├── Total Sales:", marketplaceMetrics[1].toString());
        console.log("└── Total Volume:", ethers.formatEther(marketplaceMetrics[2]), "SLAW");
        
        console.log("\n👤 Deployer Creator Profile:");
        console.log("├── Display Name:", creatorProfile.displayName);
        console.log("├── Bio:", creatorProfile.bio);
        console.log("├── Verified:", creatorProfile.isVerified);
        console.log("├── Total Wrapped IPs:", creatorProfile.totalWrappedIPs.toString());
        console.log("├── Total Value Created:", ethers.formatEther(creatorProfile.totalValueCreated), "SLAW");
        console.log("└── Joined At:", new Date(Number(creatorProfile.joinedAt) * 1000).toLocaleString());

        console.log("\n💡 Creator Economy Examples:");
        console.log("\n1. Create Creator Profile:");
        console.log("await wrappedIPManager.createCreatorProfile('Artist Name', 'Bio', 'avatar_url');");
        
        console.log("\n2. Wrap NFT with Creator Branding:");
        console.log("const tokenAddress = await wrappedIPManager.wrapIP(");
        console.log("  nftContract, nftId, totalSupply, pricePerToken,");
        console.log("  'My Amazing Song', 'music', 'metadata'");
        console.log(");");
        console.log("// Creates: 'Artist Name's My Amazing Song' token (ARTMA)");
        
        console.log("\n3. Create Creator-Branded Liquidity Pool:");
        console.log("const pairAddress = await liquidityManager.createPool(");
        console.log("  wrappedTokenAddress, slawAmount, ipAmount");
        console.log(");");
        console.log("// Creates: 'Artist Name's My Amazing Song / SLAW LP' token");
        
        console.log("\n4. Earn Creator Bonuses:");
        console.log("// First pool bonus: 1% of initial liquidity");
        console.log("// Liquidity attraction bonus: 0.1% of attracted liquidity");
        console.log("// Trading volume bonuses for popular tokens");
        
        console.log("\n5. Track Creator Value:");
        console.log("const topCreators = await wrappedIPManager.getTopCreators(10);");
        console.log("const creatorPools = await liquidityManager.getCreatorPools(creatorAddress);");

        console.log("\n💡 Next Steps:");
        console.log("1. Run health check: npx hardhat run scripts/verify-pvm-deployment.js health --network", hre.network.name);
        console.log("2. Deploy test NFT: npx hardhat run scripts/deploy-test-nft.js --network", hre.network.name);
        console.log("3. Test creator workflow: npx hardhat run scripts/test-creator-workflow.js --network", hre.network.name);
        console.log("4. Run full integration test: npx hardhat run scripts/test-full-workflow.js --network", hre.network.name);
        
        return {
            success: true,
            addresses: contractAddresses,
            data: deploymentData,
            creatorProfile: creatorProfile
        };

    } catch (error) {
        console.error("❌ Deployment failed:", error);
        
        // Save error log
        const errorPath = path.join(__dirname, "../deployments", `deployment-error-${Date.now()}.json`);
        fs.writeFileSync(errorPath, JSON.stringify({
            error: error.message,
            stack: error.stack,
            network: hre.network.name,
            deployer: deployer.address,
            timestamp: new Date().toISOString()
        }, null, 2));
        
        throw error;
    }
}

// Handle both direct execution and module export
if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

module.exports = { main };
