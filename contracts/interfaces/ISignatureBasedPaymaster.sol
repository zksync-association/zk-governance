// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface ISignatureBasedPaymaster {
    event SignerChanged(address indexed oldSigner, address indexed newSigner);
}
