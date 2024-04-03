// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Multisig
/// @dev An abstract contract implementing a basic multisig wallet functionality.
/// This contract allows a group of members to collectively authorize actions
/// by submitting a threshold number of valid signatures.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
abstract contract Multisig {
    /// @notice List of addresses authorized as members of the multisig.
    address[] public members;

    /// @dev Initializes the contract by setting the sorted list of multisig members.
    /// Members must be unique and sorted in ascending order to ensure efficient
    /// signature verification.
    /// @param _members Array of addresses to be set as multisig members.
    /// Expected to be sorted without duplicates.
    constructor(address[] memory _members) {
        address lastAddress;
        for (uint256 i = 0; i < _members.length; ++i) {
            address currentMember = _members[i];
            // Ensure the members list is strictly ascending to prevent duplicates and enable efficient signature checks.
            require(lastAddress < currentMember, "Members not sorted or duplicate found");

            members.push(currentMember);
            lastAddress = currentMember;
        }
    }

    /// @dev Internal function to check if the provided signatures meet the threshold requirement.
    /// Signatures must be from unique members and are expected in the same order as the members list (sorted order).
    /// @param _digest The hash of the data being signed.
    /// @param _signatures An array of signatures to be validated.
    /// @param _threshold The minimum number of valid signatures required to pass the check.
    function _checkSignatures(bytes32 _digest, bytes[] calldata _signatures, uint256 _threshold) internal view {
        uint256 currentMember;
        uint256 totalValidSignatures;

        for (uint256 i = 0; i < _signatures.length; ++i) {
            address signer = ECDSA.recover(_digest, _signatures[i]);
            while (members[currentMember] != signer) {
                currentMember++;
            }
            totalValidSignatures++;
        }

        // Ensure the total number of valid signatures meets or exceeds the threshold.
        require(totalValidSignatures >= _threshold, "Insufficient valid signatures");
    }
}
