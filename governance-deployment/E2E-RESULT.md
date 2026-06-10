# cli-vote end-to-end test result (ZKsync Era testnet, chainId 301)

This records a real run of `cli-vote` against the deployed L2 governance, ending in an L2→L1
protocol-upgrade message, and the verification that the message is accepted by the deployed
`TestnetProtocolUpgradeHandler` via a Sepolia fork test.

## Setup

- Governor: `0x5ec7e7d5a5608F338A900152dA88B49691a62138`
- Timelock (= L1 `L2_PROTOCOL_GOVERNOR`): `0x9569F3eb8058198B6cf3E23FDfC7Ddca450f8882`
- ZK token: `0xaE0975Eb851CC49D2C4599174815f16A6aBE1284` (deployer holds 10,000,000,000 ZK, self-delegated)
- Proposal calls: [`examples/sample-upgrade.json`](./examples/sample-upgrade.json) (a single no-op call to `0x…dEaD`)

## Steps & on-chain results

```
$ cli-vote create --calls examples/sample-upgrade.json --description "demo upgrade e2e"
  L1 upgrade id (keccak of message): 0xdf9f70b6bd7e45d679aa83081944ca8c8da73bc35978cd26c33d22c7e82491e3
  proposalId: 105562894434819284426095586818890806856698527758791878939100803568219592277391
  propose tx: 0x6e562b539a8deb59a90e6ac4f4c27535282191a658a30d94d81ec4af7e282cff (block 39)

$ cli-vote vote --proposal <id> --support for
  Tallies — for: 10000000000.0 against: 0.0 abstain: 0.0
  vote tx: 0x133f62793d22b1e8d4cfef9b7c792bd1837e8dc18ef563ffa9f59716443c1418

$ cli-vote queue   --proposal <id>     # after the voting deadline
  queue tx:   0xbbcf65a61d2f19817deec6d8c5a457743f3a32ea829fecb6d71483333b588119
$ cli-vote execute --proposal <id>     # emits the L2->L1 message
  execute tx: 0xb8452d2989392fe0b6693e187a490d7550913bf4630bfc0c584468afec613760 (block 42)

$ cli-vote message --proposal <id>
  Emitted L2->L1 message sender (topic): 0x9569f3eb8058198b6cf3e23fdfc7ddca450f8882   <-- the L2 timelock
  Emitted message hash (topic):          0xdf9f70b6bd7e45d679aa83081944ca8c8da73bc35978cd26c33d22c7e82491e3
  Matches locally-encoded UpgradeProposal: true
  Upgrade id (keccak256 of message):     0xdf9f70b6bd7e45d679aa83081944ca8c8da73bc35978cd26c33d22c7e82491e3
```

Key facts proven on-chain:

- The proposal's single action calls the L2 `L1Messenger` (`0x…8008`) `sendToL1`, and is executed by
  the **timelock** — so the emitted L2→L1 message's **sender is the timelock**
  (`0x9569…882`), exactly the address the L1 handler trusts as `L2_PROTOCOL_GOVERNOR`.
- The emitted message bytes equal `abi.encode(UpgradeProposal)` produced locally by `cli-vote`
  (`Matches … : true`), and its keccak256 equals the `upgradeId`.

## Fork verification against the testnet ProtocolUpgradeHandler

`l1-contracts/test/L2MessageCompatForkTest.t.sol` forks Sepolia, (re)deploys the
`TestnetProtocolUpgradeHandler` wired to the same L2 timelock, mocks the diamond's
`proveL2MessageInclusion` (a real Merkle proof needs the L2 batch sealed on L1, which takes hours),
and calls `startUpgrade` with the emitted message:

```
$ MESSAGE_HEX=<emitted message> EXPECTED_SENDER=0x9569…882 SEPOLIA_RPC=$SEPOLIA forge test \
    --match-path test/L2MessageCompatForkTest.t.sol -vvv

[PASS] test_startUpgradeAcceptsCliVoteMessage()
  startUpgrade accepted; upgrade id: 0xdf9f70b6bd7e45d679aa83081944ca8c8da73bc35978cd26c33d22c7e82491e3
  upgrade state (2=Waiting): 2
```

`startUpgrade` accepted the message, registered the upgrade under id `0xdf9f…`, and moved it to
`Waiting` (the testnet handler has a 0-length legal-veto period). This confirms the L2→L1 message
produced by `cli-vote` is byte-compatible with the L1 testnet protocol upgrade handler. To set
`PUH_ADDRESS` to the real deployed handler instead of redeploying in-test, pass it via env.
