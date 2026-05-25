// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Interface for ERC20 token standard
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address destination, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
