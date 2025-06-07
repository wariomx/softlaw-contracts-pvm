# Softlaw Contracts PVM

## Overview

Softlaw Contracts PVM is a comprehensive legal technology platform built on Polkadot Virtual Machine (PVM). This project provides a complete ecosystem of smart contracts designed for legal services, intellectual property management, dispute resolution, and decentralized autonomous organization (DAO) governance in the legal sector.

## 🏗️ Architecture

### Core Modules

- **ADR (Alternative Dispute Resolution)**: Arbitration, mediation, and dispute resolution systems
- **Licenses**: Copyright and patent management contracts  
- **Governance**: DAO governance system for legal entities
- **Attestations**: Legal certification and verification system
- **IP Liquidity**: Intellectual property tokenization and trading
- **Marketplace**: Legal services and IP trading platform
- **Registries**: Legal document and entity registries
- **Memberships**: Professional membership management
- **Treasury**: Financial management for legal DAOs

## Prerequisites

Ensure that you have substrate-node, eth-rpc and local resolc binaries on your local machine. If not, follow these instructions to install them:

```bash
git clone https://github.com/paritytech/polkadot-sdk
cd polkadot-sdk
cargo build --bin substrate-node --release
cargo build -p pallet-revive-eth-rpc --bin eth-rpc --release
```

Once the build is complete, you will find both binaries in the `./target/release` directory. Copy and paste them into the `./bin` directory of this repository.

## How to Initialize

```bash
git clone https://github.com/wariomx/softlaw-contracts-pvm.git
cd softlaw-contracts-pvm
npm install
```

Open the `hardhat.config.js` file and update the following fields under networks -> hardhat:

```javascript
nodeBinaryPath: Set this to the local path of your substrate-node binary.
adapterBinaryPath: Set this to the local path of your eth-rpc binary.
```

## How to Test

```bash
# For Local node 
npx hardhat test --network localNode

# For Westend Hub
npx hardhat test --network westendHub

# For Passet Hub
npx hardhat test --network passetHub
```

## How to Deploy

```bash
# Deploy to local network
npx hardhat run scripts/deploy.js --network localNode

# Deploy to Westend Hub
npx hardhat run scripts/deploy.js --network westendHub
```

## Contract Categories

### 🔨 ADR (Alternative Dispute Resolution)
- **Arbitration.sol**: Handles arbitration processes
- **Mediation.sol**: Manages mediation cases
- **SoftlawDisputes.sol**: Specialized dispute resolution for legal matters

### 📜 Licenses
- **LCopyrights.sol**: Copyright management and licensing
- **LPatents.sol**: Patent registration and licensing

### 🏛️ Governance
- **DAOGovernor.sol**: Main governance contract for legal DAOs
- **DAOGovernorHelpers.sol**: Helper functions for governance operations

### 🏪 Additional Modules
- **Attestations**: Legal document verification
- **IP-liquidity**: Intellectual property tokenization
- **Marketplace**: Legal services trading platform
- **Registries**: Legal entity and document registries
- **Memberships**: Professional association management
- **Treasury**: DAO treasury management

## Networks

- **Local Node**: For development and testing
- **Westend Hub**: Polkadot testnet
- **Passet Hub**: Asset Hub testnet

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the ISC License.

## Contact

For questions or support, please open an issue in the repository.
