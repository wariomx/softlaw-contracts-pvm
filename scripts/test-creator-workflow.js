const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🎨 Testing Softlaw Creator Economy Workflow...\n");
    
    const [deployer, alice, bob, charlie] = await ethers.getSigners();
    console.log("👤 Deployer:", deployer.address);
    console.log("👤 Alice (Creator):", alice.address);
    console.log("👤 Bob (Creator):", bob.address);
    console.log("👤 Charlie (Investor):", charlie.address);
    console.log("🌐 Network:", hre.network.name, "\n");

    try {
        // ===== Load Contract Addresses =====
        const addressPath = path.join(__dirname, "../deployments", `contract-addresses-${hre.network.name}.json`);
        if (!fs.existsSync(addressPath)) {
            throw new Error("❌ Contract addresses not found. Run deploy-integration.js first");
        }
        
        const addresses = JSON.parse(fs.readFileSync(addressPath, "utf8"));
        console.log("📋 Loaded contract addresses\n");
        
        // ===== Get Contract Instances =====
        const slawToken = await ethers.getContractAt("SLAWToken", addresses.SLAWToken);
        const treasuryCore = await ethers.getContractAt("TreasuryCore", addresses.TreasuryCore);
        const wrappedIPManager = await ethers.getContractAt("WrappedIPManager", addresses.WrappedIPManager);
        const liquidityManager = await ethers.getContractAt("LiquidityManager", addresses.LiquidityManager);
        const marketplaceCore = await ethers.getContractAt("MarketplaceCore", addresses.MarketplaceCore);
        
        // Deploy test NFT if not exists
        let testNFT;
        if (addresses.TestCopyrightNFT) {
            testNFT = await ethers.getContractAt("TestCopyrightNFT", addresses.TestCopyrightNFT);
        } else {
            console.log("⚠️  TestCopyrightNFT not found. Deploying...");
            const TestCopyrightNFT = await ethers.getContractFactory("TestCopyrightNFT");
            testNFT = await TestCopyrightNFT.deploy(deployer.address);
            await testNFT.waitForDeployment();
            
            // Configure as supported contract
            await wrappedIPManager.setSupportedNFTContract(await testNFT.getAddress(), true);
            await marketplaceCore.setSupportedNFTContract(await testNFT.getAddress(), true);
            console.log("✅ TestCopyrightNFT deployed and configured");
        }

        // ===== STEP 1: Initial SLAW Distribution =====
        console.log("💰 === STEP 1: SLAW Distribution ===");
        
        const transferAmount = ethers.parseEther("50000"); // 50K SLAW each
        
        // Transfer SLAW to users
        await slawToken.transfer(alice.address, transferAmount);
        await slawToken.transfer(bob.address, transferAmount);
        await slawToken.transfer(charlie.address, transferAmount);
        
        console.log(`✅ Distributed ${ethers.formatEther(transferAmount)} SLAW to each user`);
        
        const aliceBalance = await slawToken.balanceOf(alice.address);
        const bobBalance = await slawToken.balanceOf(bob.address);
        const charlieBalance = await slawToken.balanceOf(charlie.address);
        
        console.log(`💰 Alice Balance: ${ethers.formatEther(aliceBalance)} SLAW`);
        console.log(`💰 Bob Balance: ${ethers.formatEther(bobBalance)} SLAW`);
        console.log(`💰 Charlie Balance: ${ethers.formatEther(charlieBalance)} SLAW\n`);

        // ===== STEP 2: Create Creator Profiles =====
        console.log("👨‍🎨 === STEP 2: Create Creator Profiles ===");
        
        // Alice creates profile as a musician
        await wrappedIPManager.connect(alice).createCreatorProfile(
            "Alice Melody",
            "Independent musician specializing in electronic and ambient music. Creating unique soundscapes for the digital age.",
            "https://avatars.example.com/alice-melody"
        );
        console.log("✅ Alice created musician profile: 'Alice Melody'");
        
        // Bob creates profile as a digital artist
        await wrappedIPManager.connect(bob).createCreatorProfile(
            "Bob Pixelworks",
            "Digital artist and NFT creator. Exploring the intersection of technology and traditional art forms.",
            "https://avatars.example.com/bob-pixelworks"
        );
        console.log("✅ Bob created artist profile: 'Bob Pixelworks'");
        
        // Verify creators (admin action)
        await wrappedIPManager.verifyCreator(alice.address, true);
        await wrappedIPManager.verifyCreator(bob.address, true);
        console.log("✅ Verified both creators as official");
        
        // Display creator profiles
        const aliceProfile = await wrappedIPManager.getCreatorProfile(alice.address);
        const bobProfile = await wrappedIPManager.getCreatorProfile(bob.address);
        
        console.log("\n👤 Creator Profiles:");
        console.log(`Alice: ${aliceProfile.displayName} (Verified: ${aliceProfile.isVerified})`);
        console.log(`  Bio: ${aliceProfile.bio}`);
        console.log(`Bob: ${bobProfile.displayName} (Verified: ${bobProfile.isVerified})`);
        console.log(`  Bio: ${bobProfile.bio}\n`);

        // ===== STEP 3: Mint NFTs and Create Personalized Tokens =====
        console.log("🎵 === STEP 3: Create Personalized IP Tokens ===");
        
        // Alice mints a music NFT
        const aliceMintTx = await testNFT.connect(alice).mintCopyright(
            alice.address,
            "Ethereal Dreams",
            "A mesmerizing ambient track that transports listeners to another dimension",
            "music",
            "https://metadata.example.com/ethereal-dreams"
        );
        const aliceReceipt = await aliceMintTx.wait();
        const aliceNFTEvent = aliceReceipt.logs.find(log => {
            try {
                return testNFT.interface.parseLog(log).name === "CopyrightMinted";
            } catch {
                return false;
            }
        });
        const aliceTokenId = testNFT.interface.parseLog(aliceNFTEvent).args.tokenId;
        console.log(`🎵 Alice minted music NFT: "Ethereal Dreams" (Token ID: ${aliceTokenId})`);
        
        // Bob mints a digital art NFT
        const bobMintTx = await testNFT.connect(bob).mintCopyright(
            bob.address,
            "Cyber Phoenix",
            "A stunning digital artwork depicting a phoenix rising in cyberspace",
            "art",
            "https://metadata.example.com/cyber-phoenix"
        );
        const bobReceipt = await bobMintTx.wait();
        const bobNFTEvent = bobReceipt.logs.find(log => {
            try {
                return testNFT.interface.parseLog(log).name === "CopyrightMinted";
            } catch {
                return false;
            }
        });
        const bobTokenId = testNFT.interface.parseLog(bobNFTEvent).args.tokenId;
        console.log(`🎨 Bob minted art NFT: "Cyber Phoenix" (Token ID: ${bobTokenId})`);
        
        // Alice wraps her music NFT
        await testNFT.connect(alice).approve(addresses.WrappedIPManager, aliceTokenId);
        const aliceWrapTx = await wrappedIPManager.connect(alice).wrapIP(
            addresses.TestCopyrightNFT,
            aliceTokenId,
            ethers.parseEther("10000"), // 10,000 tokens
            ethers.parseEther("5"), // 5 SLAW per token
            "Ethereal Dreams",
            "music",
            "Fractionalized ownership of the ambient masterpiece Ethereal Dreams"
        );
        const aliceWrapReceipt = await aliceWrapTx.wait();
        const aliceWrapEvent = aliceWrapReceipt.logs.find(log => {
            try {
                return wrappedIPManager.interface.parseLog(log).name === "IPWrapped";
            } catch {
                return false;
            }
        });
        const aliceWrappedTokenAddress = wrappedIPManager.interface.parseLog(aliceWrapEvent).args.tokenAddress;
        
        console.log(`✅ Alice wrapped NFT into personalized token`);
        console.log(`🪙 Token Name: "Alice Melody's Ethereal Dreams"`);
        console.log(`🔗 Token Address: ${aliceWrappedTokenAddress}`);
        
        // Bob wraps his art NFT
        await testNFT.connect(bob).approve(addresses.WrappedIPManager, bobTokenId);
        const bobWrapTx = await wrappedIPManager.connect(bob).wrapIP(
            addresses.TestCopyrightNFT,
            bobTokenId,
            ethers.parseEther("5000"), // 5,000 tokens
            ethers.parseEther("8"), // 8 SLAW per token
            "Cyber Phoenix",
            "art",
            "Fractionalized ownership of the digital artwork Cyber Phoenix"
        );
        const bobWrapReceipt = await bobWrapTx.wait();
        const bobWrapEvent = bobWrapReceipt.logs.find(log => {
            try {
                return wrappedIPManager.interface.parseLog(log).name === "IPWrapped";
            } catch {
                return false;
            }
        });
        const bobWrappedTokenAddress = wrappedIPManager.interface.parseLog(bobWrapEvent).args.tokenAddress;
        
        console.log(`✅ Bob wrapped NFT into personalized token`);
        console.log(`🪙 Token Name: "Bob Pixelworks's Cyber Phoenix"`);
        console.log(`🔗 Token Address: ${bobWrappedTokenAddress}`);
        
        // Get token details
        const aliceWrappedToken = await ethers.getContractAt("PersonalizedWrappedIPToken", aliceWrappedTokenAddress);
        const bobWrappedToken = await ethers.getContractAt("PersonalizedWrappedIPToken", bobWrappedTokenAddress);
        
        const aliceTokenName = await aliceWrappedToken.name();
        const aliceTokenSymbol = await aliceWrappedToken.symbol();
        const bobTokenName = await bobWrappedToken.name();
        const bobTokenSymbol = await bobWrappedToken.symbol();
        
        console.log(`🎵 Alice's Token: ${aliceTokenName} (${aliceTokenSymbol})`);
        console.log(`🎨 Bob's Token: ${bobTokenName} (${bobTokenSymbol})\n`);

        // ===== STEP 4: Create Creator-Branded Liquidity Pools =====
        console.log("🌊 === STEP 4: Create Creator-Branded Liquidity Pools ===");
        
        // Alice creates liquidity pool for her music token
        const aliceSLAWAmount = ethers.parseEther("25000"); // 25K SLAW
        const aliceTokenAmount = ethers.parseEther("5000"); // 5K music tokens
        
        await slawToken.connect(alice).approve(addresses.LiquidityManager, aliceSLAWAmount);
        await aliceWrappedToken.connect(alice).approve(addresses.LiquidityManager, aliceTokenAmount);
        
        const alicePoolTx = await liquidityManager.connect(alice).createPool(
            aliceWrappedTokenAddress,
            aliceSLAWAmount,
            aliceTokenAmount
        );
        const alicePoolReceipt = await alicePoolTx.wait();
        const alicePoolEvent = alicePoolReceipt.logs.find(log => {
            try {
                return liquidityManager.interface.parseLog(log).name === "PoolCreated";
            } catch {
                return false;
            }
        });
        const alicePairAddress = liquidityManager.interface.parseLog(alicePoolEvent).args.pairAddress;
        
        console.log(`✅ Alice created music liquidity pool`);
        console.log(`🌊 Pool Name: "Alice Melody's Ethereal Dreams / SLAW LP"`);
        console.log(`🔗 Pair Address: ${alicePairAddress}`);
        console.log(`💧 SLAW Added: ${ethers.formatEther(aliceSLAWAmount)}`);
        console.log(`🎵 Music Tokens Added: ${ethers.formatEther(aliceTokenAmount)}`);
        
        // Bob creates liquidity pool for his art token
        const bobSLAWAmount = ethers.parseEther("20000"); // 20K SLAW
        const bobTokenAmount = ethers.parseEther("2500"); // 2.5K art tokens
        
        await slawToken.connect(bob).approve(addresses.LiquidityManager, bobSLAWAmount);
        await bobWrappedToken.connect(bob).approve(addresses.LiquidityManager, bobTokenAmount);
        
        const bobPoolTx = await liquidityManager.connect(bob).createPool(
            bobWrappedTokenAddress,
            bobSLAWAmount,
            bobTokenAmount
        );
        const bobPoolReceipt = await bobPoolTx.wait();
        const bobPoolEvent = bobPoolReceipt.logs.find(log => {
            try {
                return liquidityManager.interface.parseLog(log).name === "PoolCreated";
            } catch {
                return false;
            }
        });
        const bobPairAddress = liquidityManager.interface.parseLog(bobPoolEvent).args.pairAddress;
        
        console.log(`✅ Bob created art liquidity pool`);
        console.log(`🌊 Pool Name: "Bob Pixelworks's Cyber Phoenix / SLAW LP"`);
        console.log(`🔗 Pair Address: ${bobPairAddress}`);
        console.log(`💧 SLAW Added: ${ethers.formatEther(bobSLAWAmount)}`);
        console.log(`🎨 Art Tokens Added: ${ethers.formatEther(bobTokenAmount)}\n`);

        // ===== STEP 5: Charlie Invests in Creator Pools =====
        console.log("💸 === STEP 5: Charlie Invests in Creator Pools ===");
        
        // Charlie adds liquidity to Alice's pool
        const charlieSLAWForAlice = ethers.parseEther("15000"); // 15K SLAW
        const charlieTokensForAlice = ethers.parseEther("3000"); // 3K music tokens
        
        // First, Charlie needs to buy some of Alice's tokens (simulate buy)
        await slawToken.connect(charlie).approve(addresses.LiquidityManager, ethers.parseEther("30000"));
        await aliceWrappedToken.connect(alice).transfer(charlie.address, charlieTokensForAlice);
        
        await aliceWrappedToken.connect(charlie).approve(addresses.LiquidityManager, charlieTokensForAlice);
        
        const charlieAliceAddTx = await liquidityManager.connect(charlie).addLiquidity(
            aliceWrappedTokenAddress,
            charlieSLAWForAlice,
            charlieTokensForAlice
        );
        await charlieAliceAddTx.wait();
        
        console.log(`✅ Charlie added liquidity to Alice's music pool`);
        console.log(`💧 SLAW Added: ${ethers.formatEther(charlieSLAWForAlice)}`);
        console.log(`🎵 Music Tokens Added: ${ethers.formatEther(charlieTokensForAlice)}`);
        
        // Charlie adds liquidity to Bob's pool
        const charlieSLAWForBob = ethers.parseEther("10000"); // 10K SLAW
        const charlieTokensForBob = ethers.parseEther("1250"); // 1.25K art tokens
        
        await bobWrappedToken.connect(bob).transfer(charlie.address, charlieTokensForBob);
        await bobWrappedToken.connect(charlie).approve(addresses.LiquidityManager, charlieTokensForBob);
        
        const charlieBobAddTx = await liquidityManager.connect(charlie).addLiquidity(
            bobWrappedTokenAddress,
            charlieSLAWForBob,
            charlieTokensForBob
        );
        await charlieBobAddTx.wait();
        
        console.log(`✅ Charlie added liquidity to Bob's art pool`);
        console.log(`💧 SLAW Added: ${ethers.formatEther(charlieSLAWForBob)}`);
        console.log(`🎨 Art Tokens Added: ${ethers.formatEther(charlieTokensForBob)}\n`);

        // ===== STEP 6: Check Creator Bonuses and Rankings =====
        console.log("🏆 === STEP 6: Creator Bonuses and Rankings ===");
        
        // Get updated creator profiles
        const aliceUpdatedProfile = await wrappedIPManager.getCreatorProfile(alice.address);
        const bobUpdatedProfile = await wrappedIPManager.getCreatorProfile(bob.address);
        
        console.log("💰 Creator Bonuses Earned:");
        console.log(`Alice: ${ethers.formatEther(aliceUpdatedProfile.totalValueCreated)} SLAW value created`);
        console.log(`Bob: ${ethers.formatEther(bobUpdatedProfile.totalValueCreated)} SLAW value created`);
        
        // Get top creators
        const topCreators = await wrappedIPManager.getTopCreators(5);
        console.log("\n🏆 Top Creators Ranking:");
        for (let i = 0; i < topCreators[0].length; i++) {
            console.log(`${i + 1}. ${topCreators[1][i]} - ${ethers.formatEther(topCreators[2][i])} SLAW value (Verified: ${topCreators[3][i]})`);
        }
        
        // Get creator pools
        const aliceCreatorPools = await liquidityManager.getCreatorPools(alice.address);
        const bobCreatorPools = await liquidityManager.getCreatorPools(bob.address);
        
        console.log("\n🌊 Creator Pool Details:");
        console.log(`Alice has ${aliceCreatorPools[0].length} pool(s)`);
        console.log(`Bob has ${bobCreatorPools[0].length} pool(s)\n`);

        // ===== STEP 7: Feature Alice's Pool (Admin Action) =====
        console.log("⭐ === STEP 7: Feature High-Value Pool ===");
        
        // Feature Alice's pool (gives 1.5x rewards)
        await liquidityManager.setPoolFeatured(aliceWrappedTokenAddress, true);
        console.log("✅ Featured Alice's music pool (1.5x rewards)");
        
        // Get featured pools
        const featuredPools = await liquidityManager.getFeaturedPools();
        console.log(`🌟 Featured Pools: ${featuredPools.length}`);
        
        // Get top pools by value
        const topPools = await liquidityManager.getTopPoolsByValue(3);
        console.log("\n💎 Top Pools by Value:");
        for (let i = 0; i < topPools[0].length; i++) {
            if (topPools[0][i] !== ethers.ZeroAddress) {
                console.log(`${i + 1}. ${topPools[1][i]} - ${ethers.formatEther(topPools[2][i])} SLAW value`);
                console.log(`   Creator: ${topPools[3][i]}`);
            }
        }

        // ===== STEP 8: Simulate Rewards Earning =====
        console.log("\n🎁 === STEP 8: Simulate Rewards System ===");
        
        // Check pending rewards for users
        const alicePairContract = await ethers.getContractAt("ValuedLiquidityPair", alicePairAddress);
        const bobPairContract = await ethers.getContractAt("ValuedLiquidityPair", bobPairAddress);
        
        const aliceLPBalance = await alicePairContract.balanceOf(alice.address);
        const charlieLPBalanceAlice = await alicePairContract.balanceOf(charlie.address);
        const charlieBoLPBalanceBob = await bobPairContract.balanceOf(charlie.address);
        
        console.log("🎫 LP Token Balances:");
        console.log(`Alice (in her own pool): ${ethers.formatEther(aliceLPBalance)}`);
        console.log(`Charlie (in Alice's pool): ${ethers.formatEther(charlieLPBalanceAlice)}`);
        console.log(`Charlie (in Bob's pool): ${ethers.formatEther(charlieBoLPBalanceBob)}`);
        
        // Get pool metrics
        const alicePoolMetrics = await alicePairContract.getPoolMetrics();
        const bobPoolMetrics = await bobPairContract.getPoolMetrics();
        
        console.log("\n📊 Pool Metrics:");
        console.log(`Alice's Pool Value: ${ethers.formatEther(alicePoolMetrics[0])} SLAW`);
        console.log(`Alice's Pool Age: ${alicePoolMetrics[5]} seconds`);
        console.log(`Bob's Pool Value: ${ethers.formatEther(bobPoolMetrics[0])} SLAW`);
        console.log(`Bob's Pool Age: ${bobPoolMetrics[5]} seconds`);

        // ===== STEP 9: Final System Status =====
        console.log("\n📊 === FINAL CREATOR ECONOMY STATUS ===");
        
        const systemMetrics = await wrappedIPManager.getSystemMetrics();
        const liquiditySystemMetrics = await liquidityManager.getSystemMetrics();
        
        console.log("\n🎨 IP Manager Metrics:");
        console.log(`Total Wrapped IPs: ${systemMetrics[0]}`);
        console.log(`Total IP Tokens: ${ethers.formatEther(systemMetrics[1])}`);
        console.log(`Total Value Locked: ${ethers.formatEther(systemMetrics[2])} SLAW`);
        console.log(`Total Creators: ${systemMetrics[3]}`);
        console.log(`Verified Creators: ${systemMetrics[4]}`);
        
        console.log("\n🌊 Liquidity Manager Metrics:");
        console.log(`Total Pools: ${liquiditySystemMetrics[0]}`);
        console.log(`Total Liquidity: ${ethers.formatEther(liquiditySystemMetrics[1])}`);
        console.log(`Total Volume: ${ethers.formatEther(liquiditySystemMetrics[2])}`);
        console.log(`Total Rewards: ${ethers.formatEther(liquiditySystemMetrics[3])}`);
        console.log(`Featured Pools: ${liquiditySystemMetrics[4]}`);
        
        console.log("\n👥 User Balances After Creator Economy:");
        console.log(`Alice SLAW: ${ethers.formatEther(await slawToken.balanceOf(alice.address))}`);
        console.log(`Alice Music Tokens: ${ethers.formatEther(await aliceWrappedToken.balanceOf(alice.address))}`);
        console.log(`Bob SLAW: ${ethers.formatEther(await slawToken.balanceOf(bob.address))}`);
        console.log(`Bob Art Tokens: ${ethers.formatEther(await bobWrappedToken.balanceOf(bob.address))}`);
        console.log(`Charlie SLAW: ${ethers.formatEther(await slawToken.balanceOf(charlie.address))}`);

        // ===== Save Creator Economy Results =====
        const creatorEconomyResults = {
            network: hre.network.name,
            timestamp: new Date().toISOString(),
            creators: {
                alice: {
                    address: alice.address,
                    profile: aliceUpdatedProfile,
                    wrapped_token: {
                        address: aliceWrappedTokenAddress,
                        name: aliceTokenName,
                        symbol: aliceTokenSymbol
                    },
                    pool: {
                        address: alicePairAddress,
                        featured: true
                    }
                },
                bob: {
                    address: bob.address,
                    profile: bobUpdatedProfile,
                    wrapped_token: {
                        address: bobWrappedTokenAddress,
                        name: bobTokenName,
                        symbol: bobTokenSymbol
                    },
                    pool: {
                        address: bobPairAddress,
                        featured: false
                    }
                }
            },
            investor: {
                charlie: {
                    address: charlie.address,
                    lp_positions: [
                        { pool: alicePairAddress, balance: ethers.formatEther(charlieLPBalanceAlice) },
                        { pool: bobPairAddress, balance: ethers.formatEther(charlieBoLPBalanceBob) }
                    ]
                }
            },
            metrics: {
                total_wrapped_ips: systemMetrics[0].toString(),
                total_value_locked: ethers.formatEther(systemMetrics[2]),
                total_creators: systemMetrics[3].toString(),
                verified_creators: systemMetrics[4].toString(),
                total_pools: liquiditySystemMetrics[0].toString(),
                total_liquidity: ethers.formatEther(liquiditySystemMetrics[1]),
                featured_pools: liquiditySystemMetrics[4].toString()
            }
        };
        
        const resultsPath = path.join(__dirname, "../deployments", `creator-economy-results-${hre.network.name}.json`);
        fs.writeFileSync(resultsPath, JSON.stringify(creatorEconomyResults, null, 2));
        
        console.log("\n🎉 ========================================");
        console.log("🎉 CREATOR ECONOMY WORKFLOW COMPLETED!");
        console.log("🎉 ========================================\n");
        
        console.log("✅ Creator Economy Features Demonstrated:");
        console.log("  1. ✅ Creator profile creation with verification");
        console.log("  2. ✅ Personalized token creation with creator branding");
        console.log("  3. ✅ Creator-branded liquidity pools");
        console.log("  4. ✅ Creator bonus system for first pools and liquidity attraction");
        console.log("  5. ✅ Creator rankings based on value created");
        console.log("  6. ✅ Featured pools with enhanced rewards");
        console.log("  7. ✅ Investor participation and LP token rewards");
        console.log("  8. ✅ Value tracking and metrics");
        
        console.log("\n💡 Creator Economy Benefits:");
        console.log("🎨 For Creators:");
        console.log("  • Personal branding on tokens and pools");
        console.log("  • Bonuses for creating and attracting liquidity");
        console.log("  • Rankings and verification system");
        console.log("  • Revenue from token sales and trading");
        
        console.log("\n💰 For Investors:");
        console.log("  • Direct investment in favorite creators");
        console.log("  • LP token rewards for providing liquidity");
        console.log("  • Exposure to creator success through token value");
        console.log("  • Featured pool benefits with higher rewards");
        
        console.log("\n🔥 For Platform:");
        console.log("  • Creator retention through personalized branding");
        console.log("  • Increased liquidity through creator incentives");
        console.log("  • Higher engagement through rankings and features");
        console.log("  • Sustainable token economy with value backing");
        
        console.log("\n💾 Results saved to:", resultsPath);
        
        return {
            success: true,
            results: creatorEconomyResults
        };

    } catch (error) {
        console.error("❌ Creator economy workflow failed:", error);
        
        // Save error log
        const errorPath = path.join(__dirname, "../deployments", `creator-economy-error-${Date.now()}.json`);
        fs.writeFileSync(errorPath, JSON.stringify({
            error: error.message,
            stack: error.stack,
            network: hre.network.name,
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
