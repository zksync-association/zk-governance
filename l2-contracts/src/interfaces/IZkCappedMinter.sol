// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Interface for ERC20 token standard
interface IZkCappedMinter {
    function CAP() external view returns (uint256);
    function minted() external view returns (uint256);
    function mint(address _to, uint256 _amount) external;
}
