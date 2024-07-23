
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface ICREATE3Factory {
    function deploy(bytes32 _salt, bytes memory _creationCode)
        external
        payable
        returns (address deployed);

    function getDeployed(address _deployer, bytes32 _salt)
        external
        view
        returns (address deployed);
}