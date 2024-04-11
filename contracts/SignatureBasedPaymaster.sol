// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {
    IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC, Transaction
} from "./interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "./interfaces/IPaymasterFlow.sol";
import {ISignatureBasedPaymaster} from "./interfaces/ISignatureBasedPaymaster.sol";

import {BOOTLOADER_FORMAL_ADDRESS} from "./Constants.sol";

/// @title Signature based paymaster
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev Implements a paymaster contract that validates transactions based on EIP-712 signatures.
contract SignatureBasedPaymaster is IPaymaster, ISignatureBasedPaymaster, Ownable, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @notice Length of the selector in bytes.
    uint256 constant SELECTOR_BYTE_LENGTH = 4;

    /// @notice Length of the data in bytes that represents the last timestamp when paymaster will accept the transaction.
    uint256 constant VALID_UNTIL_BYTE_LENGTH = 32;

    /// @notice Length of the encoded ECDSA signature in bytes.
    /// @dev The
    /// - 32 bytes for the memory offset
    /// - 32 bytes for the signature length
    /// - 96 byte for the encoding of ECDSA signature
    ///     - Fixed size for an ECDSA signature 65 bytes padded to 32 bytes
    uint256 constant ESDCA_SIGNATURE_ENCODED_BYTE_LENGTH = 32 + 32 + 96;

    /// @notice Expected length of the paymaster input.
    /// @dev Sum of the lengths of the selector, last valid timestamp, and ECDSA signature.
    /// This is used to validate the structure of the input data.
    uint256 constant PAYMASTER_INPUT_BYTE_LENGTH =
        SELECTOR_BYTE_LENGTH + VALID_UNTIL_BYTE_LENGTH + ESDCA_SIGNATURE_ENCODED_BYTE_LENGTH;

    /// @notice EIP-712 TypeHash for an approved transaction by the paymaster.
    /// @dev It includes the last timestamp when paymaster will accept the transaction
    /// and all the transaction parameters excluding the paymaster input (because of the circular dependency).
    bytes32 public constant APPROVED_TRANSACTION_TYPEHASH = keccak256(
        "ApprovedTransaction(uint256 txType,uint256 from,uint256 to,uint256 gasLimit,uint256 gasPerPubdataByteLimit,uint256 maxFeePerGas,uint256 maxPriorityFeePerGas,uint256 paymaster,uint256 nonce,uint256 value,bytes data,bytes32[] factoryDeps,uint256 validUntil)"
    );

    /// @notice The address authorized to sign transactions for this paymaster.
    /// @dev Transactions with a valid signature from this address will have their fees covered by the paymaster.
    address public signer;

    /// @dev Ensures that only the bootloader can call certain functions.
    modifier onlyBootloader() {
        require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
        // Continue execution if called from the bootloader.
        _;
    }

    /// @param _signer The initial signer address that is authorized to approve transactions for this paymaster.
    constructor(address _signer) EIP712("SignatureBasedPaymaster", "1") {
        require(_signer != address(0), "Signer cannot be address(0)");
        signer = _signer;
        emit SignerChanged(address(0), _signer);
    }

    /// @inheritdoc IPaymaster
    function validateAndPayForPaymasterTransaction(bytes32, bytes32, Transaction calldata _transaction)
        external
        payable
        onlyBootloader
        returns (bytes4, bytes memory)
    {
        require(
            _transaction.paymasterInput.length == PAYMASTER_INPUT_BYTE_LENGTH,
            "Paymaster: Invalid paymaster input length, must match PAYMASTER_INPUT_BYTE_LENGTH"
        );

        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
        require(paymasterInputSelector == IPaymasterFlow.general.selector, "Paymaster: Unsupported paymaster flow");

        // `general` paymaster flow accepts the raw `bytes`, so decode it first.
        (bytes memory innerInputs) = abi.decode(_transaction.paymasterInput[4:], (bytes));
        // Decode the real paymaster input parameters from the raw bytes.
        (uint256 validUntil, bytes memory sig) = abi.decode(innerInputs, (uint256, bytes));

        // Verify that the signature didn't expired.
        require(block.timestamp <= validUntil, "Paymaster: Signature expired");

        // Generate the EIP-712 digest.
        bytes32 structHash = keccak256(
            abi.encode(
                APPROVED_TRANSACTION_TYPEHASH,
                _transaction.txType,
                _transaction.from,
                _transaction.to,
                _transaction.gasLimit,
                _transaction.gasPerPubdataByteLimit,
                _transaction.maxFeePerGas,
                _transaction.maxPriorityFeePerGas,
                _transaction.paymaster,
                _transaction.nonce,
                _transaction.value,
                keccak256(_transaction.data),
                keccak256(abi.encodePacked(_transaction.factoryDeps)),
                validUntil
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        // Revert if signer not matched with recovered address. Reverts on address(0) as well.
        require(signer == digest.recover(sig), "Paymaster: Invalid signer");

        // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
        // neither paymaster nor account are allowed to access this context variable.
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

        // The bootloader never returns any data, so it can safely be ignored here.
        (bool success,) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredETH}("");
        require(success, "Paymaster: Failed to transfer tx fee to the bootloader");

        return (PAYMASTER_VALIDATION_SUCCESS_MAGIC, new bytes(0));
    }

    /// @inheritdoc IPaymaster
    function postTransaction(bytes calldata, Transaction calldata, bytes32, bytes32, ExecutionResult, uint256)
        external
        payable
        override
        onlyBootloader
    {
        // Do nothing as the transaction initiator address shouldn't get any refund.
    }

    /// @notice Withdraw funds from the contract to the specified address.
    /// @param _to The address where to send funds.
    /// @param _token Address of the token to be withdrawn.
    function withdraw(address _to, address _token) public onlyOwner {
        if (_token == address(0)) {
            (bool success,) = _to.call{value: address(this).balance}("");
            require(success, "Failed to withdraw ether");
        } else {
            // We use safeTransfer to escape any tokens even if they implemented ERC-20 standard wrongly (e.g. don't return bool value)
            IERC20(_token).safeTransfer(_to, IERC20(_token).balanceOf(address(this)));
        }
    }

    /// @notice Change the active signer address.
    /// @param _signer New signer address.
    function changeSigner(address _signer) external onlyOwner {
        emit SignerChanged(signer, _signer);
        signer = _signer;
    }

    /// @notice Returns the EIP-712 domain separator for this contract.
    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @dev Contract should receive/hold ETH to pay fees as a paymaster.
    receive() external payable {}
}
