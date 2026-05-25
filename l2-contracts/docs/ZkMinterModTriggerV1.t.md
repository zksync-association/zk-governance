# ZkMinterModTriggerV1 Test Suite (`ZkMinterModTriggerV1.t.sol`)

## Overview
This test suite, written using Foundry, verifies the functionality of the `ZkMinterModTriggerV1` contract. It covers its core logic, administrative functions, and interactions with mock and example contracts, including `ZkMinterModTargetExampleV1`, `MockERC20`, `ZkCappedMinterV2`, and `MerkleDropFactory`.

## Test Contracts and Setup

### `MockERC20`
A simple ERC20 token implementation for testing purposes, allowing minting, approving, and transferring tokens.

### `ZkMinterModTriggerV1Test` (Base Contract)
This contract sets up the common testing environment:
- Deploys `MockERC20` (as `token`).
- Deploys `ZkMinterModTargetExampleV1` (as `target`), initialized with `address(token)`.
- Deploys `ZkMinterModTriggerV1` (as `trigger`) configured with arrays for a two-call sequence:
    1. **Target 0**: `token` contract. Function: `approve(address spender, uint256 amount)`. CallData: `spender = address(target)`, `amount = 500 ether`.
    2. **Target 1**: `target` contract. Function: `executeTransferAndLogic(uint256 amount)`. CallData: `amount = 500 ether`.
- Deploys `ZkCappedMinterV2` (as `cappedMinter`) and configures it:
    - Sets the `trigger` contract as a minter on `cappedMinter` by granting `MINTER_ROLE`.
    - Sets `cappedMinter` as the minter for the `trigger` contract.
- Defines a `user` address for emulating external calls.

### `MintFromZkCappedMinter` (Inherits `ZkMinterModTriggerV1Test`)
This contract focuses on tests specifically involving the minting process from `ZkCappedMinterV2` via `ZkMinterModTriggerV1`.

### `MerkleTargetTest`
This contract tests the scenario where `ZkMinterModTriggerV1` is configured to interact with a `MerkleDropFactory` contract. 
*(Note: The setup details for `ZkMinterModTriggerV1` within this test might need updating in the test code if it's still using a single-target configuration, to align with the latest multi-call `ZkMinterModTriggerV1` contract.)*
It generally aims to set up:
- `MockERC20`
- `MerkleDropFactory` (as one of the `targets`).
- `ZkMinterModTriggerV1` (as `caller`) configured with an array-based setup to ultimately call `addMerkleTree(...)` on the `MerkleDropFactory`, potentially including an `approve` call as part of the sequence if the `MerkleDropFactory` pulls tokens.
- `ZkCappedMinterV2` (as `cappedMinter`), with the `caller` granted `MINTER_ROLE`.

## Key Test Scenarios

### In `ZkMinterModTriggerV1Test` & `MintFromZkCappedMinter`:
- **`testInitiateCallFullBalance()` / `testMintFromCappedMinterAndInitiateCall()` / `testCallWithCustomCallData()`**: 
    - Verifies that `initiateCall()` successfully mints tokens from `cappedMinter` to the `trigger` contract.
    - Then, the `trigger` executes the configured sequence: 
        1. Calls `approve()` on the `token` contract (allowing `target` to spend tokens held by `trigger`).
        2. Calls `executeTransferAndLogic()` on the `target` (`ZkMinterModTargetExampleV1`), which then uses `transferFrom` to pull tokens from `trigger`.
    - Checks that tokens are ultimately transferred correctly to the `target` and the `trigger`'s balance is zeroed out.
    - Verifies that the allowance set on the `token` contract is consumed.
    - Confirms event emission (`TransferProcessed` from the `target`).
- **`test_RevertWhen_FunctionCallFailed()`**:
    - Verifies that `initiateCall()` reverts with the message "Function call failed" if any call in the sequence fails. This is tested by configuring the `trigger` with call data that would attempt to use more tokens than the `cappedMinter`'s cap (e.g., trying to approve/transfer 600 ether when cap is 500 ether).

### In `MerkleTargetTest`:
- **`testAddMerkleTreeViaCaller()`**: 
    - Verifies that `initiateCall()` on the `caller` (a `ZkMinterModTriggerV1` instance) successfully mints tokens, approves the `MerkleDropFactory` (`target`), and calls `addMerkleTree` on it.
    - Checks that the `MerkleDropFactory` has the tokens and the Merkle tree is added.
    - Confirms event emission (`MerkleTreeAdded`).

## Running the Tests
To execute these tests, use the Foundry command line tool:
```bash
forge test --match-path test/ZkMinterModTriggerV1.t.sol -vvv
```

## Test Coverage Highlights
- Core `initiateCall()` logic: minting, approval, and target call.
- Integration with `ZkCappedMinterV2` for minting.
- Interaction with different target contracts (`ZkMinterModTargetExampleV1`, `MerkleDropFactory`).
- Correct handling of call data and function signatures.
- Event emissions.

## Dependencies
- [Forge Standard Library (forge-std)](https://github.com/foundry-rs/forge-std)
- Project's own contracts (`ZkMinterModTriggerV1`, `ZkMinterModTargetExampleV1`, `MerkleDropFactory`, `ZkCappedMinterV2`).
