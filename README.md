# ZK

## Development

### Requirements

This repository uses the [Foundry](https://book.getfoundry.sh/) development framework. Install Foundry using these [instructions](https://book.getfoundry.sh/getting-started/installation).

This repository also uses the [OpenZeppelin Foundry Upgrades Plugin](https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades) to manage deployment and upgrade management of transparent upgradeable proxy contracts.

Because the upgrades plugin relies on an npm package, we use [Volta](https://docs.volta.sh/guide/) to ensure a consistent npm environment between developers. Install volta using these [instructions](https://docs.volta.sh/guide/getting-started).

### Setup

Clone the repo:

```
git clone git@github.com:matter-labs/zk.git
cd zk
```

Install the npm dependencies:

```
npm install
```

The upgrades plugin requires a clean build whenever the contract code changes. Therefore, to execute the test suite you should run:

```
forge clean && forge test
```

For convenience, and npm command is also provided:

```
npm test
```


## License

ZK is available under the [MIT](LICENSE.txt) license.

Copyright (c) 2024 Matter Labs