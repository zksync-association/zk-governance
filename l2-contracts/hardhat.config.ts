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
  },
  defaultNetwork: "zkSyncLocal",
};

export default config;
