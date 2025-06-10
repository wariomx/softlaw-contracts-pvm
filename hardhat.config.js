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
        runs: 200, // Optimized for PVM
      },
      // 🔥 CRITICAL for PVM: Enable viaIR to avoid "Stack too deep" errors
      viaIR: true,
      // Memory optimization for PVM 64kb limit
      metadata: {
        useLiteralContent: true,
        bytecodeHash: "none", // Reduces contract size
      },
      // Additional PVM optimizations
      evmVersion: "london", // Use older EVM version for better compatibility
      outputSelection: {
        "*": {
          "*": [
            "abi",
            "evm.bytecode",
            "evm.deployedBytecode",
            "evm.methodIdentifiers",
            "metadata"
          ],
          "": ["ast"]
        }
      }
    },
  },
  // Revive compiler configuration for PVM
  resolc: {
    compilerSource: "npm",
    version: "latest", // Use latest resolv compiler
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yul: true,
          yulDetails: {
            stackAllocation: true,
            optimizerSteps: "dhfoDgvulfnTUtnIf"
          }
        }
      },
      // PVM-specific optimizations
      viaIR: true,
      metadata: {
        useLiteralContent: true,
        bytecodeHash: "none"
      },
      // Memory safety for PVM
      memoryModel: "safe",
      stackAllocation: true,
      // Reduce contract size for PVM constraints
      remappings: [
        "@openzeppelin/=node_modules/@openzeppelin/"
      ]
    },
  },
  networks: {
    hardhat: {
      polkavm: true,
      // Optimized gas settings for PVM
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 180000, // 3 minutes
      // Memory settings for PVM
      allowUnlimitedContractSize: false,
      blockGasLimit: 30000000,
      nodeConfig: {
        nodeBinaryPath: "./bin/substrate-node",
        rpcPort: 8000,
        dev: true,
        // PVM-specific node configuration
        wasmHeapPages: 64, // 4MB heap for PVM
        executionStrategy: "native"
      },
      adapterConfig: {
        adapterBinaryPath: "./bin/eth-rpc",
        dev: true,
        // Adapter optimizations
        maxRequestSize: "1mb",
        maxResponseSize: "1mb"
      },
    },
    localNode: {
      polkavm: true,
      url: `http://127.0.0.1:8545`,
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 180000,
      accounts: [
        process.env.LOCAL_PRIV_KEY ??
          "0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133",
        process.env.AH_PRIV_KEY ?? "",
      ],
      // PVM network optimizations
      allowUnlimitedContractSize: false,
      blockGasLimit: 30000000,
    },
    passetHub: {
      polkavm: true,
      url: "https://testnet-passet-hub-eth-rpc.polkadot.io",
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 300000, // 5 minutes for testnet
      accounts: [
        process.env.AH_PRIV_KEY ?? "",
        process.env.LOCAL_PRIV_KEY ??
          "0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133",
      ],
      // Testnet optimizations
      allowUnlimitedContractSize: false,
      blockGasLimit: 30000000,
    },
    // Production Polkadot networks
    polkadot: {
      polkavm: true,
      url: process.env.POLKADOT_RPC_URL || "https://rpc.polkadot.io",
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 300000,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      allowUnlimitedContractSize: false,
      blockGasLimit: 30000000,
    },
    kusama: {
      polkavm: true,
      url: process.env.KUSAMA_RPC_URL || "https://rpc.kusama.io",
      gas: 30000000,
      gasPrice: 1000000000,
      timeout: 300000,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      allowUnlimitedContractSize: false,
      blockGasLimit: 30000000,
    }
  },
  // PVM-specific compiler optimizations
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 300000, // 5 minutes for PVM tests
    slow: 30000, // 30 seconds
    bail: false, // Continue on test failures
  },
  // Gas reporter configuration for PVM
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    excludeContracts: [],
    src: "./contracts",
    // PVM-specific gas reporting
    maxMethodDiff: 10,
    maxDeploymentDiff: 200,
    showTimeSpent: true,
    showMethodSig: true,
  },
  // Contract size optimization
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  // PVM-specific linting and formatting
  solhint: {
    extends: "solhint:recommended",
    rules: {
      "compiler-version": ["error", "^0.8.0"],
      "func-visibility": ["warn", { "ignoreConstructors": true }],
      // PVM-specific rules
      "max-line-length": ["error", 120],
      "bracket-align": "error",
      "no-unused-vars": "error",
      "gas-consumption": "warn"
    }
  },
  // TypeChain configuration for type-safe contract interactions
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
    alwaysGenerateOverloads: false,
    discriminateTypes: true,
  },
  // Deployment verification
  etherscan: {
    apiKey: {
      polkadot: process.env.POLKADOT_API_KEY || "",
      kusama: process.env.KUSAMA_API_KEY || "",
    },
    customChains: [
      {
        network: "polkadot",
        chainId: 1000,
        urls: {
          apiURL: "https://api.polkadot.subscan.io/api/scan",
          browserURL: "https://polkadot.subscan.io"
        }
      }
    ]
  },
  // Additional PVM optimizations
  preprocess: {
    eachLine: (hre) => ({
      transform: (line) => {
        // Remove debug statements in production
        if (hre.network.name === "polkadot" || hre.network.name === "kusama") {
          if (line.includes("console.log") || line.includes("require(\"hardhat/console.sol\")")) {
            return "";
          }
        }
        return line;
      },
    }),
  },
  // Memory and performance optimizations
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY,
    }
  },
  // Custom tasks for PVM deployment
  tasks: {
    // Add custom deployment scripts here
  }
};
