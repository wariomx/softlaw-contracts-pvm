const { ethers } = require("hardhat");

/**
 * Deployment script for complete Softlaw ecosystem
 * Deploys Treasury, Wrapped IP Factory, and configures the entire system
 */
async function main() {
    console.log("🚀 Starting Softlaw Ecosystem Deployment...\n");

    const [deployer] = await ethers.getSigners();
    console.log("🔐 Deploying contracts with the account:", deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)));

    // ===== 1. Deploy Uniswap V2 Factory (for liquidity pools) =====
    console.log("\n📦 Deploying Uniswap V2 Factory...");
    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    const liquidityFactory = await UniswapV2Factory.deploy(deployer.address);
    await liquidityFactory.waitForDeployment();
    console.log("✅ UniswapV2Factory deployed to:", await liquidityFactory.getAddress());

    // ===== 2. Deploy Softlaw Treasury =====
    console.log("\n📦 Deploying Softlaw Treasury...");
    const SoftlawTreasury = await ethers.getContractFactory("SoftlawTreasury");
    const treasury = await SoftlawTreasury.deploy(
        deployer.address, // admin
        await liquidityFactory.getAddress(), // liquidity factory
        deployer.address  // fee collector
    );
    await treasury.waitForDeployment();
    console.log("✅ SoftlawTreasury deployed to:", await treasury.getAddress());

    // ===== 3. Deploy Wrapped IP Factory =====
    console.log("\n📦 Deploying Wrapped IP Factory...");
    const WrappedIPFactory = await ethers.getContractFactory("WrappedIPFactory");
    const wrappedIPFactory = await WrappedIPFactory.deploy(
        await treasury.getAddress(), // treasury
        deployer.address  // owner
    );
    await wrappedIPFactory.waitForDeployment();
    console.log("✅ WrappedIPFactory deployed to:", await wrappedIPFactory.getAddress());

    // ===== 4. Deploy existing contracts =====
    console.log("\n📦 Deploying existing Softlaw contracts...");

    // Deploy Copyright Registry
    const CopyrightsRegistry = await ethers.getContractFactory("CopyrightsRegistry");
    const copyrightsRegistry = await CopyrightsRegistry.deploy(deployer.address);
    await copyrightsRegistry.waitForDeployment();
    console.log("✅ CopyrightsRegistry deployed to:", await copyrightsRegistry.getAddress());

    // Deploy Copyright Licensing
    const CopyrightLicensing = await ethers.getContractFactory("CopyrightLicensing");
    const copyrightLicensing = await CopyrightLicensing.deploy(deployer.address);
    await copyrightLicensing.waitForDeployment();
    console.log("✅ CopyrightLicensing deployed to:", await copyrightLicensing.getAddress());

    // Deploy DAO Governor
    const DAOGovernor = await ethers.getContractFactory("DAOGovernor");
    const daoGovernor = await DAOGovernor.deploy();
    await daoGovernor.waitForDeployment();
    console.log("✅ DAOGovernor deployed to:", await daoGovernor.getAddress());

    // Deploy DAO Membership
    const DAOMembership = await ethers.getContractFactory("DAOMembership");
    const daoMembership = await DAOMembership.deploy();
    await daoMembership.waitForDeployment();
    console.log("✅ DAOMembership deployed to:", await daoMembership.getAddress());

    // ===== 5. Configure system permissions =====
    console.log("\n🔧 Configuring system permissions...");

    // Grant roles to registry contract
    const REGISTRY_ROLE = await treasury.REGISTRY_CONTRACT();
    await treasury.grantRole(REGISTRY_ROLE, await copyrightsRegistry.getAddress());
    console.log("✅ Registry contract role granted");

    // Grant roles to licensing contract
    const LICENSING_ROLE = await treasury.LICENSING_CONTRACT();
    await treasury.grantRole(LICENSING_ROLE, await copyrightLicensing.getAddress());
    console.log("✅ Licensing contract role granted");

    // Grant liquidity manager role to deployer (can be changed later)
    const LIQUIDITY_ROLE = await treasury.LIQUIDITY_MANAGER();
    await treasury.grantRole(LIQUIDITY_ROLE, deployer.address);
    console.log("✅ Liquidity manager role granted");

    // ===== 6. Get system info =====
    console.log("\n📊 System Information:");
    const treasuryBalance = await treasury.getTreasuryBalance();
    const systemMetrics = await treasury.getSystemMetrics();
    
    console.log("💰 Treasury SLAW Balance:", ethers.formatEther(treasuryBalance));
    console.log("📈 System Metrics:");
    console.log("   - Treasury Balance:", ethers.formatEther(systemMetrics[0]));
    console.log("   - Total Wrapped IPs:", systemMetrics[1].toString());
    console.log("   - Total Liquidity Pools:", systemMetrics[2].toString());
    console.log("   - Total Fees Collected:", ethers.formatEther(systemMetrics[3]));
    console.log("   - Reward Pool:", ethers.formatEther(systemMetrics[4]));

    // ===== 7. Save deployment info =====
    const deploymentInfo = {
        network: "local", // Update based on network
        timestamp: new Date().toISOString(),
        deployer: deployer.address,
        contracts: {
            UniswapV2Factory: await liquidityFactory.getAddress(),
            SoftlawTreasury: await treasury.getAddress(),
            WrappedIPFactory: await wrappedIPFactory.getAddress(),
            CopyrightsRegistry: await copyrightsRegistry.getAddress(),
            CopyrightLicensing: await copyrightLicensing.getAddress(),
            DAOGovernor: await daoGovernor.getAddress(),
            DAOMembership: await daoMembership.getAddress()
        },
        configuration: {
            treasuryAdmin: deployer.address,
            feeCollector: deployer.address,
            registrationFee: "100", // SLAW
            licenseBaseFee: "50"     // SLAW
        }
    };

    console.log("\n💾 Deployment completed successfully!");
    console.log("📋 Deployment Summary:");
    console.log(JSON.stringify(deploymentInfo, null, 2));

    // ===== 8. Example usage demonstration =====
    console.log("\n🎯 Example Usage Flow:");
    console.log("1. Register IP: Call copyrightsRegistry.registerCopyright()");
    console.log("2. Wrap IP: Call treasury.wrapCopyrightNFT()");
    console.log("3. Create Pool: Call treasury.createLiquidityPool()");
    console.log("4. Trade: Use Uniswap V2 interface with pair address");
    console.log("5. Rewards: Call treasury.distributeRewards()");

    return deploymentInfo;
}

// Example function to demonstrate the complete flow
async function demonstrateFlow() {
    console.log("\n🎬 Demonstrating complete IP → Liquidity flow...");
    
    // This would be called after deployment
    // const treasury = await ethers.getContractAt("SoftlawTreasury", TREASURY_ADDRESS);
    // const factory = await ethers.getContractAt("WrappedIPFactory", FACTORY_ADDRESS);
    
    // 1. User registers IP (mock)
    console.log("1. 📄 User registers copyright NFT");
    
    // 2. User wraps IP into tokens
    console.log("2. 🎁 User wraps NFT into 1000 IP tokens");
    
    // 3. User creates liquidity pool
    console.log("3. 🏊 User creates liquidity pool: 500 IP tokens + 1000 SLAW");
    
    // 4. Other users can now trade
    console.log("4. 📈 Pool active - users can trade IP tokens for SLAW");
    
    // 5. Liquidity providers earn rewards
    console.log("5. 🎁 Liquidity providers earn SLAW rewards");
    
    console.log("✅ Flow demonstration complete!");
}

if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error("❌ Deployment failed:", error);
            process.exit(1);
        });
}

module.exports = { main, demonstrateFlow };
