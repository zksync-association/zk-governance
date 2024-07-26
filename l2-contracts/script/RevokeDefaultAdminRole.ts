import { config as dotEnvConfig } from "dotenv";
import { getTokenContract } from './utils'

// Before executing in a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
// The TOKEN_ADDRESS below is derived from the output of the DeployZkTokenV1.ts script, using hardhat account 0 as the deployer.
// For local testing purposes, the NEW_ADMIN is set to local hardhat account 3.
const TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const SELECTED_DEFAULT_ADMIN = "0x478A1eBE665396ce0F2F87aB0F057aC273451B92";

async function main() {
  dotEnvConfig();

  // get the already deployed token contract .. this function will throw an error if the ZKTOKENV1_ADMIN_PRIVATE_KEY env var is not set
  const tokenContract = await getTokenContract(TOKEN_ADDRESS);

  // report whether or not the role has been set on the SELECTED_DEFAULT_ADMIN account
  const hasRoleBefore = await tokenContract.hasRole(tokenContract.DEFAULT_ADMIN_ROLE(), SELECTED_DEFAULT_ADMIN);
  if (!hasRoleBefore) {
    console.log(`The address ${SELECTED_DEFAULT_ADMIN} does not have the DEFAULT_ADMIN_ROLE`);
    return;
  }
  console.log("Revoking DEFAULT_ADMIN_ROLE for ZkTokenV1 on " + SELECTED_DEFAULT_ADMIN);

  // revoke the DEFAULT_ADMIN_ROLE to the SELECTED_DEFAULT_ADMIN account
  const tx = await tokenContract.revokeRole(tokenContract.DEFAULT_ADMIN_ROLE(), SELECTED_DEFAULT_ADMIN);
  await tx.wait();

  // report the result of the revoke action
  const hasRoleAfter = await tokenContract.hasRole(tokenContract.DEFAULT_ADMIN_ROLE(), SELECTED_DEFAULT_ADMIN);
  if (hasRoleAfter) {
    throw `Failed to revoke DEFAULT_ADMIN_ROLE to ${SELECTED_DEFAULT_ADMIN}`;
  }
  console.log('Successfully revoked DEFAULT_ADMIN_ROLE to ' + SELECTED_DEFAULT_ADMIN);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
