const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🚀 Starting Softlaw PVM Integration Deployment...\n");
    
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
        console.log("📦 1/5 Deploying SLAWToken...");
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
        console.log("\n📦 2/5 Deploying TreasuryCore...");
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
        console.log("\n🔧 3/5 Updating SLAWToken with TreasuryCore...");
        await slawToken.updateTreasuryCore(treasuryCoreAddress);
        console.log("✅ SLAWToken treasury updated");
        
        deploymentData.contracts.SLAWToken.treasuryCore = treasuryCoreAddress;

        // ===== STEP 4: Deploy Wrapped IP Manager =====
        console.log("\n📦 4/5 Deploying WrappedIPManager...");
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

        // ===== STEP 5: Deploy Liquidity Manager =====
        console.log("\n📦 5/5 Deploying LiquidityManager...");
        const LiquidityManager = await ethers.getContractFactory("LiquidityManager");
        
        const liquidityManager = await LiquidityManager.deploy(
            deployer.address, // admin
            slawAddress, // SLAW token
            treasuryCoreAddress // treasury core
        );
        await liquidityManager.waitForDeployment();
        
        const liquidityManagerAddress = await liquidityManager.getAddress();
        console.log("✅ LiquidityManager deployed to:", liquidityManagerAddress);
        
        deploymentData.contracts.LiquidityManager = {
            address: liquidityManagerAddress,
            admin: deployer.address,
            slawToken: slawAddress,
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
        console.log("\n🔧 Configuring RBAC...");
        
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

        // ===== STEP 8: Initial SLAW Distribution =====
        console.log("\n💰 Initial SLAW distribution...");
        
        // Transfer 1M SLAW to deployer for testing
        const testAmount = ethers.parseEther("1000000"); // 1M SLAW
        await slawToken.treasuryTransfer(deployer.address, testAmount);
        console.log("✅ Transferred 1M SLAW to deployer for testing");
        
        // ===== STEP 9: Save Deployment Data =====
        console.log("\n💾 Saving deployment data...");
        
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
        
        console.log("✅ Deployment data saved to:", deploymentPath);
        console.log("✅ Contract addresses saved to:", addressPath);
        console.log("✅ ABIs saved to deployments directory");

        // ===== DEPLOYMENT SUMMARY =====
        console.log("\n🎉 ========================================");
        console.log("🎉 SOFTLAW PVM INTEGRATION DEPLOYMENT COMPLETE!");
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
        console.log("├── SLAW Total Supply:", ethers.formatEther(await slawToken.totalSupply()));
        console.log("└── Network:", hre.network.name);
        
        console.log("\n💡 Next Steps:");
        console.log("1. Run health check: npx hardhat run scripts/verify-pvm-deployment.js --network", hre.network.name);
        console.log("2. Run integration tests: npx hardhat test test/integration/ --network", hre.network.name);
        console.log("3. Deploy test NFT contract: npx hardhat run scripts/deploy-test-nft.js --network", hre.network.name);
        console.log("4. Configure supported contracts in managers");
        
        return {
            success: true,
            addresses: contractAddresses,
            data: deploymentData
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
