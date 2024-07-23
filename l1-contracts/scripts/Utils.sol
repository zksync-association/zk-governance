// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

library Utils {
    function sortAddresses(address[] memory _addresses)
        internal
        pure
        returns (address[] memory sortedAddresses)
    {
        for (uint256 i = 0; i < _addresses.length; i++) {
            uint256 lowest = i;
            for (uint256 j = i + 1; j < _addresses.length; j++) {
                if (uint160(_addresses[j]) < uint160(_addresses[lowest])) {
                    lowest = j;
                }
            }
            // swap
            address min = _addresses[i];
            _addresses[i] = _addresses[lowest];
            _addresses[lowest] = min;
        }
        sortedAddresses = _addresses;
    }
}
