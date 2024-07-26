# ZK Governance
This project includes Ethereum smart contracts for ZK governance.

## L1 contracts

### Development

#### Requirements

This repository uses the [Foundry](https://book.getfoundry.sh/) development framework for testing. Install Foundry using these [instructions](https://book.getfoundry.sh/getting-started/installation).

#### Setup

Clone the repo:

```
git clone git@github.com:ZKsync-Association/zk-governance.git
cd zk-governance/l1-contracts
```

Build the contracts, with both `solc`:

```
forge compile
```

Run the tests (Foundry only):

```
forge test
```

## L2 contracts

### Development

#### Requirements

This repository uses the [Foundry](https://book.getfoundry.sh/) development framework for testing. Install Foundry using these [instructions](https://book.getfoundry.sh/getting-started/installation).

This repository uses the [Hardhat](https://hardhat.org/docs) development framework, with the relevant [zkSync Era plugins](https://docs.zksync.io/build/tooling/hardhat/getting-started.html) for managing deployments, including upgradeable deployments of the token contract.

We use [Volta](https://docs.volta.sh/guide/) to ensure a consistent npm environment between developers. Install volta using these [instructions](https://docs.volta.sh/guide/getting-started).

#### Setup

Clone the repo:

```
git clone git@github.com:ZKsync-Association/zk-governance.git
cd zk-governance/l2-contracts
```

Install the npm dependencies:

```
npm install
```

Build the contracts, with both `solc` and `zksolc`:

```
npm run compile
```

Run the tests (Foundry only):

```
npm test
```

Clean build artifacts, from both `solc` and `zksolc`:

```
npm run clean
```

#### Scripts

This repo contains deployment scripts for each of the contracts, including proper deployment of the token contract using the transparent proxy pattern via the [hardhat-zksync-upgradable](https://docs.zksync.io/build/tooling/hardhat/hardhat-zksync-upgradable.html) plugin.

To test the deploy scripts locally, first start a local zkSync node:

```
npm run local-node
```

Then execute the deploy script of your choice, for example:

```
npm run script -- DeployZkTokenV1.ts
```

The `script` command will first build the contracts using zksolc to make sure the latest version of the contracts—rather than build artifacts from a previous compilation—are being deployed, and then execute the requested script, which is assumed to reside in the `script` subdirectory.

Running the deploy scripts will produce deployment logs locally in either the `.upgradable/` subdirectory (for upgradeable contracts) or the `deployments-zk/` (for non-upgradeable contracts). These should _not_ be checked in for local test deployments, but _should_ be checked in for real deployments, either to testnets or to production.

Each deploy scripts hardcodes deployment parameters as simple constants at the top of each file. Before executing a real deployment, be sure to set these values as appropriate for the environment you're deploying to.

In addition to the deploy scripts, there are also utility scripts for interacting with the deployed contracts, for the purposes of granting roles to accounts, transferring ownership of the token contract, and so on. These scripts are located in the `script` subdirectory, can be run in the same way as the deploy scripts, and also have hardedcoded parameters at the top of each file that should be changed for non-local deployments.
