// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IPausable} from "./IPausable.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IBridgeHub is IPausable {
    function getAllZKChainChainIDs() external view returns (uint256[] memory);
}
