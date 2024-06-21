// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Vm} from "forge-std/Test.sol";

library Utils {
    function sortWalletsByAddress(Vm.Wallet[] memory _wallets)
        internal
        pure
        returns (Vm.Wallet[] memory sortedWallets)
    {
        for (uint256 i = 0; i < _wallets.length; i++) {
            uint256 lowest = i;
            for (uint256 j = i + 1; j < _wallets.length; j++) {
                if (uint160(_wallets[j].addr) < uint160(_wallets[lowest].addr)) {
                    lowest = j;
                }
            }
            // swap
            Vm.Wallet memory min = _wallets[i];
            _wallets[i] = _wallets[lowest];
            _wallets[lowest] = min;
        }
        sortedWallets = _wallets;
    }

    // add this to be excluded from coverage report
    function test() private {}
}
