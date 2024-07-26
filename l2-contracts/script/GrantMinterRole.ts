import { config as dotEnvConfig } from "dotenv";
import { getTokenContract } from './utils'

// Before executing in a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
// The TOKEN_ADDRESS below is derived from the output of the DeployZkTokenV1.ts script, using hardhat account 0 as the deployer.
// For local testing purposes, the MINTER is set to local hardhat account 2.
const TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const MINTER = "0x00D3dc9676572d04665A64Ee72A78cF0358F6382";

async function main() {
  dotEnvConfig();

  // get the already deployed token contract .. this function will throw an error if the ZKTOKENV1_ADMIN_PRIVATE_KEY env var is not set
  const tokenContract = await getTokenContract(TOKEN_ADDRESS);

  // report whether or not the role has been set on the MINTER account
  const hasRoleBefore = await tokenContract.hasRole(tokenContract.MINTER_ROLE(), MINTER);
  if (hasRoleBefore) {
    console.log(`The address ${MINTER} already has the MINTER_ROLE`);
    return;
  }
  console.log("Granting new MINTER_ROLE for ZkTokenV1 to " + MINTER);
  

  // grant the MINTER_ROLE to the MINTER account
  const tx = await tokenContract.grantRole(tokenContract.MINTER_ROLE(), MINTER);
  await tx.wait();

  // report the result of the grant action
  const hasRoleAfter = await tokenContract.hasRole(tokenContract.MINTER_ROLE(), MINTER);
  if (!hasRoleAfter) {
    throw `Failed to grant MINTER_ROLE to ${MINTER}`;
  }
  console.log('Successfully granted MINTER_ROLE to ' + MINTER);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
