# ZkMinterModTriggerV1

## Overview
`ZkMinterModTriggerV1.sol` is a trigger contract designed to work with an `IZkCappedMinter` compatible contract (e.g., `ZkCappedMinterV2`) to orchestrate a sequence of operations: minting tokens and then executing one or more arbitrary function calls on specified target contracts. This enables gas-efficient batch operations by combining token minting and multiple function executions in a single transaction.

It can be configured to call any set of target contracts and functions, making it a flexible tool for various on-chain operations that require prior token minting.

## Key Features
- Integrates with `IZkCappedMinter` compatible contracts for controlled token minting.
- Executes arbitrary function calls on one or multiple target contracts in sequence.
- Supports dynamic arrays of target addresses, function signatures, and call data, configurable at deployment and updatable by an admin.
- Admin-controlled configuration for critical parameters.

## Core Components

### State Variables
- `minter` (`IZkCappedMinter`): The `IZkCappedMinter` contract instance responsible for minting tokens. The token type is implicitly defined by this minter.
- `admin` (`address`): The address with administrative privileges to change configurations.
- `targets` (`address[]`): An array of target contract addresses that `ZkMinterModTriggerV1` will call.
- `functionSignatures` (`bytes[]`): An array of 4-byte function selectors corresponding to the functions to be called on the respective `targets`.
- `callDatas` (`bytes[]`): An array of encoded arguments to be passed to the respective target functions. Each `callDatas[i]` is appended to `functionSignatures[i]` to form the complete calldata for `targets[i]`.

## Functions

### `constructor(address _admin, address[] memory _targetAddresses, bytes[] memory _functionSignatures, bytes[] memory _callDatas)`
Initializes the trigger contract. Requires `_admin` address and parallel arrays for `_targetAddresses`, `_functionSignatures`, and `_callDatas`. The lengths of these arrays must match.

### `setMinter(address _minter) external adminOnly`
Updates the `minter` contract address. Only callable by the `admin`.

### `setTargets(address[] calldata _targets) external adminOnly`
Updates the array of `targets` contract addresses. Only callable by the `admin`.

### `setAdmin(address _admin) external adminOnly`
Transfers admin privileges to a new `_admin` address. Only callable by the current `admin`.

### `setFunctionSignatures(bytes[] calldata _functionSignatures) external adminOnly`
Updates the array of `functionSignatures`. The length must be consistent with other call parameter arrays. Only callable by the `admin`.

### `setCallDatas(bytes[] calldata _callDatas) external adminOnly`
Updates the array of `callDatas`. The length must be consistent with other call parameter arrays. Only callable by the `admin`.

### `setCallParameters(address[] calldata _targets, bytes[] calldata _functionSignatures, bytes[] calldata _callDatas) external adminOnly`
Atomically updates `targets`, `functionSignatures`, and `callDatas`. Ensures all arrays have matching lengths. Only callable by the `admin`.

### `initiateCall() external`
This is the main function that orchestrates the operation:
1. Determines the amount of tokens available to mint from the `minter` (up to its cap) and mints these tokens from `minter` directly to this contract (`address(this)`).
2. Requires that the `targets`, `functionSignatures`, and `callDatas` arrays have matching lengths.
3. Iterates through the `targets` array:
    a. For each `targets[i]`, it constructs the `fullCallData` by concatenating `functionSignatures[i]` and `callDatas[i]`.
    b. Executes the call to `targets[i]` with `fullCallData`.
    c. Reverts if any of the calls fail.

## Security Considerations
- **Admin Control**: The `admin` has significant control over all configurable parameters. The security of the admin key is paramount.
- **Target Interaction**: The contract interacts with external `targets`. Ensure all `targets` addresses, `functionSignatures`, and `callDatas` are correctly set and that all target contracts are audited and secure. Malicious or buggy targets could lead to unexpected behavior or interfere with subsequent calls in the sequence if not handled carefully (though a failing call will revert the entire `initiateCall`).
- **Minter Trust**: The `minter` contract must be trusted to mint tokens correctly, securely, and to correctly report its cap and minted amounts. The type of token minted is determined by the `minter`.
- **Array Length Consistency**: The contract has checks to ensure `targets`, `functionSignatures`, and `callDatas` arrays match in length during setup and execution. However, the logical pairing of these elements is critical for correct operation.

## Integration Example
This contract can be used to perform a sequence of actions, such as funding multiple airdrops or interacting with several DeFi protocols in one go.

```solidity
// Example: Setting up to call two different functions on two target contracts
address adminAddress = msg.sender;

// Target 1: MerkleDropFactory
address merkleDropFactoryAddress = address(myMerkleDropFactory);
bytes4 addTreeSig = myMerkleDropFactory.addMerkleTree.selector;
bytes memory addTreeArgs = abi.encode(
    bytes32_merkleRoot1, 
    bytes32_ipfsHash1, 
    address(tokenFromMinter), // Token address is implicit from minter 
    uint256_amountToFund1
);

// Target 2: AnotherContract
address anotherContractAddress = address(myOtherService);
bytes4 someFuncSig = myOtherService.someFunction.selector;
bytes memory someFuncArgs = abi.encode(uint256_paramA, bool_paramB);

ZkMinterModTriggerV1 trigger = new ZkMinterModTriggerV1(
    adminAddress,
    new address[](2),[merkleDropFactoryAddress, anotherContractAddress]),
    new bytes[](2),[abi.encodePacked(addTreeSig), abi.encodePacked(someFuncSig)]),
    new bytes[](2),[addTreeArgs, someFuncArgs])
);

// After deployment, set the minter (e.g., ZkCappedMinterV2)
// Assume zkCappedMinter is already deployed
trigger.setMinter(address(zkCappedMinter));

// Grant MINTER_ROLE to the trigger contract on zkCappedMinter
// zkCappedMinter.grantRole(MINTER_ROLE, address(trigger));

// Now, anyone can call initiateCall on the trigger
// trigger.initiateCall(); 
// This will mint tokens to the trigger contract, then call:
// 1. myMerkleDropFactory.addMerkleTree(...)
// 2. myOtherService.someFunction(...)
```

Refer to `DeployZkMinterModTriggerV1.ts` for deployment script examples which may need updating to reflect array-based configuration.
