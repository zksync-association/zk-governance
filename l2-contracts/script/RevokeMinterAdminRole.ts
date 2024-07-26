import { config as dotEnvConfig } from "dotenv";
import { getTokenContract } from "./utils";

// Before executing in a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
// The TOKEN_ADDRESS below is derived from the output of the DeployZkTokenV1.ts script, using hardhat/zksync local node account 0 as the deployer.
// The MINTER_ADMIN_ADDRESS is initially set to the hardhat/zkSync local node account 1.
const TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const MINTER_ADMIN_ADDRESS = "0x478A1eBE665396ce0F2F87aB0F057aC273451B92"


async function main() {
  dotEnvConfig();

  const tokenContract = await getTokenContract(TOKEN_ADDRESS);

  const hasRoleBefore = await tokenContract.hasRole(tokenContract.MINTER_ADMIN_ROLE(), MINTER_ADMIN_ADDRESS);
  if (!hasRoleBefore) {
    console.log(`The address ${MINTER_ADMIN_ADDRESS} does not have the MINTER_ADMIN_ROLE`);
    return;
  }
  console.log("Revoking MINTER_ADMIN_ROLE for ZkTokenV1 from " + MINTER_ADMIN_ADDRESS);

  // revoke the MINTER_ADMING_ROLE from the minterAdminAddress account
  const tx = await tokenContract.revokeRole(tokenContract.MINTER_ADMIN_ROLE(), MINTER_ADMIN_ADDRESS);
  await tx.wait();

  // report the result of the revoke action
  const hasRoleAfter = await tokenContract.hasRole(tokenContract.MINTER_ADMIN_ROLE(), MINTER_ADMIN_ADDRESS);
  if (hasRoleAfter) {
    throw `Failed to revoke MINTER_ADMIN_ROLE for ${MINTER_ADMIN_ADDRESS}`;
  }
  console.log('Successfully revoked MINTER_ADMIN_ROLE for ' + MINTER_ADMIN_ADDRESS);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
