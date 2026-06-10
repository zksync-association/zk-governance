import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-node";
import "@matterlabs/hardhat-zksync-upgradable";
import "@matterlabs/hardhat-zksync-verify";

import * as dotenv from 'dotenv';
dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  zksolc: {
    version: "1.4.0",
    settings: {
      optimizer: {
        enabled: true,
      },
    },
  },
  paths: {
    "sources": "./src",
  },
  networks: {
    hardhat: {
      zksync: false,
    },
    ethNetwork: {
      zksync: false,
      url: "http://localhost:8545",
    },
    zkSyncLocal: {
      zksync: true,
      ethNetwork: "ethNetwork",
      url: process.env.ZK_LOCAL_NETWORK_URL ? process.env.ZK_LOCAL_NETWORK_URL : "http://0.0.0.0:8011",
    },
    mainnet: {
      zksync: false,
      url: "https://eth-mainnet.g.alchemy.com/v2/SECRET",
    },
    zkSyncEra: {
      zksync: true,
      ethNetwork: "mainnet",
      url: "https://zksync-mainnet.g.alchemy.com/v2/SECRET",
    },
    zkSyncTestnet: {
      zksync: true,
      ethNetwork: "sepolia",
      url: "https://sepolia.era.zksync.dev",
      verifyURL: "https://explorer.sepolia.era.zksync.dev/contract_verification",
    },
    // The "ZKsync Era testnet" chain (chainId 301), anchored on Sepolia L1. RPC and verify
    // URLs are overridable via env so the redeploy script can target any compatible chain.
    eraTestnet: {
      zksync: true,
      ethNetwork: process.env.L1_RPC || "https://ethereum-sepolia-rpc.publicnode.com",
      url: process.env.L2_RPC || "https://rpc.zksync-era-testnet.zksync.dev/",
      verifyURL:
        process.env.L2_VERIFY_URL ||
        "https://rpc.zksync-era-testnet.zksync.dev/contract_verification",
    },
  },
  // Etherscan-compatible verification for the Era testnet block explorer (the dedicated
  // /contract_verification endpoint is not exposed; the /api verifysourcecode flow is).
  etherscan: {
    apiKey: {
      eraTestnet: process.env.L2_EXPLORER_API_KEY || "no-key-required",
    },
    customChains: [
      {
        network: "eraTestnet",
        chainId: 301,
        urls: {
          apiURL: "https://block-explorer-api.zksync-era-testnet.zksync.dev/api",
          browserURL: "https://block-explorer.zksync-era-testnet.zksync.dev",
        },
      },
    ],
  },
  defaultNetwork: "zkSyncLocal",
};

export default config;
