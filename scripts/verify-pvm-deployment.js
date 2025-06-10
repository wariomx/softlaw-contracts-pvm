const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    const command = process.argv[2] || "health";
    const args = process.argv.slice(3);
    
    console.log("🔍 Softlaw PVM Deployment Verification\n");
    
    try {
        const [signer] = await ethers.getSigners();
        console.log("👤 Using account:", signer.address);
        console.log("🌐 Network:", hre.network.name);
        console.log("💰 Balance:", ethers.formatEther(await signer.provider.getBalance(signer.address)), "ETH\n");
        
        // Load contract addresses
        const addressPath = path.join(__dirname, "../deployments", `contract-addresses-${hre.network.name}.json`);
        if (!fs.existsSync(addressPath)) {
            throw new Error(`❌ Contract addresses not found for network: ${hre.network.name}`);
        }
        
        const addresses = JSON.parse(fs.readFileSync(addressPath, "utf8"));
        console.log("📋 Loaded contract addresses:", Object.keys(addresses).join(", "));
        
        switch (command) {
            case "health":
                await healthCheck(addresses, signer);
                break;
            case "verify":
                await verifyDeployment(addresses, signer);
                break;
            case "monitor":
                const duration = parseInt(args[0]) || 10;
                await monitorSystem(addresses, signer, duration);
                break;
            default:
                console.log("❓ Available commands:");
                console.log("  health  - Basic health check");
                console.log("  verify  - Full verification");
                console.log("  monitor [minutes] - Monitor system");
        }
        
    } catch (error) {
        console.error("❌ Error:", error.message);
        process.exit(1);
    }
}

async function healthCheck(addresses, signer) {
    console.log("🏥 === HEALTH CHECK ===\n");
    
    let allHealthy = true;
    const results = {};
    
    // Check each contract
    for (const [name, address] of Object.entries(addresses)) {
        try {
            console.log(`🔍 Checking ${name}...`);
            
            const contract = await ethers.getContractAt(name, address);
            
            // Basic deployment check
            const code = await signer.provider.getCode(address);
            if (code === "0x") {
                throw new Error("No contract code found");
            }
            
            // Contract-specific checks
            let status = "HEALTHY";
            const checks = {};
            
            if (name === "SLAWToken") {
                checks.totalSupply = await contract.totalSupply();
                checks.name = await contract.name();
                checks.symbol = await contract.symbol();
                checks.decimals = await contract.decimals();
                checks.treasuryCore = await contract.treasuryCore();
            } else if (name === "TreasuryCore") {
                checks.slawToken = await contract.slawToken();
                checks.feeCollector = await contract.feeCollector();
                const metrics = await contract.getSystemMetrics();
                checks.feesCollected = metrics[0];
                checks.registrations = metrics[1];
                checks.licenses = metrics[2];
                checks.treasuryBalance = metrics[3];
            } else if (name === "WrappedIPManager") {
                checks.slawToken = await contract.slawToken();
                checks.treasuryCore = await contract.treasuryCore();
                const metrics = await contract.getSystemMetrics();
                checks.totalWrapped = metrics[0];
                checks.totalTokens = metrics[1];
            } else if (name === "LiquidityManager") {
                checks.slawToken = await contract.slawToken();
                checks.treasuryCore = await contract.treasuryCore();
                const metrics = await contract.getSystemMetrics();
                checks.totalPools = metrics[0];
                checks.totalLiquidity = metrics[1];
            } else if (name === "MarketplaceCore") {
                checks.slawToken = await contract.slawToken();
                checks.treasuryCore = await contract.treasuryCore();
                const metrics = await contract.getSystemMetrics();
                checks.totalListings = metrics[0];
                checks.totalSales = metrics[1];
                checks.totalVolume = metrics[2];
            }
            
            results[name] = { status, address, checks };
            console.log(`✅ ${name}: ${status}`);
            
        } catch (error) {
            console.log(`❌ ${name}: ERROR - ${error.message}`);
            results[name] = { status: "ERROR", address, error: error.message };
            allHealthy = false;
        }
    }
    
    console.log("\n📊 === HEALTH SUMMARY ===");
    console.log(`Overall Status: ${allHealthy ? "🟢 HEALTHY" : "🔴 UNHEALTHY"}`);
    console.log("Contract Details:");
    
    for (const [name, result] of Object.entries(results)) {
        console.log(`\n${name} (${result.address}):`);
        console.log(`  Status: ${result.status}`);
        
        if (result.checks) {
            for (const [key, value] of Object.entries(result.checks)) {
                if (typeof value === "bigint") {
                    console.log(`  ${key}: ${ethers.formatEther(value)} (if token amount)`);
                } else {
                    console.log(`  ${key}: ${value}`);
                }
            }
        }
        
        if (result.error) {
            console.log(`  Error: ${result.error}`);
        }
    }
    
    return allHealthy;
}

async function verifyDeployment(addresses, signer) {
    console.log("🔍 === FULL VERIFICATION ===\n");
    
    // First run health check
    const isHealthy = await healthCheck(addresses, signer);
    if (!isHealthy) {
        console.log("❌ Health check failed, stopping verification");
        return;
    }
    
    console.log("\n🔗 === INTEGRATION VERIFICATION ===\n");
    
    // Get contract instances
    const slawToken = await ethers.getContractAt("SLAWToken", addresses.SLAWToken);
    const treasuryCore = await ethers.getContractAt("TreasuryCore", addresses.TreasuryCore);
    const wrappedIPManager = await ethers.getContractAt("WrappedIPManager", addresses.WrappedIPManager);
    const liquidityManager = await ethers.getContractAt("LiquidityManager", addresses.LiquidityManager);
    const marketplaceCore = await ethers.getContractAt("MarketplaceCore", addresses.MarketplaceCore);
    
    try {
        // Verify SLAW Token integration
        console.log("🔍 Verifying SLAW Token integration...");
        const treasuryFromSLAW = await slawToken.treasuryCore();
        const slawFromTreasury = await treasuryCore.slawToken();
        
        if (treasuryFromSLAW !== addresses.TreasuryCore) {
            throw new Error("SLAW Token treasury core mismatch");
        }
        if (slawFromTreasury !== addresses.SLAWToken) {
            throw new Error("Treasury Core SLAW token mismatch");
        }
        console.log("✅ SLAW Token ↔ Treasury Core integration verified");
        
        // Verify WrappedIPManager integration
        console.log("🔍 Verifying WrappedIPManager integration...");
        const slawFromIPManager = await wrappedIPManager.slawToken();
        const treasuryFromIPManager = await wrappedIPManager.treasuryCore();
        
        if (slawFromIPManager !== addresses.SLAWToken) {
            throw new Error("WrappedIPManager SLAW token mismatch");
        }
        if (treasuryFromIPManager !== addresses.TreasuryCore) {
            throw new Error("WrappedIPManager treasury core mismatch");
        }
        console.log("✅ WrappedIPManager integration verified");
        
        // Verify LiquidityManager integration
        console.log("🔍 Verifying LiquidityManager integration...");
        const slawFromLiquidityManager = await liquidityManager.slawToken();
        const treasuryFromLiquidityManager = await liquidityManager.treasuryCore();
        
        if (slawFromLiquidityManager !== addresses.SLAWToken) {
            throw new Error("LiquidityManager SLAW token mismatch");
        }
        if (treasuryFromLiquidityManager !== addresses.TreasuryCore) {
            throw new Error("LiquidityManager treasury core mismatch");
        }
        console.log("✅ LiquidityManager integration verified");
        
        // Verify MarketplaceCore integration
        console.log("🔍 Verifying MarketplaceCore integration...");
        const slawFromMarketplace = await marketplaceCore.slawToken();
        const treasuryFromMarketplace = await marketplaceCore.treasuryCore();
        
        if (slawFromMarketplace !== addresses.SLAWToken) {
            throw new Error("MarketplaceCore SLAW token mismatch");
        }
        if (treasuryFromMarketplace !== addresses.TreasuryCore) {
            throw new Error("MarketplaceCore treasury core mismatch");
        }
        console.log("✅ MarketplaceCore integration verified");
        
        // Verify role-based access control
        console.log("🔍 Verifying RBAC...");
        const MARKETPLACE_CONTRACT = ethers.keccak256(ethers.toUtf8Bytes("MARKETPLACE_CONTRACT"));
        const hasMarketplaceRole = await treasuryCore.hasRole(MARKETPLACE_CONTRACT, addresses.MarketplaceCore);
        
        if (!hasMarketplaceRole) {
            console.log("⚠️  MarketplaceCore missing MARKETPLACE_CONTRACT role in TreasuryCore");
        } else {
            console.log("✅ RBAC verified");
        }
        
        console.log("\n🎉 === VERIFICATION COMPLETE ===");
        console.log("✅ All integrations verified successfully!");
        
        // Display system summary
        console.log("\n📊 === SYSTEM SUMMARY ===");
        const slawTotalSupply = await slawToken.totalSupply();
        const slawTreasuryBalance = await slawToken.getTreasuryBalance();
        const slawCirculating = await slawToken.getCirculatingSupply();
        
        console.log(`SLAW Total Supply: ${ethers.formatEther(slawTotalSupply)}`);
        console.log(`SLAW Treasury Balance: ${ethers.formatEther(slawTreasuryBalance)}`);
        console.log(`SLAW Circulating: ${ethers.formatEther(slawCirculating)}`);
        
        const treasuryMetrics = await treasuryCore.getSystemMetrics();
        console.log(`Total Fees Collected: ${ethers.formatEther(treasuryMetrics[0])}`);
        console.log(`Total Registrations: ${treasuryMetrics[1]}`);
        console.log(`Total Licenses: ${treasuryMetrics[2]}`);
        
        const ipMetrics = await wrappedIPManager.getSystemMetrics();
        console.log(`Total Wrapped IPs: ${ipMetrics[0]}`);
        console.log(`Total IP Tokens: ${ethers.formatEther(ipMetrics[1])}`);
        
        const liquidityMetrics = await liquidityManager.getSystemMetrics();
        console.log(`Total Liquidity Pools: ${liquidityMetrics[0]}`);
        console.log(`Total Liquidity: ${ethers.formatEther(liquidityMetrics[1])}`);
        
        const marketplaceMetrics = await marketplaceCore.getSystemMetrics();
        console.log(`Total Marketplace Listings: ${marketplaceMetrics[0]}`);
        console.log(`Total Sales: ${marketplaceMetrics[1]}`);
        console.log(`Total Volume: ${ethers.formatEther(marketplaceMetrics[2])}`);
        
    } catch (error) {
        console.error("❌ Verification failed:", error.message);
        throw error;
    }
}

async function monitorSystem(addresses, signer, durationMinutes) {
    console.log(`📊 === MONITORING SYSTEM FOR ${durationMinutes} MINUTES ===\n`);
    
    const endTime = Date.now() + (durationMinutes * 60 * 1000);
    let iteration = 0;
    
    while (Date.now() < endTime) {
        iteration++;
        console.log(`\n🔄 Monitor Iteration ${iteration} - ${new Date().toLocaleTimeString()}`);
        
        try {
            const isHealthy = await healthCheck(addresses, signer);
            
            if (!isHealthy) {
                console.log("🚨 ALERT: System unhealthy detected!");
                // Here you could add notification logic
            }
            
            console.log("⏰ Waiting 30 seconds before next check...");
            await new Promise(resolve => setTimeout(resolve, 30000));
            
        } catch (error) {
            console.error("❌ Monitor error:", error.message);
            await new Promise(resolve => setTimeout(resolve, 10000));
        }
    }
    
    console.log("\n✅ Monitoring completed");
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

module.exports = { main, healthCheck, verifyDeployment };
