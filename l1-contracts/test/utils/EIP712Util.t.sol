// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

contract EIP712Util {
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function _buildDomainHash(address _verifyingContract, string memory _name, string memory _version)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                TYPE_HASH, keccak256(bytes(_name)), keccak256(bytes(_version)), block.chainid, _verifyingContract
            )
        );
    }

    function _buildDigest(bytes32 _domainHash, bytes32 _message) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainHash, _message));
    }

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
