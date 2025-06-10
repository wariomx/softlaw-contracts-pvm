require("@nomicfoundation/hardhat-toolbox");
require("@parity/hardhat-polkadot");

require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      // 🔥 CRITICAL for PVM: Enable viaIR to avoid "Stack too deep" errors
      viaIR: true,
      // Memory optimization for PVM 64kb limit
      metadata: {
        useLiteralContent: true,
      },
    },
  },
  resolc: {
    compilerSource: "npm",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      // PVM-specific optimizations
      viaIR: true,
      metadata: {
        useLiteralContent: true,
      },
    },
  },
  networks: {
    hardhat: {
      polkavm: true,
      // Increased gas limits for PVM
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 120000,
      nodeConfig: {
        nodeBinaryPath: "./bin/substrate-node",
        rpcPort: 8000,
        dev: true,
      },
      adapterConfig: {
        adapterBinaryPath: "./bin/eth-rpc",
        dev: true,
      },
    },
    localNode: {
      polkavm: true,
      url: `http://127.0.0.1:8545`,
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 120000,
      accounts: [
        process.env.LOCAL_PRIV_KEY ??
          "0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133",
        process.env.AH_PRIV_KEY ?? "",
      ],
    },
    passetHub: {
      polkavm: true,
      url: "https://testnet-passet-hub-eth-rpc.polkadot.io",
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 180000, // 3 minutes for testnet
      accounts: [
        process.env.AH_PRIV_KEY ?? "",
        process.env.LOCAL_PRIV_KEY ??
          "0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133",
      ],
    },
  },
  // PVM-specific compiler optimizations
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 120000, // 2 minutes for PVM tests
  },
};
