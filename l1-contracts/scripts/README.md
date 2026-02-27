## Env vars required for re-deployment

The below are the values required to re-deploy the **current** version given a deployment of the **previous** version [b1d1bdce1def3c036c06e449787a3763bf47e766](https://github.com/zksync-association/zk-governance/tree/b1d1bdce1def3c036c06e449787a3763bf47e766)).

`MainnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
GUARDIAN_MEMBERS= # Comma separated addresses, exactly 8
SECURITY_COUNCIL_MEMBERS= # Comma separated addresses, exactly 12
L2_PROTOCOL_GOVERNOR=0x085b8B6407f150D62adB1EF926F7f304600ec714
PUH_PROXY_MAINNET=0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3 
ERA_CHAIN_ID=321
```

`TestnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
GUARDIAN_MEMBERS= # Comma separated addresses, exactly 8
SECURITY_COUNCIL_MEMBERS= # Comma separated addresses, exactly 12
L2_PROTOCOL_GOVERNOR=0x085b8B6407f150D62adB1EF926F7f304600ec714
PUH_PROXY_TESTNET=0x9B956d242e6806044877C7C1B530D475E371d544
ERA_CHAIN_ID=321
```