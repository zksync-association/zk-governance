# ZkTokenV2 Deployment – Stage Proofs (chain 499)

## Addresses

| Contract | Address |
|---|---|
| ZkTokenV2 proxy (token) | `0xf491d1aE752cad884238933BeD15863C5EE22f12` |
| ZkTokenV2 implementation (active) | `0xE51447a23A8f9064F2241e60c56b1918F63FD89C` |
| ZkTokenV1 implementation (initial) | `0xA627e7C4b0AB0acc5e166C7fe04D5a3295dE1E6d` |
| ProxyAdmin | `0x9380789287AB044A7A316672Fe565d8df35A1d8B` |
| Proxy owner / admin | `0x1454c35737130eB8700e5d0e7a6C44e8aE00aB10` |
| L2NativeTokenVault (predeploy) | `0x0000000000000000000000000000000000010004` |

## Token details

| Property | Value |
|---|---|
| Name | ZKsync |
| Symbol | ZK |
| Decimals | 18 |
| Total supply | 1 000 000 ZK |
| assetId (on L2NativeTokenVault) | `0xd7912bfd25000ee1b3355167866f960a61787b79cd2c7e791036fe6e85a73823` |

## Roles held by proxy owner

| Role | Identifier |
|---|---|
| `DEFAULT_ADMIN_ROLE` | `0x0000000000000000000000000000000000000000000000000000000000000000` |
| `MINTER_ADMIN_ROLE` | `keccak256("MINTER_ADMIN_ROLE")` |
| `BURNER_ADMIN_ROLE` | `keccak256("BURNER_ADMIN_ROLE")` |
| `MINTER_ROLE` | `keccak256("MINTER_ROLE")` |
| `BURNER_ROLE` | `keccak256("BURNER_ROLE")` |

## Verification IDs (stage-proofs explorer)

| Contract | Verification ID |
|---|---|
| ZkTokenV1 (standalone, step 1) | 7 |
| ZkTokenV2 (standalone, step 3) | 8 |
| ZkTokenV2 (active impl, step 4) | 9 |
| TransparentUpgradeableProxy | 11 |
| ProxyAdmin | 12 |
| ZkTokenV1 (proxy's initial impl) | 13 |

Explorer: `https://dev-api-explorer.era-stage-proofs.zksync.dev`

## Verifying the deployment

Run `CheckZkTokenState.ts` to verify that the proxy, implementation, and ProxyAdmin have the correct bytecode, that `initializeV2` was called, that the governance owner holds all roles, and that the deployer holds none:

```bash
ZK_TOKEN_PROXY=0xf491d1aE752cad884238933BeD15863C5EE22f12 \
L2_RPC=<stage-proofs-rpc-url> \
EXPECTED_ROLE_HOLDERS=0x1454c35737130eB8700e5d0e7a6C44e8aE00aB10 \
EXPECTED_NO_ROLES=0xD742604A657A114ca6d59b4B0eA541ced7Bd9413 \
  npx hardhat run script/CheckZkTokenState.ts --network stageProofs
```

Expected output: `✅  All checks passed.`

## Minting ZK tokens

Use `MintZkToken.ts` to mint additional ZK to any address. The caller must hold `MINTER_ROLE` on the proxy.

```bash
OWNER_PRIVATE_KEY=<private-key-with-MINTER_ROLE> \
ZK_TOKEN_PROXY=0xf491d1aE752cad884238933BeD15863C5EE22f12 \
MINT_TO=<recipient-address> \
MINT_AMOUNT=<amount-in-ZK> \
L2_RPC=<stage-proofs-rpc-url> \
  npx hardhat run script/MintZkToken.ts --network stageProofs
```

The script pre-flight checks that the caller actually holds `MINTER_ROLE` and prints the recipient balance before and after.

## Depositing ETH from Sepolia to Stage Proofs

Use `DepositEthToL2.ts` to bridge ETH from Sepolia L1 to the same wallet address on Stage Proofs (chain 499).

```bash
PRIVATE_KEY=<private-key> \
DEPOSIT_AMOUNT=<amount-in-ETH> \
L1_RPC=<sepolia-rpc-url> \
L2_RPC=<stage-proofs-rpc-url> \
  npx hardhat run script/DepositEthToL2.ts --network stageProofs
```

The script calls `Bridgehub.requestL2TransactionDirect` (the universal path for ETH / base-token deposits). It waits for L1 confirmation and then for L2 block inclusion (~minutes).

> **Note:** Use a non-rate-limited Sepolia RPC. The Tenderly public gateway will 429 on the multiple sequential calls. A reliable public alternative: `https://ethereum-sepolia-rpc.publicnode.com`

## Withdrawing ZK tokens from Stage Proofs to Sepolia

### Step 1 – initiate the withdrawal on L2

```bash
COMMAND=withdraw \
L2_WALLET_PRIVATE_KEY=<private-key> \
ZK_TOKEN_ADDRESS=0xf491d1aE752cad884238933BeD15863C5EE22f12 \
WITHDRAW_AMOUNT=<amount-in-ZK> \
L1_RECEIVER=<sepolia-address> \
L2_RPC=<stage-proofs-rpc-url> \
L1_RPC=<sepolia-rpc-url> \
  npx hardhat run script/WithdrawZkToken.ts --network stageProofs
```

`L1_RECEIVER` defaults to the L2 wallet address if omitted. Copy the printed `WITHDRAWAL_TX_HASH` for step 2.

### Step 2 – finalise the withdrawal on Sepolia

Finalisation can only be submitted after the ZKsync proof window has elapsed (~1 h on Sepolia testnet). The script prints a clear message if the proof is not yet available — re-run after the window.

```bash
COMMAND=finalize \
L2_WALLET_PRIVATE_KEY=<private-key> \
L1_WALLET_PRIVATE_KEY=<private-key> \
WITHDRAWAL_TX_HASH=<hash-from-step-1> \
L2_RPC=<stage-proofs-rpc-url> \
L1_RPC=<sepolia-rpc-url> \
  npx hardhat run script/WithdrawZkToken.ts --network stageProofs
```

`L1_WALLET_PRIVATE_KEY` is the wallet that pays for L1 finalisation gas; it can be the same as `L2_WALLET_PRIVATE_KEY`.

## Test withdrawal record

| Field | Value |
|---|---|
| L2 withdrawal tx | `0xe70afeac4fce59f17d596081470c36d4b4b3732a202a093cc6019a9fd6463615` |
| Amount | 1 ZK |
| L2 block | 376002 |
