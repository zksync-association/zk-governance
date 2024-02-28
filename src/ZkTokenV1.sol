// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20VotesUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract ZkTokenV1 is Initializable, ERC20VotesUpgradeable, AccessControlUpgradeable {
  bytes32 public constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
  bytes32 public constant BURNER_ADMIN_ROLE = keccak256("BURNER_ADMIN_ROLE");

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

  function initialize(address _admin) public initializer {
    __ERC20_init("zkSync", "ZK");
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MINTER_ADMIN_ROLE, _admin);
    _grantRole(BURNER_ADMIN_ROLE, _admin);
    _setRoleAdmin(MINTER_ROLE, MINTER_ADMIN_ROLE);
    _setRoleAdmin(BURNER_ROLE, BURNER_ADMIN_ROLE);
  }

  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
    _burn(from, amount);
  }
}
