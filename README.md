# 🚀 Softlaw Contracts PVM - Integrations

**Modular smart contract architecture optimized for PVM/Revive compiler**

## 🎯 Overview

This branch contains a complete refactor of the Softlaw ecosystem with a modular, lightweight architecture optimized for Polkadot's PVM (PolkaVM) and the Revive compiler. The system is designed to handle copyright NFTs, tokenization, liquidity pools, and marketplace functionality while respecting PVM's constraints and best practices.

## 🏗️ Architecture

### Core Modules

1. **[SLAWToken](./contracts/integrations/SLAWToken.sol)** - ERC20 token with withdrawal patterns
2. **[TreasuryCore](./contracts/integrations/TreasuryCore.sol)** - Fee management and payment processing 
3. **[WrappedIPManager](./contracts/integrations/WrappedIPManager.sol)** - NFT to ERC20 conversion
4. **[LiquidityManager](./contracts/integrations/LiquidityManager.sol)** - Simplified AMM for IP tokens
5. **[MarketplaceCore](./contracts/integrations/MarketplaceCore.sol)** - NFT and token trading
6. **[TestCopyrightNFT](./contracts/integrations/TestCopyrightNFT.sol)** - Test NFT contract

### 🔥 PVM Optimizations

- ✅ **viaIR enabled** - Resolves "Stack too deep" errors
- ✅ **No .send/.transfer** - Uses withdrawal patterns for safety
- ✅ **No ecrecover** - Avoids signature verification issues
- ✅ **Memory constraints** - Respects 64kb memory limit
- ✅ **Lightweight contracts** - Modular design reduces complexity
- ✅ **Gas optimizations** - Efficient storage and computation

## 🚀 Quick Start

### Prerequisites

```bash
node --version  # Requires Node.js 18+
npm install     # Install dependencies
```

### 1. Deploy Complete System

```bash
# Deploy all core contracts
npx hardhat run scripts/deploy-integration.js --network localNode

# Verify deployment health
npx hardhat run scripts/verify-pvm-deployment.js health --network localNode

# Deploy test NFT contract
npx hardhat run scripts/deploy-test-nft.js --network localNode
```

### 2. Test Full Workflow

```bash
# Run complete end-to-end test
npx hardhat run scripts/test-full-workflow.js --network localNode
```

### 3. Monitor System

```bash
# Monitor system for 5 minutes
npx hardhat run scripts/verify-pvm-deployment.js monitor 5 --network localNode
```

## 📋 Workflow Example

The complete Softlaw workflow in action:

```
1. 💰 SLAW Distribution → Users get SLAW tokens
2. 🎨 NFT Minting → Create copyright NFTs
3. 🔄 NFT Wrapping → Convert NFT to ERC20 tokens
4. 🌊 Liquidity Pool → Create SLAW + Wrapped IP pool
5. 🏪 Marketplace → List NFTs and tokens for sale
6. 💸 Trading → Make offers and complete sales
7. 💰 Payouts → Claim earnings via withdrawal pattern
```

## 🏗️ System Components

### SLAWToken (ERC20)

Native ecosystem currency with:
- Role-based minting (max supply protected)
- Withdrawal pattern for PVM safety
- Treasury integration
- Batch operations for efficiency

```solidity
// Mint tokens with reason tracking
await slawToken.mint(recipient, amount, "ECOSYSTEM_INCENTIVE");

// Schedule withdrawal (no direct transfers)
await slawToken.scheduleWithdrawal(user, amount);
await slawToken.processWithdrawal(); // User claims
```

### TreasuryCore

Central hub for fees and payments:
- Registration and licensing fees
- Marketplace transaction fees
- Revenue sharing (70% creator, 30% protocol)
- Withdrawal pattern for all payouts

```solidity
// Process registration payment
await treasuryCore.processRegistrationPayment(user, nftId);

// Process license with revenue sharing
await treasuryCore.processLicensePayment(licensor, licensee, licenseId, customAmount);

// Claim accumulated earnings
await treasuryCore.claimPayout();
```

### WrappedIPManager

Convert NFTs to fungible tokens:
- Individual ERC20 contracts per wrapped NFT
- Creator verification and metadata
- Unwrapping support (burn tokens → get NFT back)
- Supported contract management

```solidity
// Wrap NFT to ERC20 tokens
const tokenAddress = await wrappedIPManager.wrapIP(
    nftContract, nftId, totalSupply, pricePerToken,
    "My Song Token", "MST", "metadata"
);

// Unwrap (requires all tokens)
await wrappedIPManager.unwrapIP(ipId);
```

### LiquidityManager

Simplified AMM for IP tokens:
- Custom lightweight LP pairs
- SLAW + Wrapped IP pools
- Uniswap V2-style constant product formula
- Pool creation and management

```solidity
// Create liquidity pool
const pairAddress = await liquidityManager.createPool(
    wrappedTokenAddress, slawAmount, ipTokenAmount
);

// Add/remove liquidity
await liquidityManager.addLiquidity(wrappedToken, slawAmount, ipAmount);
await liquidityManager.removeLiquidity(wrappedToken, lpAmount);
```

### MarketplaceCore

Trading platform for NFTs and tokens:
- Direct sales and offer system
- Fee integration with treasury
- Batch operations support
- Withdrawal pattern for proceeds

```solidity
// Create NFT listing
await marketplace.createNFTListing(nftContract, tokenId, price, duration, allowOffers);

// Make offer
await marketplace.makeOffer(listingId, offerAmount, duration);

// Accept offer
await marketplace.acceptOffer(offerId);
```

## 🛠️ Development

### Local Development

```bash
# Start local PVM node
npx hardhat node --network hardhat

# Deploy contracts (new terminal)
npx hardhat run scripts/deploy-integration.js --network localNode

# Run tests
npx hardhat test test/integration/ --network localNode
```

### Testnet Deployment

```bash
# Set up environment
echo "AH_PRIV_KEY=your_private_key_here" >> .env

# Deploy to Passet Hub testnet
npx hardhat run scripts/deploy-integration.js --network passetHub

# Verify deployment
npx hardhat run scripts/verify-pvm-deployment.js verify --network passetHub
```

## 📊 System Metrics

Monitor system health and usage:

```bash
# Get comprehensive system status
npx hardhat run scripts/verify-pvm-deployment.js verify --network localNode
```

**Key Metrics Tracked:**
- 💰 Total fees collected
- 🎨 Wrapped IPs created
- 🌊 Liquidity pools active
- 🏪 Marketplace volume
- 👥 User engagement

## 🔧 Configuration

### Supported Networks

- **hardhat** - Local development with PVM
- **localNode** - Local PVM node
- **passetHub** - Testnet deployment

### Contract Addresses

After deployment, addresses are saved to:
- `deployments/contract-addresses-{network}.json`
- `deployments/integration-deployment-{network}.json`

### Fee Structure

- **Registration**: 100 SLAW
- **Licensing Base**: 50 SLAW + custom amount
- **Marketplace**: 2.5% of sale price
- **Revenue Split**: 70% creator, 30% protocol

## 🧪 Testing

### Integration Tests

```bash
# Test individual components
npx hardhat test test/integration/SLAWToken.test.js
npx hardhat test test/integration/TreasuryCore.test.js
npx hardhat test test/integration/WrappedIPManager.test.js

# Test full system integration
npx hardhat test test/integration/FullSystem.test.js
```

### End-to-End Testing

```bash
# Complete workflow test
npx hardhat run scripts/test-full-workflow.js --network localNode
```

## 🚨 Troubleshooting

### Common Issues

**Stack too deep errors:**
- ✅ Fixed with `viaIR: true` in hardhat.config.js
- ✅ Modular architecture reduces complexity

**Gas estimation failures:**
- ✅ Increased gas limits for PVM
- ✅ Withdrawal patterns prevent gas issues

**Memory constraints:**
- ✅ Batch operations limited to safe sizes
- ✅ Optimized storage layouts

**Compilation warnings:**
- ✅ No .send/.transfer usage
- ✅ No ecrecover dependencies
- ✅ EIP-1271 ready for signature verification

### Health Check

```bash
# Basic health check
npx hardhat run scripts/verify-pvm-deployment.js health --network localNode

# Full verification
npx hardhat run scripts/verify-pvm-deployment.js verify --network localNode
```

## 📚 Documentation

### Contract Documentation

Each contract includes comprehensive NatSpec documentation:
- Function parameters and return values
- Usage examples and integration patterns
- Security considerations and best practices

### Integration Examples

See the test scripts for complete integration examples:
- [Deploy Integration](./scripts/deploy-integration.js)
- [Full Workflow Test](./scripts/test-full-workflow.js)
- [Test NFT Deployment](./scripts/deploy-test-nft.js)

## 🔐 Security

### Access Control

- **Role-based permissions** for all administrative functions
- **Multi-signature support** ready for production
- **Pausable contracts** for emergency stops
- **Withdrawal patterns** prevent reentrancy attacks

### Best Practices

- ✅ ReentrancyGuard on all state-changing functions
- ✅ Access control on administrative functions
- ✅ Input validation and bounds checking
- ✅ Event emission for transparency
- ✅ Emergency functions for recovery

## 🎯 Production Checklist

Before mainnet deployment:

- [ ] **Security audit** completed
- [ ] **Multisig setup** for admin roles
- [ ] **Fee collector** address configured
- [ ] **Supported contracts** whitelist updated
- [ ] **Emergency procedures** documented
- [ ] **Monitoring systems** deployed
- [ ] **User documentation** completed

## 🤝 Contributing

1. Create feature branch from `integrations`
2. Follow PVM optimization guidelines
3. Add comprehensive tests
4. Update documentation
5. Submit PR with detailed description

### PVM Guidelines

When developing for PVM:
- Use `viaIR: true` in compiler settings
- Avoid `.send()` and `.transfer()` calls
- Implement withdrawal patterns
- Respect memory limits in loops/arrays
- Test with actual PVM node

## 📝 License

MIT License - See [LICENSE](./LICENSE) file for details.

## 🔗 Links

- [Polkadot Contracts Documentation](https://contracts.polkadot.io)
- [Revive Compiler Guide](https://contracts.polkadot.io/revive_compiler/)
- [PVM Architecture](https://contracts.polkadot.io/revive_compiler/architecture)
- [Known Issues](https://contracts.polkadot.io/known_issues/)

---

**Built with ❤️ for the Polkadot ecosystem**

Ready to revolutionize copyright management with PVM-optimized smart contracts! 🚀
