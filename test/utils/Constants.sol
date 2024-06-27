// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract Constants {
  uint48 constant INITIAL_VOTING_DELAY = 1 days;
  uint32 constant INITIAL_VOTING_PERIOD = 7 days;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant INITIAL_QUORUM = 1_000_000e18;
  uint64 constant INITIAL_VOTE_EXTENSION = 1 days;
  string constant DESCRIPTION = "Description";
  uint256 constant TIMELOCK_MIN_DELAY = 0;
  address constant DEPLOYED_TOKEN_ADDRESS = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  address constant TOKEN_ADMIN_ADDRESS = 0x3cFc0e11D88B38A7577DAB36f3a8E5e8538a8C22;
  address constant TOKEN_PROXY_ADMIN = 0xdB1E46B448e68a5E35CB693a99D59f784aD115CC;
  bytes32 public constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
  bytes32 public constant BURNER_ADMIN_ROLE = keccak256("BURNER_ADMIN_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  string constant ZKSYNC_RPC_URL = "https://mainnet.era.zksync.io";
  string constant UPGRADE_DESCRIPTION = "Token Upgrade Proposal";
  address constant L1_MESSENGER_ADDRESS = 0x0000000000000000000000000000000000008008;
}
