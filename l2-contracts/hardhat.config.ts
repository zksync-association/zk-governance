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
    // L1 networks – set L1_RPC to your preferred endpoint for the relevant L1.
    sepolia: {
      zksync: false,
      url: process.env.L1_RPC || "https://rpc.sepolia.org",
    },
    mainnet: {
      zksync: false,
      url: process.env.L1_RPC || "https://eth.llamarpc.com",
    },
    // ZKsync Era mainnet – L2_RPC should point to the Era mainnet JSON-RPC.
    zkSyncEra: {
      zksync: true,
      ethNetwork: "mainnet",
      url: process.env.L2_RPC || "https://mainnet.era.zksync.io",
      verifyURL: "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
    // ZKsync Era Sepolia testnet.
    zkSyncTestnet: {
      zksync: true,
      ethNetwork: "sepolia",
      url: process.env.L2_RPC || "https://sepolia.era.zksync.dev",
      verifyURL: "https://explorer.sepolia.era.zksync.dev/contract_verification",
    },
    // ZKsync stage-proofs environment (chain 499, L1 = Sepolia).
    // Set L2_RPC to the stage-proofs RPC endpoint.
    stageProofs: {
      zksync: true,
      ethNetwork: "sepolia",
      url: process.env.L2_RPC || "",
      verifyURL: "https://dev-api-explorer.era-stage-proofs.zksync.dev/contract_verification",
    },
  },
  defaultNetwork: "zkSyncLocal",
};

export default config;
