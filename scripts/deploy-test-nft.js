const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🎨 Deploying Test Copyright NFT for PVM Testing...\n");
    
    const [deployer] = await ethers.getSigners();
    console.log("👤 Deploying with account:", deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(await deployer.provider.getBalance(deployer.address)), "ETH\n");

    try {
        // ===== Deploy TestCopyrightNFT =====
        console.log("📦 Deploying TestCopyrightNFT...");
        const TestCopyrightNFT = await ethers.getContractFactory("TestCopyrightNFT");
        
        const testNFT = await TestCopyrightNFT.deploy(deployer.address);
        await testNFT.waitForDeployment();
        
        const testNFTAddress = await testNFT.getAddress();
        console.log("✅ TestCopyrightNFT deployed to:", testNFTAddress);

        // ===== Mint Test NFTs =====
        console.log("\n🎨 Minting test NFTs...");
        
        // Mint test suite (4 different categories)
        const testSuite = await testNFT.mintTestSuite(deployer.address);
        await testSuite.wait();
        console.log("✅ Minted test suite (4 NFTs)");
        
        // Mint additional individual test NFTs
        const musicNFT = await testNFT.mintTestNFT(deployer.address, "music");
        await musicNFT.wait();
        console.log("✅ Minted music NFT");
        
        const artNFT = await testNFT.mintTestNFT(deployer.address, "art");
        await artNFT.wait();
        console.log("✅ Minted art NFT");
        
        // Get all tokens owned by deployer
        const ownedTokens = await testNFT.getTokensByOwner(deployer.address);
        console.log(`✅ Total NFTs minted: ${ownedTokens.length}`);

        // ===== Load Existing Deployment Data =====
        const addressPath = path.join(__dirname, "../deployments", `contract-addresses-${hre.network.name}.json`);
        let addresses = {};
        
        if (fs.existsSync(addressPath)) {
            addresses = JSON.parse(fs.readFileSync(addressPath, "utf8"));
            console.log("\n📋 Loaded existing contract addresses");
        } else {
            console.log("\n⚠️  No existing deployment found. Deploy main contracts first with:");
            console.log("npx hardhat run scripts/deploy-integration.js --network", hre.network.name);
        }

        // ===== Configure WrappedIPManager (if deployed) =====
        if (addresses.WrappedIPManager) {
            console.log("\n🔧 Configuring WrappedIPManager...");
            
            const WrappedIPManager = await ethers.getContractFactory("WrappedIPManager");
            const wrappedIPManager = WrappedIPManager.attach(addresses.WrappedIPManager);
            
            // Add TestCopyrightNFT as supported contract
            await wrappedIPManager.setSupportedNFTContract(testNFTAddress, true);
            console.log("✅ Added TestCopyrightNFT as supported contract in WrappedIPManager");
        }

        // ===== Configure MarketplaceCore (if deployed) =====
        if (addresses.MarketplaceCore) {
            console.log("\n🏪 Configuring MarketplaceCore...");
            
            const MarketplaceCore = await ethers.getContractFactory("MarketplaceCore");
            const marketplaceCore = MarketplaceCore.attach(addresses.MarketplaceCore);
            
            // Add TestCopyrightNFT as supported contract
            await marketplaceCore.setSupportedNFTContract(testNFTAddress, true);
            console.log("✅ Added TestCopyrightNFT as supported contract in MarketplaceCore");
        }

        // ===== Save Test NFT Data =====
        console.log("\n💾 Saving test NFT data...");
        
        const deploymentsDir = path.join(__dirname, "../deployments");
        if (!fs.existsSync(deploymentsDir)) {
            fs.mkdirSync(deploymentsDir, { recursive: true });
        }
        
        // Update contract addresses
        addresses.TestCopyrightNFT = testNFTAddress;
        const addressPath2 = path.join(deploymentsDir, `contract-addresses-${hre.network.name}.json`);
        fs.writeFileSync(addressPath2, JSON.stringify(addresses, null, 2));
        
        // Save test NFT deployment data
        const testNFTData = {
            network: hre.network.name,
            deployer: deployer.address,
            timestamp: new Date().toISOString(),
            address: testNFTAddress,
            ownedTokens: ownedTokens.map(id => id.toString()),
            totalSupply: (await testNFT.totalSupply()).toString()
        };
        
        const testDataPath = path.join(deploymentsDir, `test-nft-${hre.network.name}.json`);
        fs.writeFileSync(testDataPath, JSON.stringify(testNFTData, null, 2));
        
        // Save ABI
        const artifact = await hre.artifacts.readArtifact("TestCopyrightNFT");
        const abiPath = path.join(deploymentsDir, "TestCopyrightNFT-abi.json");
        fs.writeFileSync(abiPath, JSON.stringify(artifact.abi, null, 2));
        
        console.log("✅ Test NFT data saved");

        // ===== Display Token Information =====
        console.log("\n📋 === TEST NFT SUMMARY ===");
        console.log("Contract Address:", testNFTAddress);
        console.log("Total Supply:", await testNFT.totalSupply());
        console.log("Owner:", deployer.address);
        console.log("Owned Tokens:", ownedTokens.map(id => id.toString()).join(", "));
        
        console.log("\n🎨 Token Details:");
        for (let i = 0; i < ownedTokens.length; i++) {
            const tokenId = ownedTokens[i];
            const info = await testNFT.getCopyrightInfo(tokenId);
            const uri = await testNFT.tokenURI(tokenId);
            
            console.log(`\nToken ID ${tokenId}:`);
            console.log(`  Title: ${info.title}`);
            console.log(`  Category: ${info.category}`);
            console.log(`  Description: ${info.description}`);
            console.log(`  URI: ${uri}`);
            console.log(`  Registered: ${info.isRegistered}`);
        }

        // ===== Integration Examples =====
        if (addresses.WrappedIPManager && addresses.SLAWToken) {
            console.log("\n🔗 === INTEGRATION EXAMPLES ===");
            console.log("\n1. Wrap NFT to tokens:");
            console.log("const ipId = await wrappedIPManager.getIPId(testNFTAddress, tokenId);");
            console.log("await testNFT.approve(wrappedIPManagerAddress, tokenId);");
            console.log("await wrappedIPManager.wrapIP(testNFTAddress, tokenId, totalSupply, pricePerToken, name, symbol, metadata);");
            
            console.log("\n2. Create liquidity pool:");
            console.log("await wrappedIPToken.approve(liquidityManagerAddress, ipAmount);");
            console.log("await slawToken.approve(liquidityManagerAddress, slawAmount);");
            console.log("await liquidityManager.createPool(wrappedIPTokenAddress, slawAmount, ipAmount);");
            
            console.log("\n3. List on marketplace:");
            console.log("await testNFT.approve(marketplaceCoreAddress, tokenId);");
            console.log("await marketplaceCore.createNFTListing(testNFTAddress, tokenId, price, duration, allowOffers);");
        }

        console.log("\n🎉 ========================================");
        console.log("🎉 TEST COPYRIGHT NFT DEPLOYMENT COMPLETE!");
        console.log("🎉 ========================================\n");
        
        console.log("💡 Next Steps:");
        console.log("1. Run full workflow test:");
        console.log("   npx hardhat run scripts/test-full-workflow.js --network", hre.network.name);
        console.log("2. Test NFT wrapping:");
        console.log("   npx hardhat run scripts/test-ip-wrapping.js --network", hre.network.name);
        console.log("3. Test marketplace functionality:");
        console.log("   npx hardhat run scripts/test-marketplace.js --network", hre.network.name);
        
        return {
            success: true,
            address: testNFTAddress,
            ownedTokens: ownedTokens.map(id => id.toString()),
            totalSupply: (await testNFT.totalSupply()).toString()
        };

    } catch (error) {
        console.error("❌ Test NFT deployment failed:", error);
        
        // Save error log
        const errorPath = path.join(__dirname, "../deployments", `test-nft-error-${Date.now()}.json`);
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
