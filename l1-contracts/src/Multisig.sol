// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @title Multisig
/// @dev An abstract contract implementing a basic multisig wallet functionality.
/// This contract allows a group of members to collectively authorize actions
/// by submitting a threshold number of valid signatures.
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
abstract contract Multisig is IERC1271 {
    using SignatureChecker for address;

    /// @notice List of addresses authorized as members of the multisig.
    address[] public members;

    /// @notice The threshold for EIP-1271 signature verification.
    uint256 public immutable EIP1271_THRESHOLD;

    /// @dev Initializes the contract by setting the sorted list of multisig members.
    /// Members must be unique and sorted in ascending order to ensure efficient
    /// signature verification.
    /// @param _members Array of addresses to be set as multisig members.
    /// Expected to be sorted without duplicates.
    /// @param _eip1271Threshold The threshold for EIP-1271 signature verification.
    constructor(address[] memory _members, uint256 _eip1271Threshold) {
        require(_eip1271Threshold > 0, "EIP-1271 threshold is too small");
        require(_eip1271Threshold <= _members.length, "EIP-1271 threshold is too big");
        EIP1271_THRESHOLD = _eip1271Threshold;

        address lastAddress;
        for (uint256 i = 0; i < _members.length; ++i) {
            address currentMember = _members[i];
            // Ensure the members list is strictly ascending to prevent duplicates and enable efficient signature checks.
            require(lastAddress < currentMember, "Members not sorted or duplicate found");

            members.push(currentMember);
            lastAddress = currentMember;
        }
    }

    /// @dev The function to check if the provided signatures meet the threshold requirement.
    /// Signatures must be from unique members and are expected in the same order as the members list (sorted order).
    /// @param _digest The hash of the data being signed.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures to be validated.
    /// @param _threshold The minimum number of valid signatures required to pass the check.
    function checkSignatures(bytes32 _digest, address[] memory _signers, bytes[] memory _signatures, uint256 _threshold)
        public
        view
    {
        // Ensure the total number of signatures meets or exceeds the threshold.
        require(_signatures.length >= _threshold, "Insufficient valid signatures");
        require(_signers.length == _signatures.length, "Inconsistent signers/signatures length");

        uint256 currentMember;
        for (uint256 i = 0; i < _signatures.length; ++i) {
            bool success = _signers[i].isValidSignatureNow(_digest, _signatures[i]);
            require(success, "Signature verification failed");
            while (members[currentMember] != _signers[i]) {
                currentMember++;
            }
            currentMember++;
        }
    }

    /// @dev The function to check if the provided signatures are valid and meet predefined threshold.
    /// @param _digest The hash of the data being signed.
    /// @param _signature An array of signers and signatures to be validated ABI encoded from `address[], bytes[]` to `abi.decode(data,(address[],bytes[]))`.
    function isValidSignature(bytes32 _digest, bytes calldata _signature) external view override returns (bytes4) {
        (address[] memory signers, bytes[] memory signatures) = abi.decode(_signature, (address[], bytes[]));
        checkSignatures(_digest, signers, signatures, EIP1271_THRESHOLD);
        return IERC1271.isValidSignature.selector;
    }
}
