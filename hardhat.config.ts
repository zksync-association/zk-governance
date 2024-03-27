import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-node";
import "@matterlabs/hardhat-zksync-upgradable";

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
      url: "http://localhost:8011",
    },
  },
  defaultNetwork: "zkSyncLocal",
};

export default config;
