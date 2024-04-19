// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title Multisig
/// @dev An abstract contract implementing a basic multisig wallet functionality.
/// This contract allows a group of members to collectively authorize actions
/// by submitting a threshold number of valid signatures.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
abstract contract Multisig is IERC1271 {
    /// @notice List of addresses authorized as members of the multisig.
    address[] public members;

    /// @notice The threshold for EIP-1271 signature verification.
    uint256 immutable EIP1271_THRESHOLD;

    /// @dev Initializes the contract by setting the sorted list of multisig members.
    /// Members must be unique and sorted in ascending order to ensure efficient
    /// signature verification.
    /// @param _members Array of addresses to be set as multisig members.
    /// Expected to be sorted without duplicates.
    /// @param _eip1271Threshold The threshold for EIP-1271 signature verification.
    constructor(address[] memory _members, uint256 _eip1271Threshold) {
        address lastAddress;
        for (uint256 i = 0; i < _members.length; ++i) {
            address currentMember = _members[i];
            // Ensure the members list is strictly ascending to prevent duplicates and enable efficient signature checks.
            require(lastAddress < currentMember, "Members not sorted or duplicate found");

            members.push(currentMember);
            lastAddress = currentMember;
        }
        EIP1271_THRESHOLD = _eip1271Threshold;
    }

    /// @dev The function to check if the provided signatures meet the threshold requirement.
    /// Signatures must be from unique members and are expected in the same order as the members list (sorted order).
    /// @param _digest The hash of the data being signed.
    /// @param _signatures An array of signatures to be validated.
    /// @param _threshold The minimum number of valid signatures required to pass the check.
    function checkSignatures(bytes32 _digest, bytes[] memory _signatures, uint256 _threshold) public view {
        // Ensure the total number of signatures meets or exceeds the threshold.
        require(_signatures.length >= _threshold, "Insufficient valid signatures");

        uint256 currentMember;
        for (uint256 i = 0; i < _signatures.length; ++i) {
            address signer = ECDSA.recover(_digest, _signatures[i]);
            while (members[currentMember] != signer) {
                currentMember++;
            }
            currentMember++;
        }
    }

    /// @dev The function to check if the provided signatures are valid and meet predefined threshold.
    /// @param _digest The hash of the data being signed.
    /// @param _signature An array of signatures to be validated ABI encoded from `bytes[]` to `abi.decode(data,(bytes[]))`.
    function isValidSignature(bytes32 _digest, bytes calldata _signature) external view override returns (bytes4) {
        bytes[] memory signatures = abi.decode(_signature, (bytes[]));
        checkSignatures(_digest, signatures, EIP1271_THRESHOLD);
        return IERC1271.isValidSignature.selector;
    }
}
