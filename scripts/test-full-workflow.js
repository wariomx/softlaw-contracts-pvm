const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    console.log("🔄 Testing Full Softlaw PVM Workflow...\n");
    
    const [deployer, user1, user2] = await ethers.getSigners();
    console.log("👤 Deployer:", deployer.address);
    console.log("👤 User1:", user1.address);
    console.log("👤 User2:", user2.address);
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
        
        const transferAmount = ethers.parseEther("10000"); // 10K SLAW each
        
        // Transfer SLAW to users for testing
        await slawToken.transfer(user1.address, transferAmount);
        await slawToken.transfer(user2.address, transferAmount);
        
        console.log(`✅ Transferred ${ethers.formatEther(transferAmount)} SLAW to User1`);
        console.log(`✅ Transferred ${ethers.formatEther(transferAmount)} SLAW to User2`);
        
        const user1Balance = await slawToken.balanceOf(user1.address);
        const user2Balance = await slawToken.balanceOf(user2.address);
        console.log(`💰 User1 SLAW Balance: ${ethers.formatEther(user1Balance)}`);
        console.log(`💰 User2 SLAW Balance: ${ethers.formatEther(user2Balance)}\n`);

        // ===== STEP 2: Mint Test NFT =====
        console.log("🎨 === STEP 2: Mint Copyright NFT ===");
        
        const mintTx = await testNFT.connect(user1).mintCopyright(
            user1.address,
            "My Original Song",
            "A beautiful original composition",
            "music",
            "https://metadata.example.com/song/1"
        );
        const receipt = await mintTx.wait();
        
        // Get the token ID from the event
        const mintEvent = receipt.logs.find(log => {
            try {
                return testNFT.interface.parseLog(log).name === "CopyrightMinted";
            } catch {
                return false;
            }
        });
        
        const tokenId = testNFT.interface.parseLog(mintEvent).args.tokenId;
        console.log(`✅ Minted NFT with Token ID: ${tokenId}`);
        
        const copyrightInfo = await testNFT.getCopyrightInfo(tokenId);
        console.log(`🎵 Title: ${copyrightInfo.title}`);
        console.log(`📝 Category: ${copyrightInfo.category}\n`);

        // ===== STEP 3: Wrap NFT to ERC20 Tokens =====
        console.log("🔄 === STEP 3: Wrap NFT to ERC20 Tokens ===");
        
        const totalSupply = ethers.parseEther("1000"); // 1000 tokens
        const pricePerToken = ethers.parseEther("10"); // 10 SLAW per token
        
        // Approve WrappedIPManager to transfer the NFT
        await testNFT.connect(user1).approve(addresses.WrappedIPManager, tokenId);
        console.log("✅ Approved WrappedIPManager to transfer NFT");
        
        // Wrap the NFT
        const wrapTx = await wrappedIPManager.connect(user1).wrapIP(
            addresses.TestCopyrightNFT,
            tokenId,
            totalSupply,
            pricePerToken,
            "Wrapped Song Token",
            "WST",
            "Tokenized version of My Original Song"
        );
        const wrapReceipt = await wrapTx.wait();
        
        // Get the wrapped token address from the event
        const wrapEvent = wrapReceipt.logs.find(log => {
            try {
                return wrappedIPManager.interface.parseLog(log).name === "IPWrapped";
            } catch {
                return false;
            }
        });
        
        const ipId = wrappedIPManager.interface.parseLog(wrapEvent).args.ipId;
        const wrappedTokenAddress = wrappedIPManager.interface.parseLog(wrapEvent).args.tokenAddress;
        
        console.log(`✅ Wrapped NFT to tokens`);
        console.log(`🔗 IP ID: ${ipId}`);
        console.log(`📄 Wrapped Token Address: ${wrappedTokenAddress}`);
        
        const wrappedToken = await ethers.getContractAt("WrappedIPToken", wrappedTokenAddress);
        const user1TokenBalance = await wrappedToken.balanceOf(user1.address);
        console.log(`💎 User1 Wrapped Token Balance: ${ethers.formatEther(user1TokenBalance)}\n`);

        // ===== STEP 4: Create Liquidity Pool =====
        console.log("🌊 === STEP 4: Create Liquidity Pool ===");
        
        const slawLiquidityAmount = ethers.parseEther("5000"); // 5000 SLAW
        const tokenLiquidityAmount = ethers.parseEther("500"); // 500 Wrapped tokens
        
        // Approve tokens for liquidity manager
        await slawToken.connect(user1).approve(addresses.LiquidityManager, slawLiquidityAmount);
        await wrappedToken.connect(user1).approve(addresses.LiquidityManager, tokenLiquidityAmount);
        console.log("✅ Approved tokens for LiquidityManager");
        
        // Create liquidity pool
        const poolTx = await liquidityManager.connect(user1).createPool(
            wrappedTokenAddress,
            slawLiquidityAmount,
            tokenLiquidityAmount
        );
        const poolReceipt = await poolTx.wait();
        
        const poolEvent = poolReceipt.logs.find(log => {
            try {
                return liquidityManager.interface.parseLog(log).name === "PoolCreated";
            } catch {
                return false;
            }
        });
        
        const pairAddress = liquidityManager.interface.parseLog(poolEvent).args.pairAddress;
        console.log(`✅ Created liquidity pool`);
        console.log(`🔗 Pair Address: ${pairAddress}`);
        console.log(`💧 SLAW Added: ${ethers.formatEther(slawLiquidityAmount)}`);
        console.log(`💎 Tokens Added: ${ethers.formatEther(tokenLiquidityAmount)}`);
        
        const lpToken = await ethers.getContractAt("SimpleLiquidityPair", pairAddress);
        const lpBalance = await lpToken.balanceOf(user1.address);
        console.log(`🎫 LP Tokens Received: ${ethers.formatEther(lpBalance)}\n`);

        // ===== STEP 5: List Remaining NFT on Marketplace =====
        console.log("🏪 === STEP 5: Marketplace Listing ===");
        
        // First, mint another NFT for marketplace testing
        const mintTx2 = await testNFT.connect(user1).mintTestNFT(user1.address, "art");
        const receipt2 = await mintTx2.wait();
        
        const mintEvent2 = receipt2.logs.find(log => {
            try {
                return testNFT.interface.parseLog(log).name === "CopyrightMinted";
            } catch {
                return false;
            }
        });
        
        const tokenId2 = testNFT.interface.parseLog(mintEvent2).args.tokenId;
        console.log(`🎨 Minted additional NFT for marketplace: Token ID ${tokenId2}`);
        
        // Approve marketplace to transfer NFT
        await testNFT.connect(user1).approve(addresses.MarketplaceCore, tokenId2);
        console.log("✅ Approved MarketplaceCore to transfer NFT");
        
        // Create marketplace listing
        const listingPrice = ethers.parseEther("1000"); // 1000 SLAW
        const duration = 30 * 24 * 60 * 60; // 30 days
        
        const listTx = await marketplaceCore.connect(user1).createNFTListing(
            addresses.TestCopyrightNFT,
            tokenId2,
            listingPrice,
            duration,
            true // allow offers
        );
        const listReceipt = await listTx.wait();
        
        const listEvent = listReceipt.logs.find(log => {
            try {
                return marketplaceCore.interface.parseLog(log).name === "ListingCreated";
            } catch {
                return false;
            }
        });
        
        const listingId = marketplaceCore.interface.parseLog(listEvent).args.listingId;
        console.log(`✅ Created marketplace listing`);
        console.log(`🏷️  Listing ID: ${listingId}`);
        console.log(`💰 Price: ${ethers.formatEther(listingPrice)} SLAW\n`);

        // ===== STEP 6: Make Offer on Marketplace =====
        console.log("💸 === STEP 6: Marketplace Offer ===");
        
        const offerAmount = ethers.parseEther("800"); // 800 SLAW offer
        const offerDuration = 7 * 24 * 60 * 60; // 7 days
        
        // Approve SLAW for potential purchase
        await slawToken.connect(user2).approve(addresses.MarketplaceCore, offerAmount);
        console.log("✅ User2 approved SLAW for marketplace");
        
        // Make offer
        const offerTx = await marketplaceCore.connect(user2).makeOffer(
            listingId,
            offerAmount,
            offerDuration
        );
        const offerReceipt = await offerTx.wait();
        
        const offerEvent = offerReceipt.logs.find(log => {
            try {
                return marketplaceCore.interface.parseLog(log).name === "OfferCreated";
            } catch {
                return false;
            }
        });
        
        const offerId = marketplaceCore.interface.parseLog(offerEvent).args.offerId;
        console.log(`✅ Made offer on listing`);
        console.log(`🏷️  Offer ID: ${offerId}`);
        console.log(`💰 Offer Amount: ${ethers.formatEther(offerAmount)} SLAW\n`);

        // ===== STEP 7: Accept Offer =====
        console.log("🤝 === STEP 7: Accept Marketplace Offer ===");
        
        const user1BalanceBefore = await slawToken.balanceOf(user1.address);
        const user2BalanceBefore = await slawToken.balanceOf(user2.address);
        
        // Accept the offer
        const acceptTx = await marketplaceCore.connect(user1).acceptOffer(offerId);
        await acceptTx.wait();
        
        console.log(`✅ Accepted offer`);
        
        // Check NFT ownership transfer
        const newOwner = await testNFT.ownerOf(tokenId2);
        console.log(`🎨 NFT now owned by: ${newOwner}`);
        console.log(`✅ NFT transferred to User2: ${newOwner === user2.address}`);
        
        // Check pending payouts (withdrawal pattern)
        const pendingPayout = await treasuryCore.getPendingPayout(user1.address);
        console.log(`💰 User1 Pending Payout: ${ethers.formatEther(pendingPayout)} SLAW`);
        
        // Claim payout
        if (pendingPayout > 0) {
            await treasuryCore.connect(user1).claimPayout();
            console.log("✅ User1 claimed payout");
        }
        
        const user1BalanceAfter = await slawToken.balanceOf(user1.address);
        const user2BalanceAfter = await slawToken.balanceOf(user2.address);
        
        console.log(`📊 User1 SLAW Change: ${ethers.formatEther(user1BalanceAfter - user1BalanceBefore)}`);
        console.log(`📊 User2 SLAW Change: ${ethers.formatEther(user2BalanceAfter - user2BalanceBefore)}\n`);

        // ===== STEP 8: Final System Status =====
        console.log("📊 === FINAL SYSTEM STATUS ===");
        
        const treasuryMetrics = await treasuryCore.getSystemMetrics();
        const ipMetrics = await wrappedIPManager.getSystemMetrics();
        const liquidityMetrics = await liquidityManager.getSystemMetrics();
        const marketplaceMetrics = await marketplaceCore.getSystemMetrics();
        
        console.log("\n💰 Treasury Metrics:");
        console.log(`  Fees Collected: ${ethers.formatEther(treasuryMetrics[0])} SLAW`);
        console.log(`  Total Registrations: ${treasuryMetrics[1]}`);
        console.log(`  Total Licenses: ${treasuryMetrics[2]}`);
        console.log(`  Treasury Balance: ${ethers.formatEther(treasuryMetrics[3])} SLAW`);
        
        console.log("\n🎨 IP Manager Metrics:");
        console.log(`  Total Wrapped IPs: ${ipMetrics[0]}`);
        console.log(`  Total IP Tokens: ${ethers.formatEther(ipMetrics[1])}`);
        
        console.log("\n🌊 Liquidity Metrics:");
        console.log(`  Total Pools: ${liquidityMetrics[0]}`);
        console.log(`  Total Liquidity: ${ethers.formatEther(liquidityMetrics[1])} (value)`);
        
        console.log("\n🏪 Marketplace Metrics:");
        console.log(`  Total Listings: ${marketplaceMetrics[0]}`);
        console.log(`  Total Sales: ${marketplaceMetrics[1]}`);
        console.log(`  Total Volume: ${ethers.formatEther(marketplaceMetrics[2])} SLAW`);
        
        console.log("\n👤 User Balances:");
        console.log(`  User1 SLAW: ${ethers.formatEther(await slawToken.balanceOf(user1.address))}`);
        console.log(`  User1 Wrapped Tokens: ${ethers.formatEther(await wrappedToken.balanceOf(user1.address))}`);
        console.log(`  User1 LP Tokens: ${ethers.formatEther(await lpToken.balanceOf(user1.address))}`);
        console.log(`  User2 SLAW: ${ethers.formatEther(await slawToken.balanceOf(user2.address))}`);

        // ===== Save Workflow Results =====
        const workflowResults = {
            network: hre.network.name,
            timestamp: new Date().toISOString(),
            steps: {
                "1_slaw_distribution": {
                    user1_balance: ethers.formatEther(await slawToken.balanceOf(user1.address)),
                    user2_balance: ethers.formatEther(await slawToken.balanceOf(user2.address))
                },
                "2_nft_mint": {
                    token_id: tokenId.toString(),
                    owner: user1.address
                },
                "3_nft_wrapping": {
                    ip_id: ipId,
                    wrapped_token_address: wrappedTokenAddress,
                    total_supply: ethers.formatEther(totalSupply)
                },
                "4_liquidity_pool": {
                    pair_address: pairAddress,
                    slaw_added: ethers.formatEther(slawLiquidityAmount),
                    tokens_added: ethers.formatEther(tokenLiquidityAmount)
                },
                "5_marketplace_listing": {
                    listing_id: listingId.toString(),
                    token_id: tokenId2.toString(),
                    price: ethers.formatEther(listingPrice)
                },
                "6_marketplace_offer": {
                    offer_id: offerId.toString(),
                    amount: ethers.formatEther(offerAmount)
                },
                "7_offer_acceptance": {
                    nft_new_owner: newOwner,
                    sale_completed: true
                }
            },
            final_metrics: {
                treasury: {
                    fees_collected: ethers.formatEther(treasuryMetrics[0]),
                    registrations: treasuryMetrics[1].toString(),
                    licenses: treasuryMetrics[2].toString()
                },
                ip_manager: {
                    wrapped_ips: ipMetrics[0].toString(),
                    total_tokens: ethers.formatEther(ipMetrics[1])
                },
                liquidity: {
                    total_pools: liquidityMetrics[0].toString(),
                    total_liquidity: ethers.formatEther(liquidityMetrics[1])
                },
                marketplace: {
                    total_listings: marketplaceMetrics[0].toString(),
                    total_sales: marketplaceMetrics[1].toString(),
                    total_volume: ethers.formatEther(marketplaceMetrics[2])
                }
            }
        };
        
        const workflowPath = path.join(__dirname, "../deployments", `workflow-results-${hre.network.name}.json`);
        fs.writeFileSync(workflowPath, JSON.stringify(workflowResults, null, 2));
        
        console.log("\n🎉 ========================================");
        console.log("🎉 FULL WORKFLOW TEST COMPLETED SUCCESSFULLY!");
        console.log("🎉 ========================================\n");
        
        console.log("✅ All steps completed:");
        console.log("  1. ✅ SLAW token distribution");
        console.log("  2. ✅ Copyright NFT minting");
        console.log("  3. ✅ NFT wrapping to ERC20 tokens");
        console.log("  4. ✅ Liquidity pool creation");
        console.log("  5. ✅ Marketplace listing");
        console.log("  6. ✅ Marketplace offer");
        console.log("  7. ✅ Offer acceptance and NFT sale");
        
        console.log("\n💾 Workflow results saved to:", workflowPath);
        
        return {
            success: true,
            results: workflowResults
        };

    } catch (error) {
        console.error("❌ Workflow test failed:", error);
        
        // Save error log
        const errorPath = path.join(__dirname, "../deployments", `workflow-error-${Date.now()}.json`);
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
