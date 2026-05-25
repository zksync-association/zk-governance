# MerkleDropFactory.sol

## Overview

`MerkleDropFactory.sol` is a smart contract that implements a factory pattern for creating and managing Merkle tree-based airdrops (merkle-drops). It allows anyone to permissionlessly set up an airdrop for any ERC20 token by providing a Merkle root that defines token allocations. The contract handles the storage of Merkle tree metadata, token deposits, and the verification of withdrawal claims using Merkle proofs.

## Key Features

- **Permissionless Tree Creation**: Anyone can add a new Merkle tree for an airdrop.
- **ERC20 Token Support**: Supports any ERC20 compliant token for distributions.
- **Secure Withdrawals**: Utilizes Merkle proofs to ensure only eligible recipients can claim their allocated tokens.
- **Token Management**: Each tree has its own token balance, preventing interference between different airdrops.
- **Event Emission**: Emits events for key actions such as tree creation, token deposits, and withdrawals, facilitating off-chain tracking.
- **IPFS Integration**: Stores an IPFS hash of the dataset for redundancy and data availability.

## Core Components

### Struct: `MerkleTree`
Represents a single airdrop and stores:
- `merkleRoot` (bytes32): The root hash of the Merkle tree. Leaves are typically `keccak256(abi.encode(address destination, uint256 value))`.
- `ipfsHash` (bytes32): An IPFS hash of the full dataset (e.g., the list of all address-amount pairs).
- `tokenAddress` (address): The ERC20 token being distributed.
- `tokenBalance` (uint): The current balance of tokens deposited for this tree held by the factory contract.
- `spentTokens` (uint): The total amount of tokens already withdrawn from this tree.
- `withdrawn` (mapping bytes32 => bool): Tracks which Merkle leaves (claims) have already been processed to prevent double-spending.

### State Variables
- `numTrees` (uint): The total number of Merkle trees (airdrops) managed by the contract. Tree indices are 1-based.
- `merkleTrees` (mapping uint => MerkleTree): Stores the `MerkleTree` structs, indexed by their tree number.

## Functions

### `addMerkleTree(bytes32 newRoot, bytes32 ipfsHash, address tokenAddress, uint tokenBalance)`
- **Visibility**: `public`
- **Description**: Adds a new Merkle tree (airdrop) to the factory. It initializes the tree's metadata and requires an initial deposit of tokens.
- **Parameters**:
    - `newRoot`: The Merkle root of the distribution.
    - `ipfsHash`: IPFS hash of the airdrop dataset.
    - `tokenAddress`: Address of the ERC20 token for the airdrop.
    - `tokenBalance`: The initial amount of tokens to be deposited into the tree's balance. This amount is transferred from `msg.sender` to the contract.
- **Emits**: `MerkleTreeAdded` upon successful creation and `TokensDeposited` as part of the initial funding.

### `depositTokens(uint treeIndex, uint value)`
- **Visibility**: `public`
- **Description**: Allows anyone to add more funds (tokens) to an existing Merkle tree. This is useful if the initial deposit was insufficient or if the airdrop is to be topped up.
- **Parameters**:
    - `treeIndex`: The index of the Merkle tree to fund.
    - `value`: The amount of tokens to deposit. Transferred from `msg.sender`.
- **Emits**: `TokensDeposited`.
- **Reverts**: `BadTreeIndex` if `treeIndex` is invalid.

### `withdraw(uint treeIndex, address destination, uint value, bytes32[] memory proof)`
- **Visibility**: `public`
- **Description**: Allows a recipient (or anyone on their behalf) to claim their allocated tokens from a specific airdrop tree by providing a valid Merkle proof.
- **Parameters**:
    - `treeIndex`: The index of the Merkle tree.
    - `destination`: The address of the token recipient.
    - `value`: The amount of tokens to be claimed.
    - `proof`: The Merkle proof verifying that the leaf `keccak256(abi.encode(destination, value))` is part of the `merkleRoot` of the specified tree.
- **Emits**: `WithdrawalOccurred`.
- **Reverts**:
    - `BadTreeIndex`: If `treeIndex` is invalid.
    - `LeafAlreadyClaimed`: If this specific claim (leaf) has already been processed.
    - `BadProof`: If the provided Merkle proof is invalid for the given leaf and root.
    - `TokensNotTransferred`: If the token transfer to the destination fails or transfers zero tokens (e.g., due to insufficient contract balance for that tree or issues with the token contract).

### `getWithdrawn(uint treeIndex, bytes32 leaf) external view returns (bool)`
- **Visibility**: `external view`
- **Description**: Checks if a specific Merkle leaf (claim) has already been withdrawn for a given tree.
- **Parameters**:
    - `treeIndex`: The index of the Merkle tree.
    - `leaf`: The Merkle leaf hash to check.
- **Returns**: `true` if withdrawn, `false` otherwise.

## Events

- `WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint value)`: Emitted when tokens are successfully claimed.
- `MerkleTreeAdded(uint indexed treeIndex, address indexed tokenAddress, bytes32 newRoot, bytes32 ipfsHash)`: Emitted when a new airdrop tree is added.
- `TokensDeposited(uint indexed treeIndex, address indexed tokenAddress, uint amount)`: Emitted when tokens are deposited into a tree.

## Errors

- `BadTreeIndex(uint treeIndex)`: Indicates an invalid `treeIndex` was provided.
- `LeafAlreadyClaimed(uint treeIndex, bytes32 leafHash)`: Indicates the specific airdrop claim has already been processed.
- `BadProof(uint treeIndex, bytes32 leaf, bytes32[] proof)`: Indicates the Merkle proof provided is invalid.
- `TokensNotTransferred(uint treeIndex, bytes32 leaf)`: Indicates that the token transfer failed during a withdrawal attempt, or zero tokens were transferred.

## Security Considerations

- **Token Contract Trust**: The security of an individual airdrop relies on the legitimacy of the ERC20 token contract used. A malicious token contract could behave unexpectedly (e.g., reentrancy, though the contract has some guards; or lying about balances).
- **Merkle Root Integrity**: The creator of the Merkle tree is responsible for the correctness of the `merkleRoot` and the underlying data. The factory contract itself does not verify the contents of the tree beyond the proof mechanism.
- **Sufficient Funding**: While tokens are deposited upon tree creation and can be topped up, it's crucial that `tokenBalance` for a tree is sufficient to cover all claims. The contract allows for underfunded trees, where claims might fail if the contract runs out of tokens for that specific tree.
- **Gas Costs**: Merkle proof verification can be gas-intensive, especially for deep trees or long proofs.
- **No Admin Controls**: The factory is permissionless by design. Once a tree is added, it cannot be removed or centrally managed by a single admin, only interacted with via its public functions.
