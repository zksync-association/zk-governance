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

#### Deploying ZkTokenV2 from scratch

`DeployZkTokenV2FromScratch.ts` deploys ZkTokenV2 behind a Transparent Upgradeable Proxy in a single run. It deploys the V1 implementation, initialises the proxy, upgrades to V2, grants all access-control roles to the hardcoded `PROXY_OWNER`, and registers the token on the L2NativeTokenVault so it can be bridged back to L1.

The script is resumable: it persists completed steps to `script/.deploy-state.json` and skips them on re-runs, so it is safe to interrupt and restart.

Required env vars:
- `DEPLOYER_PRIVATE_KEY` – private key of the deploying wallet
- `L2_RPC` – ZKsync Era JSON-RPC endpoint

```bash
L2_RPC=<l2-rpc-url> \
  npx hardhat run script/DeployZkTokenV2FromScratch.ts --network <network>
```

#### Withdrawing ZK tokens from L2 to L1

`WithdrawZkToken.ts` supports two commands that together complete an L2→L1 bridge withdrawal.

**Step 1 – initiate the withdrawal on L2**

```bash
COMMAND=withdraw \
L2_WALLET_PRIVATE_KEY=<private-key> \
ZK_TOKEN_ADDRESS=<proxy-address> \
WITHDRAW_AMOUNT=<amount>          \
L1_RECEIVER=<l1-address>          \
L2_RPC=<l2-rpc-url>               \
L1_RPC=<l1-rpc-url>               \
  npx hardhat run script/WithdrawZkToken.ts --network <network>
```

`L1_RECEIVER` defaults to the L2 wallet address if omitted. The command prints a `WITHDRAWAL_TX_HASH` to use in step 2.

**Step 2 – finalise the withdrawal on L1**

Finalisation can only be submitted after the ZKsync proof window has elapsed (~24 h on mainnet, ~1 h on Sepolia testnet). Re-run the command after that window; it will print a clear message if the proof is not yet available.

```bash
COMMAND=finalize \
L2_WALLET_PRIVATE_KEY=<private-key> \
L1_WALLET_PRIVATE_KEY=<private-key> \
WITHDRAWAL_TX_HASH=<hash-from-step-1> \
L2_RPC=<l2-rpc-url>                   \
L1_RPC=<l1-rpc-url>                   \
  npx hardhat run script/WithdrawZkToken.ts --network <network>
```

`L1_WALLET_PRIVATE_KEY` is the wallet that pays for the L1 finalisation gas. It can be the same key as `L2_WALLET_PRIVATE_KEY`.
