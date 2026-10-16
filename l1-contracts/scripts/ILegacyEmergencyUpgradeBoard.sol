// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

// The EmergencyUpgradeBoard deployed before the guardians removal exposes a `GUARDIANS()`
// getter that no longer exists on the current EmergencyUpgradeBoard sources. Scripts that
// read from the previous-generation deployment need the legacy interface.
interface ILegacyEmergencyUpgradeBoard {
    function GUARDIANS() external view returns (address);
}
