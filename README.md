# ZK

## Development

### Requirements

This repository uses the [Foundry](https://book.getfoundry.sh/) development framework for testing. Install Foundry using these [instructions](https://book.getfoundry.sh/getting-started/installation).

This repository uses the [Hardhat](https://hardhat.org/docs) development framework, with the relevant [zkSync Era plugins](https://docs.zksync.io/build/tooling/hardhat/getting-started.html) for managing deployments, including upgradeable deployments of the token contract.

We use [Volta](https://docs.volta.sh/guide/) to ensure a consistent npm environment between developers. Install volta using these [instructions](https://docs.volta.sh/guide/getting-started).

### Setup

Clone the repo:

```
git clone git@github.com:matter-labs/zk.git
cd zk
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

### Scripts

This repo contains deployment scripts for each of the contracts, including proper deployment of the token contract using the transparent proxy pattern via the [hardhat-zksync-upgradable](https://docs.zksync.io/build/tooling/hardhat/hardhat-zksync-upgradable.html) plugin.

To test the deploy scripts locally, first start a local zkSync node:

```
npm run local-node
```

Then execute the deploy script of your choice, for example:

```
npm run deploy script/DeployZkTokenV1.ts
```

The `deploy` command will first build the contracts using zksolc to make sure the latest version of the contracts—rather than build artifacts from a previous compilation—are being deployed.

Running the deploy scripts will produce deployment logs locally in either the `.upgradable/` subdirectory (for upgradeable contracts) or the `deployments-zk/` (for non-upgradeable contracts). These should *not* be checked in for local test deployments, but *should* be checked in for real deployments, either to testnets or to production.

Each deploy scripts hardcodes deployment parameters as simple constants at the top of each file. Before executing a real deployment, be sure to set these values as appropriate for the environment you're deploying to.

## License

ZK is available under the [MIT](LICENSE.txt) license.

Copyright (c) 2024 Matter Labs