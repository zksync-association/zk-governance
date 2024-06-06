import { config as dotEnvConfig } from "dotenv";
import { getTokenContract } from './utils'

// Before executing in a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
// The TOKEN_ADDRESS below is derived from the output of the DeployZkTokenV1.ts script, using hardhat account 0 as the deployer.
// For local testing purposes, the NEW_DEFAULT_ADMIN is set to local hardhat account 3.
const TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const NEW_DEFAULT_ADMIN = "0x3cFc0e11D88B38A7577DAB36f3a8E5e8538a8C22";

async function main() {
  dotEnvConfig();

  // get the already deployed token contract .. this function will throw an error if the ZKTOKENV1_ADMIN_PRIVATE_KEY env var is not set
  const tokenContract = await getTokenContract(TOKEN_ADDRESS);

  // report whether or not the role has been set on the NEW_DEFAULT_ADMIN account
  const hasRoleBefore = await tokenContract.hasRole(tokenContract.DEFAULT_ADMIN_ROLE(), NEW_DEFAULT_ADMIN);
  if (hasRoleBefore) {
    console.log(`The address ${NEW_DEFAULT_ADMIN} already has the DEFAULT_ADMIN_ROLE`);
    return;
  }
  console.log("Granting new DEFAULT_ADMIN_ROLE for ZkTokenV1 to " + NEW_DEFAULT_ADMIN);

  // grant the DEFAULT_ADMIN_ROLE to the NEW_DEFAULT_ADMIN account
  const tx = await tokenContract.grantRole(tokenContract.DEFAULT_ADMIN_ROLE(), NEW_DEFAULT_ADMIN);
  await tx.wait();

  // report the result of the grant action
  const hasRoleAfter = await tokenContract.hasRole(tokenContract.DEFAULT_ADMIN_ROLE(), NEW_DEFAULT_ADMIN);
  if (!hasRoleAfter) {
    throw `Failed to grant DEFAULT_ADMIN_ROLE to ${NEW_DEFAULT_ADMIN}`;
  }
  console.log('Successfully granted DEFAULT_ADMIN_ROLE to ' + NEW_DEFAULT_ADMIN);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
