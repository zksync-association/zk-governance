# ZkTokenV2 Deployment – Stage Proofs (chain 499)

## Addresses

| Contract | Address |
|---|---|
| ZkTokenV2 proxy (token) | `0xf491d1aE752cad884238933BeD15863C5EE22f12` |
| ZkTokenV2 implementation (active) | `0xE51447a23A8f9064F2241e60c56b1918F63FD89C` |
| ZkTokenV1 implementation (initial) | `0xA627e7C4b0AB0acc5e166C7fe04D5a3295dE1E6d` |
| ProxyAdmin | `0x9380789287AB044A7A316672Fe565d8df35A1d8B` |
| Proxy owner / admin | `0xD742604A657A114ca6d59b4B0eA541ced7Bd9413` |
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

Run `CheckZkTokenState.ts` to verify that the proxy, implementation, and ProxyAdmin have the correct bytecode, that `initializeV2` was called, and that the proxy owner holds all expected roles:

```bash
ZK_TOKEN_PROXY=0xf491d1aE752cad884238933BeD15863C5EE22f12 \
L2_RPC=<stage-proofs-rpc-url> \
  npx hardhat run script/CheckZkTokenState.ts --network stageProofs
```

Expected output: `✅  All checks passed.`

## Test withdrawal

| Field | Value |
|---|---|
| L2 withdrawal tx | `0xe70afeac4fce59f17d596081470c36d4b4b3732a202a093cc6019a9fd6463615` |
| Amount | 1 ZK |
| L2 block | 376002 |
