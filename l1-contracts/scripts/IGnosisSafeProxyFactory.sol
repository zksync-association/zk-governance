// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IGnosisSafeProxyFactory {
    function createProxy(address singleton, bytes memory data) external returns(address);

    function createProxyWithNonce(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address);

    function proxyRuntimeCode() external pure returns (bytes memory);

    function proxyCreationCode() external pure;

    function calculateCreateProxyWithNonceAddress(
        address _singleton,
        bytes calldata initializer,
        uint256 saltNonce
    ) external returns (address);
}
