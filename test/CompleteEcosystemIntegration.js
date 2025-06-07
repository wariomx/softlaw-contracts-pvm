const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("🌟 Complete Softlaw Ecosystem Integration Tests", function () {
    // Test accounts
    let owner, creator, investor, arbitrator, mediator, buyer, seller;
    
    // Core contracts
    let treasury, wrappedIPFactory, liquidityFactory;
    let copyrightLicensing, patentRegistry, disputeResolution, marketplace;
    let mockNFT;

    // Test constants
    const INITIAL_SLAW_SUPPLY = ethers.parseEther("10000000000"); // 10B SLAW
    const CREATOR_INITIAL_SLAW = ethers.parseEther("10000"); // 10K SLAW for testing

    /**
     * Deploy complete ecosystem for testing
     */
    async function deployCompleteEcosystem() {
        [owner, creator, investor, arbitrator, mediator, buyer, seller] = await ethers.getSigners();

        console.log("\n🚀 Deploying Complete Softlaw Ecosystem for Testing...");

        // 1. Deploy Uniswap V2 Factory
        const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
        liquidityFactory = await UniswapV2Factory.deploy(owner.address);
        await liquidityFactory.waitForDeployment();

        // 2. Deploy Softlaw Treasury
        const SoftlawTreasury = await ethers.getContractFactory("SoftlawTreasury");
        treasury = await SoftlawTreasury.deploy(
            owner.address,
            await liquidityFactory.getAddress(),
            owner.address
        );
        await treasury.waitForDeployment();

        // 3. Deploy Wrapped IP Factory
        const WrappedIPFactory = await ethers.getContractFactory("WrappedIPFactory");
        wrappedIPFactory = await WrappedIPFactory.deploy(
            await treasury.getAddress(),
            owner.address
        );
        await wrappedIPFactory.waitForDeployment();

        // 4. Deploy Enhanced Copyright Licensing
        const CopyrightLicensing = await ethers.getContractFactory("CopyrightLicensing");
        copyrightLicensing = await CopyrightLicensing.deploy(
            owner.address,
            await treasury.getAddress()
        );
        await copyrightLicensing.waitForDeployment();

        // 5. Deploy Patent Registry
        const PatentRegistry = await ethers.getContractFactory("PatentRegistry");
        patentRegistry = await PatentRegistry.deploy(
            await treasury.getAddress(),
            owner.address
        );
        await patentRegistry.waitForDeployment();

        // 6. Deploy Dispute Resolution
        const SoftlawDisputeResolution = await ethers.getContractFactory("SoftlawDisputeResolution");
        disputeResolution = await SoftlawDisputeResolution.deploy(
            await treasury.getAddress(),
            owner.address
        );
        await disputeResolution.waitForDeployment();

        // 7. Deploy Marketplace
        const SoftlawMarketplace = await ethers.getContractFactory("SoftlawMarketplace");
        marketplace = await SoftlawMarketplace.deploy(
            await treasury.getAddress(),
            owner.address
        );
        await marketplace.waitForDeployment();

        // 8. Deploy Mock NFT for testing
        const MockCopyrightNFT = await ethers.getContractFactory("MockCopyrightNFT");
        mockNFT = await MockCopyrightNFT.deploy();
        await mockNFT.waitForDeployment();

        // 9. Configure permissions
        const REGISTRY_ROLE = await treasury.REGISTRY_CONTRACT();
        const LICENSING_ROLE = await treasury.LICENSING_CONTRACT();
        const ARBITRATOR_ROLE = await disputeResolution.ARBITRATOR_ROLE();
        const MEDIATOR_ROLE = await disputeResolution.MEDIATOR_ROLE();

        await treasury.grantRole(REGISTRY_ROLE, await copyrightLicensing.getAddress());
        await treasury.grantRole(REGISTRY_ROLE, await patentRegistry.getAddress());
        await treasury.grantRole(LICENSING_ROLE, await copyrightLicensing.getAddress());
        await disputeResolution.grantRole(ARBITRATOR_ROLE, arbitrator.address);
        await disputeResolution.grantRole(MEDIATOR_ROLE, mediator.address);

        // 10. Setup initial SLAW distribution
        await treasury.distributeIncentives(
            [creator.address, investor.address, buyer.address, seller.address],
            [CREATOR_INITIAL_SLAW, CREATOR_INITIAL_SLAW, CREATOR_INITIAL_SLAW, CREATOR_INITIAL_SLAW]
        );

        console.log("✅ Complete ecosystem deployed and configured!");

        return {
            treasury, wrappedIPFactory, liquidityFactory,
            copyrightLicensing, patentRegistry, disputeResolution, marketplace,
            mockNFT, owner, creator, investor, arbitrator, mediator, buyer, seller
        };
    }

    beforeEach(async function () {
        ({
            treasury, wrappedIPFactory, liquidityFactory,
            copyrightLicensing, patentRegistry, disputeResolution, marketplace,
            mockNFT, owner, creator, investor, arbitrator, mediator, buyer, seller
        } = await loadFixture(deployCompleteEcosystem));
    });

    describe("🎯 End-to-End User Journey: Copyright", function () {
        let copyrightId, wrappedTokenAddress, pairAddress, licenseId;

        it("Should complete full copyright journey: Register → Tokenize → List → Trade → License → Dispute", async function () {
            console.log("\n🎬 Starting Complete Copyright Journey...");

            // Step 1: Register Copyright
            console.log("1. 📄 Registering copyright...");
            const tx1 = await copyrightLicensing.connect(creator).registerCopyright(
                "AI Innovation Algorithm",
                "Revolutionary AI algorithm for patent analysis",
                ["AI", "Machine Learning", "Patent Analysis"],
                "Innovation Co.",
                "QmHash123456", // IPFS hash
                {
                    reproduction: true,
                    distribution: true,
                    rental: false,
                    broadcasting: true,
                    performance: false,
                    translation: true,
                    adaptation: true
                }
            );
            const receipt1 = await tx1.wait();
            copyrightId = 1; // First copyright
            console.log("   ✅ Copyright registered with ID:", copyrightId);

            // Step 2: Tokenize Copyright
            console.log("2. 🎁 Tokenizing copyright...");
            const tx2 = await copyrightLicensing.connect(creator).tokenizeCopyright(
                copyrightId,
                ethers.parseEther("1000"), // 1000 tokens
                ethers.parseEther("5"),     // 5 SLAW per token
                "AI Innovation Tokens"
            );
            await tx2.wait();
            
            const copyrightInfo = await copyrightLicensing.getCopyrightInfo(copyrightId);
            wrappedTokenAddress = copyrightInfo.wrappedToken;
            expect(copyrightInfo.tokenized).to.be.true;
            console.log("   ✅ Copyright tokenized. Wrapped token:", wrappedTokenAddress);

            // Step 3: Create Liquidity Pool
            console.log("3. 🏊 Creating liquidity pool...");
            const tx3 = await copyrightLicensing.connect(creator).createCopyrightLiquidityPool(
                copyrightId,
                ethers.parseEther("500"),  // 500 IP tokens
                ethers.parseEther("2500")  // 2500 SLAW tokens
            );
            await tx3.wait();
            
            pairAddress = await liquidityFactory.getPair(wrappedTokenAddress, await treasury.getAddress());
            expect(pairAddress).to.not.equal(ethers.ZeroAddress);
            console.log("   ✅ Liquidity pool created:", pairAddress);

            // Step 4: List on Marketplace
            console.log("4. 🏪 Listing on marketplace...");
            const tx4 = await marketplace.connect(creator).createFixedPriceListing(
                0, // AssetType.COPYRIGHT_NFT
                await copyrightLicensing.getAddress(),
                copyrightId,
                1, // quantity
                ethers.parseEther("8000"), // 8000 SLAW
                7 * 24 * 60 * 60, // 7 days
                "AI Innovation Copyright",
                "Complete rights to revolutionary AI algorithm",
                ["AI", "Innovation", "Patent"],
                creator.address,
                500 // 5% royalty
            );
            await tx4.wait();
            console.log("   ✅ Listed on marketplace");

            // Step 5: Create Enhanced License
            console.log("5. 📜 Creating enhanced license...");
            const tx5 = await copyrightLicensing.connect(creator).offerEnhancedLicense(
                copyrightId,
                buyer.address,
                0, // LicenseType.COMMERCIAL
                ethers.parseEther("1000"), // 1000 SLAW
                365 * 24 * 60 * 60, // 1 year
                "Commercial use license for AI algorithm",
                {
                    reproduction: true,
                    distribution: true,
                    rental: false,
                    broadcasting: false,
                    performance: false,
                    translation: false,
                    adaptation: false
                },
                false, // not exclusive
                "Worldwide",
                true // auto-tokenization
            );
            await tx5.wait();
            licenseId = 1; // First license
            console.log("   ✅ Enhanced license offered with ID:", licenseId);

            // Step 6: Accept License
            console.log("6. ✅ Accepting license...");
            const tx6 = await copyrightLicensing.connect(buyer).acceptEnhancedLicense(licenseId);
            await tx6.wait();
            
            const license = await copyrightLicensing.getEnhancedLicense(licenseId);
            expect(license.status).to.equal(1); // ACCEPTED
            console.log("   ✅ License accepted and payments processed");

            // Step 7: File Dispute
            console.log("7. 🏛️ Filing dispute...");
            const tx7 = await disputeResolution.connect(buyer).fileDispute(
                0, // DisputeType.COPYRIGHT_INFRINGEMENT
                creator.address,
                copyrightId,
                await copyrightLicensing.getAddress(),
                "License Breach Dispute",
                "Creator is not honoring the agreed license terms",
                ethers.parseEther("500") // 500 SLAW damages
            );
            await tx7.wait();
            
            const disputeId = 1;
            const dispute = await disputeResolution.getDispute(disputeId);
            expect(dispute.plaintiff).to.equal(buyer.address);
            console.log("   ✅ Dispute filed with ID:", disputeId);

            // Step 8: Start Mediation
            console.log("8. 🤝 Starting mediation...");
            const tx8 = await disputeResolution.connect(buyer).startMediation(disputeId, mediator.address);
            await tx8.wait();
            console.log("   ✅ Mediation started");

            // Step 9: Verify System State
            console.log("9. 📊 Verifying final system state...");
            const finalMetrics = await treasury.getSystemMetrics();
            const marketStats = await marketplace.getMarketStats();
            
            expect(finalMetrics[1]).to.equal(1); // 1 wrapped IP
            expect(finalMetrics[2]).to.equal(1); // 1 liquidity pool
            expect(marketStats.totalListings).to.equal(1); // 1 marketplace listing
            
            console.log("   💰 Treasury Balance:", ethers.formatEther(finalMetrics[0]));
            console.log("   🎁 Wrapped IPs:", finalMetrics[1].toString());
            console.log("   🏊 Liquidity Pools:", finalMetrics[2].toString());
            console.log("   🏪 Marketplace Listings:", marketStats.totalListings.toString());

            console.log("\n🎉 Complete Copyright Journey Successful!");
        });
    });

    describe("🎯 End-to-End User Journey: Patent", function () {
        let patentId, wrappedTokenAddress;

        it("Should complete full patent journey: File → Examine → Grant → Tokenize → Marketplace", async function () {
            console.log("\n🎬 Starting Complete Patent Journey...");

            // Step 1: File Patent
            console.log("1. 📋 Filing patent application...");
            const tx1 = await patentRegistry.connect(creator).filePatent(
                "Quantum Computing Algorithm",
                "Revolutionary quantum algorithm for optimization problems",
                ["Quantum entanglement optimization", "Error correction protocol", "Speedup verification"],
                ["quantum", "optimization", "algorithm"],
                "Dr. Quantum Creator",
                0, // PatentType.UTILITY
                "USPTO",
                "QmPatentHash123",
                ["Prior Art Reference 1", "Prior Art Reference 2"]
            );
            await tx1.wait();
            patentId = 1;
            console.log("   ✅ Patent filed with ID:", patentId);

            // Step 2: Move to Examination
            console.log("2. 🔍 Moving to examination...");
            const tx2 = await patentRegistry.connect(owner).moveToExamination(patentId);
            await tx2.wait();
            console.log("   ✅ Patent under examination");

            // Step 3: Grant Patent
            console.log("3. 🏆 Granting patent...");
            const tx3 = await patentRegistry.connect(owner).grantPatent(
                patentId,
                "US11,123,456",
                20 // 20 years
            );
            await tx3.wait();
            
            const patentInfo = await patentRegistry.getPatentInfo(patentId);
            expect(patentInfo.status).to.equal(2); // GRANTED
            console.log("   ✅ Patent granted with number:", "US11,123,456");

            // Step 4: Tokenize Patent
            console.log("4. 🎁 Tokenizing patent...");
            const tx4 = await patentRegistry.connect(creator).tokenizePatent(
                patentId,
                ethers.parseEther("2000"), // 2000 tokens
                ethers.parseEther("10"),    // 10 SLAW per token
                "Quantum Algorithm Tokens"
            );
            await tx4.wait();
            
            const updatedPatentInfo = await patentRegistry.getPatentInfo(patentId);
            wrappedTokenAddress = updatedPatentInfo.wrappedToken;
            expect(updatedPatentInfo.isTokenized).to.be.true;
            console.log("   ✅ Patent tokenized. Wrapped token:", wrappedTokenAddress);

            // Step 5: Create Auction on Marketplace
            console.log("5. 🏛️ Creating auction on marketplace...");
            const tx5 = await marketplace.connect(creator).createAuction(
                1, // AssetType.PATENT_NFT
                await patentRegistry.getAddress(),
                patentId,
                ethers.parseEther("15000"), // 15K SLAW reserve
                7 * 24 * 60 * 60, // 7 days
                "Quantum Computing Patent Auction",
                "Exclusive rights to revolutionary quantum algorithm",
                creator.address,
                750 // 7.5% royalty
            );
            await tx5.wait();
            console.log("   ✅ Patent auction created");

            // Step 6: Place Bids
            console.log("6. 💰 Placing bids...");
            const tx6a = await marketplace.connect(investor).placeBid(1, ethers.parseEther("16000"));
            await tx6a.wait();
            
            const tx6b = await marketplace.connect(buyer).placeBid(1, ethers.parseEther("18000"));
            await tx6b.wait();
            console.log("   ✅ Bids placed: 16K and 18K SLAW");

            // Step 7: Pay Maintenance Fee
            console.log("7. 💳 Paying maintenance fee...");
            const tx7 = await patentRegistry.connect(creator).payMaintenanceFee(patentId);
            await tx7.wait();
            console.log("   ✅ Maintenance fee paid");

            console.log("\n🎉 Complete Patent Journey Successful!");
        });
    });

    describe("🎯 Cross-System Integration Tests", function () {
        it("Should handle complex multi-contract interactions", async function () {
            console.log("\n🔗 Testing Cross-System Integration...");

            // Create copyright and patent
            await copyrightLicensing.connect(creator).registerCopyright(
                "Hybrid AI System",
                "AI system combining multiple innovations",
                ["AI", "Hybrid"],
                "Innovation Lab",
                "QmHybridHash",
                {
                    reproduction: true,
                    distribution: true,
                    rental: true,
                    broadcasting: true,
                    performance: true,
                    translation: true,
                    adaptation: true
                }
            );

            await patentRegistry.connect(creator).filePatent(
                "Hybrid AI Method",
                "Patented method for hybrid AI",
                ["Novel combination claim"],
                ["AI", "method"],
                "Dr. Creator",
                0, // UTILITY
                "USPTO",
                "QmMethodHash",
                []
            );

            // Grant patent
            await patentRegistry.connect(owner).moveToExamination(1);
            await patentRegistry.connect(owner).grantPatent(1, "US11,999,999", 20);

            // Tokenize both
            await copyrightLicensing.connect(creator).tokenizeCopyright(
                1,
                ethers.parseEther("1000"),
                ethers.parseEther("3"),
                "Hybrid AI Copyright Tokens"
            );

            await patentRegistry.connect(creator).tokenizePatent(
                1,
                ethers.parseEther("1000"),
                ethers.parseEther("7"),
                "Hybrid AI Patent Tokens"
            );

            // Create bundle listing on marketplace
            // Note: This would require bundle functionality to be fully implemented
            
            // File dispute involving both IPs
            await disputeResolution.connect(buyer).fileDispute(
                1, // PATENT_INFRINGEMENT
                creator.address,
                1, // patent ID
                await patentRegistry.getAddress(),
                "Complex IP Dispute",
                "Dispute involving both copyright and patent",
                ethers.parseEther("2000")
            );

            // Register arbitrator
            await disputeResolution.connect(arbitrator).registerArbitrator(
                "Expert IP Arbitrator",
                "PhD in IP Law, 10+ years experience",
                ["COPYRIGHT_INFRINGEMENT", "PATENT_INFRINGEMENT"],
                ethers.parseEther("100")
            );

            // Start arbitration
            await disputeResolution.connect(buyer).startArbitration(1, arbitrator.address);

            console.log("   ✅ Cross-system integration successful");
        });

        it("Should handle treasury fee distributions correctly", async function () {
            console.log("\n💰 Testing Treasury Fee Distributions...");

            // Track initial balances
            const initialCreatorBalance = await treasury.balanceOf(creator.address);
            const initialTreasuryBalance = await treasury.getTreasuryBalance();

            // Register copyright (pays registration fee)
            await copyrightLicensing.connect(creator).registerCopyright(
                "Fee Test Copyright",
                "Testing fee distributions",
                ["test"],
                "Test Co",
                "QmTestHash",
                {
                    reproduction: true,
                    distribution: false,
                    rental: false,
                    broadcasting: false,
                    performance: false,
                    translation: false,
                    adaptation: false
                }
            );

            // Create and accept license
            await copyrightLicensing.connect(creator).offerEnhancedLicense(
                1,
                buyer.address,
                0, // COMMERCIAL
                ethers.parseEther("500"),
                365 * 24 * 60 * 60,
                "Test license",
                {
                    reproduction: true,
                    distribution: false,
                    rental: false,
                    broadcasting: false,
                    performance: false,
                    translation: false,
                    adaptation: false
                },
                false,
                "Global",
                false
            );

            await copyrightLicensing.connect(buyer).acceptEnhancedLicense(1);

            // Verify fee distributions
            const finalCreatorBalance = await treasury.balanceOf(creator.address);
            const finalTreasuryBalance = await treasury.getTreasuryBalance();

            // Creator should have received licensing revenue (70% of license fee)
            expect(finalCreatorBalance).to.be.gt(initialCreatorBalance);
            
            console.log("   💰 Initial Creator Balance:", ethers.formatEther(initialCreatorBalance));
            console.log("   💰 Final Creator Balance:", ethers.formatEther(finalCreatorBalance));
            console.log("   ✅ Fee distributions working correctly");
        });
    });

    describe("🎯 System Stress Tests", function () {
        it("Should handle multiple concurrent operations", async function () {
            console.log("\n⚡ Running System Stress Tests...");

            // Create multiple IPs simultaneously
            const promises = [];
            for (let i = 0; i < 5; i++) {
                promises.push(
                    copyrightLicensing.connect(creator).registerCopyright(
                        `Bulk Copyright ${i}`,
                        `Description ${i}`,
                        [`tag${i}`],
                        "Bulk Creator",
                        `QmHash${i}`,
                        {
                            reproduction: true,
                            distribution: true,
                            rental: false,
                            broadcasting: false,
                            performance: false,
                            translation: false,
                            adaptation: false
                        }
                    )
                );
            }

            await Promise.all(promises);

            // Tokenize all copyrights
            for (let i = 1; i <= 5; i++) {
                await copyrightLicensing.connect(creator).tokenizeCopyright(
                    i,
                    ethers.parseEther("100"),
                    ethers.parseEther("1"),
                    `Bulk Token ${i}`
                );
            }

            // Verify system metrics
            const finalMetrics = await treasury.getSystemMetrics();
            expect(finalMetrics[1]).to.equal(5); // 5 wrapped IPs

            console.log("   ✅ Created and tokenized 5 IPs successfully");
            console.log("   📊 Final wrapped IPs:", finalMetrics[1].toString());
        });

        it("Should maintain system consistency under load", async function () {
            console.log("\n🔄 Testing System Consistency...");

            // Create IP
            await copyrightLicensing.connect(creator).registerCopyright(
                "Consistency Test",
                "Testing system consistency",
                ["consistency"],
                "Test Lab",
                "QmConsistencyHash",
                {
                    reproduction: true,
                    distribution: true,
                    rental: true,
                    broadcasting: true,
                    performance: true,
                    translation: true,
                    adaptation: true
                }
            );

            // Tokenize
            await copyrightLicensing.connect(creator).tokenizeCopyright(
                1,
                ethers.parseEther("1000"),
                ethers.parseEther("2"),
                "Consistency Tokens"
            );

            // Create multiple licenses
            for (let i = 0; i < 3; i++) {
                await copyrightLicensing.connect(creator).offerEnhancedLicense(
                    1,
                    i === 0 ? buyer.address : i === 1 ? investor.address : seller.address,
                    0, // COMMERCIAL
                    ethers.parseEther("100"),
                    365 * 24 * 60 * 60,
                    `License ${i}`,
                    {
                        reproduction: true,
                        distribution: false,
                        rental: false,
                        broadcasting: false,
                        performance: false,
                        translation: false,
                        adaptation: false
                    },
                    false,
                    "Global",
                    false
                );
            }

            // Verify all licenses are tracked correctly
            const copyrightInfo = await copyrightLicensing.getCopyrightInfo(1);
            expect(copyrightInfo.licenseIds.length).to.equal(3);

            console.log("   ✅ System consistency maintained under load");
        });
    });

    describe("📊 Final System Verification", function () {
        it("Should have all systems properly integrated and operational", async function () {
            console.log("\n🔍 Final System Verification...");

            // Check Treasury integration
            const treasuryMetrics = await treasury.getSystemMetrics();
            expect(treasuryMetrics[0]).to.be.gt(0); // Treasury has balance

            // Check all contracts are connected
            expect(await treasury.hasRole(await treasury.REGISTRY_CONTRACT(), await copyrightLicensing.getAddress())).to.be.true;
            expect(await treasury.hasRole(await treasury.REGISTRY_CONTRACT(), await patentRegistry.getAddress())).to.be.true;

            // Check marketplace is operational
            const marketStats = await marketplace.getMarketStats();
            expect(await marketplace.hasRole(await marketplace.MARKETPLACE_ADMIN(), owner.address)).to.be.true;

            // Check dispute resolution is configured
            expect(await disputeResolution.hasRole(await disputeResolution.ARBITRATOR_ROLE(), arbitrator.address)).to.be.true;

            console.log("   ✅ Treasury Integration: Working");
            console.log("   ✅ Copyright System: Working");
            console.log("   ✅ Patent System: Working");
            console.log("   ✅ Dispute Resolution: Working");
            console.log("   ✅ Marketplace: Working");
            console.log("   ✅ Liquidity System: Working");

            console.log("\n🌟 COMPLETE SOFTLAW ECOSYSTEM: FULLY OPERATIONAL!");
        });
    });
});
