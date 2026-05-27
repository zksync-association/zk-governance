/**
 * DeployZkTokenV2FromScratch.ts
 *
 * Deploys ZkTokenV2 from scratch by:
 *   1. Deploying the ZkTokenV1 implementation
 *   2. Deploying a TransparentUpgradeableProxy (TUP) pointing at V1 and calling initialize()
 *   3. Deploying the ZkTokenV2 implementation
 *   4. Upgrading the proxy to V2 and calling initializeV2()
 *   5. Granting all roles (DEFAULT_ADMIN, MINTER_ADMIN, BURNER_ADMIN, MINTER, BURNER) to PROXY_OWNER
 *   6. Minting 1 000 000 ZK tokens to PROXY_OWNER
 *   7. Registering the token on the L2NativeTokenVault so it is bridgeable to L1
 *
 * The script is designed to be resumable: it reads/writes a state file at
 * DEPLOY_STATE_FILE and skips steps that have already been completed.
 *
 * Usage:
 *   npx hardhat run script/DeployZkTokenV2FromScratch.ts --network zkSyncTestnet
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY  – private key of the deployer wallet (must match PROXY_OWNER for role granting)
 *
 * The PROXY_OWNER below is HARDCODED. It is the address that will:
 *   - Own the ProxyAdmin (controls contract upgrades)
 *   - Hold all access-control roles on the token
 *   - Receive the initial 1 000 000 ZK token mint
 *
 * IMPORTANT: For production deployments, change PROXY_OWNER to the appropriate
 * governance multisig or timelock address, and ensure DEPLOYER_PRIVATE_KEY
 * corresponds to that same address (or arrange a separate ownership-transfer step).
 */

import * as fs from "fs";
import * as path from "path";
import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, Contract, Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as hre from "hardhat";

// ---------------------------------------------------------------------------
// HARDCODED CONFIGURATION
// ---------------------------------------------------------------------------

/**
 * The address that will own the ProxyAdmin and hold all token roles.
 * Change this for production deployments.
 */
const PROXY_OWNER = "0xD742604A657A114ca6d59b4B0eA541ced7Bd9413";

/** Amount minted to PROXY_OWNER during setup (1 000 000 ZK tokens, 18 decimals). */
const INITIAL_MINT_AMOUNT = ethers.parseUnits("1000000", 18);

/**
 * L2NativeTokenVault – predeploy address on every ZKsync Era chain.
 * Registering the token here makes it bridgeable back to L1.
 */
const L2_NATIVE_TOKEN_VAULT = "0x0000000000000000000000000000000000010004";

/** Path to the JSON file that persists deployment state between runs. */
const DEPLOY_STATE_FILE = path.join(__dirname, ".deploy-state.json");

// ---------------------------------------------------------------------------
// STATE MANAGEMENT
// ---------------------------------------------------------------------------

interface DeployState {
  step: number;
  v1ImplAddress?: string;
  proxyAddress?: string;
  proxyAdminAddress?: string;
  v2ImplAddress?: string;
  rolesGranted?: boolean;
  tokenMinted?: boolean;
  registeredOnNTV?: boolean;
}

function loadState(): DeployState {
  if (fs.existsSync(DEPLOY_STATE_FILE)) {
    const raw = fs.readFileSync(DEPLOY_STATE_FILE, "utf-8");
    return JSON.parse(raw) as DeployState;
  }
  return { step: 0 };
}

function saveState(state: DeployState): void {
  fs.writeFileSync(DEPLOY_STATE_FILE, JSON.stringify(state, null, 2), "utf-8");
  console.log(`  [state saved to ${DEPLOY_STATE_FILE}]`);
}

// ---------------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------------

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw new Error("Please set DEPLOYER_PRIVATE_KEY in your .env file");
  }

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);
  const deployerAddress = await zkWallet.getAddress();

  console.log(`\nDeployer address : ${deployerAddress}`);
  console.log(`Proxy owner      : ${PROXY_OWNER}`);
  if (deployerAddress.toLowerCase() !== PROXY_OWNER.toLowerCase()) {
    console.warn(
      "\n⚠  WARNING: DEPLOYER_PRIVATE_KEY does not correspond to PROXY_OWNER.\n" +
        "   The deployer will set PROXY_OWNER as the token admin.\n" +
        "   Steps that require signing as PROXY_OWNER will be skipped – grant roles manually.\n"
    );
  }

  const state = loadState();
  console.log(`\nResuming from step ${state.step}\n`);

  // -------------------------------------------------------------------------
  // STEP 1 – Deploy ZkTokenV1 implementation
  // -------------------------------------------------------------------------
  if (state.step < 1) {
    console.log("STEP 1: Deploying ZkTokenV1 implementation…");
    const v1Artifact = await deployer.loadArtifact("ZkTokenV1");
    const v1Impl = await deployer.deploy(v1Artifact, []);
    await v1Impl.waitForDeployment();
    state.v1ImplAddress = await v1Impl.getAddress();
    state.step = 1;
    saveState(state);
    console.log(`  ZkTokenV1 implementation: ${state.v1ImplAddress}`);
  } else {
    console.log(`STEP 1: skipped  (ZkTokenV1 impl = ${state.v1ImplAddress})`);
  }

  // -------------------------------------------------------------------------
  // STEP 2 – Deploy TUP with V1 impl + call initialize()
  // PROXY_OWNER becomes the initial admin; receives 1 000 000 ZK initially.
  // -------------------------------------------------------------------------
  if (state.step < 2) {
    console.log("STEP 2: Deploying proxy (TUP) with ZkTokenV1 + initializing…");
    const v1Artifact = await deployer.loadArtifact("ZkTokenV1");

    // deployProxy deploys: implementation, ProxyAdmin, TransparentUpgradeableProxy
    // and calls initialize() on the proxy.
    const proxy = await hre.zkUpgrades.deployProxy(
      deployer.zkWallet,
      v1Artifact,
      // initialize(address _admin, address _mintReceiver, uint256 _mintAmount)
      [PROXY_OWNER, PROXY_OWNER, INITIAL_MINT_AMOUNT],
      { initializer: "initialize" }
    );
    await proxy.waitForDeployment();
    state.proxyAddress = await proxy.getAddress();
    state.step = 2;
    saveState(state);
    console.log(`  Proxy (token) address: ${state.proxyAddress}`);

    // Fetch and persist the ProxyAdmin address
    const proxyAdmin = await hre.zkUpgrades.admin.getInstance(deployer.zkWallet);
    state.proxyAdminAddress = await proxyAdmin.getAddress();
    saveState(state);
    console.log(`  ProxyAdmin address:    ${state.proxyAdminAddress}`);

    const tokenV1 = new Contract(state.proxyAddress, v1Artifact.abi, deployer.zkWallet);
    const supply = await tokenV1.totalSupply();
    console.log(`  Total supply after init: ${ethers.formatUnits(supply, 18)} ZK`);
  } else {
    console.log(`STEP 2: skipped  (proxy = ${state.proxyAddress})`);
  }

  // -------------------------------------------------------------------------
  // STEP 3 – Deploy ZkTokenV2 implementation
  // -------------------------------------------------------------------------
  if (state.step < 3) {
    console.log("STEP 3: Deploying ZkTokenV2 implementation…");
    const v2Artifact = await deployer.loadArtifact("ZkTokenV2");
    const v2Impl = await deployer.deploy(v2Artifact, []);
    await v2Impl.waitForDeployment();
    state.v2ImplAddress = await v2Impl.getAddress();
    state.step = 3;
    saveState(state);
    console.log(`  ZkTokenV2 implementation: ${state.v2ImplAddress}`);
  } else {
    console.log(`STEP 3: skipped  (ZkTokenV2 impl = ${state.v2ImplAddress})`);
  }

  // -------------------------------------------------------------------------
  // STEP 4 – Upgrade proxy to V2 and call initializeV2()
  // -------------------------------------------------------------------------
  if (state.step < 4) {
    console.log("STEP 4: Upgrading proxy to ZkTokenV2 + calling initializeV2()…");
    if (!state.proxyAddress) throw new Error("proxyAddress missing from state");

    const v2Artifact = await deployer.loadArtifact("ZkTokenV2");
    await hre.zkUpgrades.upgradeProxy(
      deployer.zkWallet,
      state.proxyAddress,
      v2Artifact,
      { call: "initializeV2" }
    );

    const tokenV2 = new Contract(state.proxyAddress, v2Artifact.abi, deployer.zkWallet);
    const name = await tokenV2.name();
    const symbol = await tokenV2.symbol();
    console.log(`  Token name: ${name}, symbol: ${symbol}`);

    state.step = 4;
    saveState(state);
  } else {
    console.log("STEP 4: skipped  (proxy already upgraded to V2)");
  }

  // -------------------------------------------------------------------------
  // STEP 5 – Grant all roles to PROXY_OWNER
  // Requires that DEPLOYER_PRIVATE_KEY corresponds to PROXY_OWNER (who holds DEFAULT_ADMIN_ROLE).
  // -------------------------------------------------------------------------
  if (state.step < 5) {
    if (deployerAddress.toLowerCase() !== PROXY_OWNER.toLowerCase()) {
      console.log("STEP 5: SKIPPED – deployer != PROXY_OWNER; grant roles manually via PROXY_OWNER key.");
    } else {
      console.log("STEP 5: Granting all roles to PROXY_OWNER…");
      if (!state.proxyAddress) throw new Error("proxyAddress missing from state");

      const v2Artifact = await deployer.loadArtifact("ZkTokenV2");
      const tokenV2 = new Contract(state.proxyAddress, v2Artifact.abi, deployer.zkWallet);

      // Retrieve role identifiers
      const MINTER_ADMIN_ROLE = await tokenV2.MINTER_ADMIN_ROLE();
      const BURNER_ADMIN_ROLE = await tokenV2.BURNER_ADMIN_ROLE();
      const MINTER_ROLE = await tokenV2.MINTER_ROLE();
      const BURNER_ROLE = await tokenV2.BURNER_ROLE();
      const DEFAULT_ADMIN_ROLE = await tokenV2.DEFAULT_ADMIN_ROLE();

      // DEFAULT_ADMIN_ROLE, MINTER_ADMIN_ROLE, BURNER_ADMIN_ROLE are already
      // granted to PROXY_OWNER by initialize(). We still call grantRole to be
      // explicit and to additionally grant MINTER_ROLE and BURNER_ROLE.
      const rolesToGrant = [
        { name: "DEFAULT_ADMIN_ROLE", role: DEFAULT_ADMIN_ROLE },
        { name: "MINTER_ADMIN_ROLE", role: MINTER_ADMIN_ROLE },
        { name: "BURNER_ADMIN_ROLE", role: BURNER_ADMIN_ROLE },
        { name: "MINTER_ROLE",       role: MINTER_ROLE },
        { name: "BURNER_ROLE",       role: BURNER_ROLE },
      ];

      for (const { name, role } of rolesToGrant) {
        const hasRole = await tokenV2.hasRole(role, PROXY_OWNER);
        if (!hasRole) {
          console.log(`  Granting ${name} to ${PROXY_OWNER}…`);
          const tx = await tokenV2.grantRole(role, PROXY_OWNER);
          await tx.wait();
        } else {
          console.log(`  ${name} already held by PROXY_OWNER – skipping`);
        }
      }

      state.rolesGranted = true;
      state.step = 5;
      saveState(state);
      console.log("  All roles granted.");
    }
  } else {
    console.log("STEP 5: skipped  (roles already granted)");
  }

  // -------------------------------------------------------------------------
  // STEP 6 – Mint 1 000 000 ZK tokens to PROXY_OWNER
  // (Already minted in initialize() — this step verifies and logs the balance.)
  // -------------------------------------------------------------------------
  if (state.step < 6) {
    console.log("STEP 6: Verifying initial token mint to PROXY_OWNER…");
    if (!state.proxyAddress) throw new Error("proxyAddress missing from state");

    const v2Artifact = await deployer.loadArtifact("ZkTokenV2");
    const tokenV2 = new Contract(state.proxyAddress, v2Artifact.abi, deployer.zkWallet);
    const balance = await tokenV2.balanceOf(PROXY_OWNER);
    const totalSupply = await tokenV2.totalSupply();

    console.log(`  PROXY_OWNER balance: ${ethers.formatUnits(balance, 18)} ZK`);
    console.log(`  Total supply       : ${ethers.formatUnits(totalSupply, 18)} ZK`);

    if (balance < INITIAL_MINT_AMOUNT) {
      // The mint was expected in initialize(); if the balance is insufficient
      // and the deployer == PROXY_OWNER (who has MINTER_ROLE), top it up.
      if (deployerAddress.toLowerCase() === PROXY_OWNER.toLowerCase()) {
        const deficit = INITIAL_MINT_AMOUNT - balance;
        console.log(`  Balance below target – minting ${ethers.formatUnits(deficit, 18)} ZK…`);
        const tx = await tokenV2.mint(PROXY_OWNER, deficit);
        await tx.wait();
        console.log(`  Mint complete.`);
      } else {
        console.warn("  ⚠  Balance below 1 000 000 ZK – mint manually as PROXY_OWNER.");
      }
    }

    state.tokenMinted = true;
    state.step = 6;
    saveState(state);
  } else {
    console.log("STEP 6: skipped  (token mint already verified)");
  }

  // -------------------------------------------------------------------------
  // STEP 7 – Register token on L2NativeTokenVault
  // This makes the ZK token bridgeable to L1 via the ZKsync bridge protocol.
  // -------------------------------------------------------------------------
  if (state.step < 7) {
    console.log("STEP 7: Registering ZK token on L2NativeTokenVault…");
    if (!state.proxyAddress) throw new Error("proxyAddress missing from state");

    const l2NTVAbi = [
      "function registerToken(address _nativeToken) external",
      "function assetId(address token) external view returns (bytes32)",
    ];
    const l2NTV = new Contract(L2_NATIVE_TOKEN_VAULT, l2NTVAbi, deployer.zkWallet);

    // Check if already registered
    const existingAssetId = await l2NTV.assetId(state.proxyAddress);
    if (existingAssetId !== ethers.ZeroHash) {
      console.log(`  Already registered. assetId: ${existingAssetId}`);
    } else {
      const tx = await l2NTV.registerToken(state.proxyAddress);
      await tx.wait();
      const assetId = await l2NTV.assetId(state.proxyAddress);
      console.log(`  Registration successful. assetId: ${assetId}`);
    }

    state.registeredOnNTV = true;
    state.step = 7;
    saveState(state);
  } else {
    console.log("STEP 7: skipped  (token already registered on NTV)");
  }

  // -------------------------------------------------------------------------
  // Transfer ProxyAdmin ownership to PROXY_OWNER (if deployer != PROXY_OWNER)
  // -------------------------------------------------------------------------
  const proxyAdmin = await hre.zkUpgrades.admin.getInstance(deployer.zkWallet);
  const currentOwner = await proxyAdmin.owner();
  if (currentOwner.toLowerCase() !== PROXY_OWNER.toLowerCase()) {
    console.log(`\nTransferring ProxyAdmin ownership from ${currentOwner} → ${PROXY_OWNER}…`);
    await hre.zkUpgrades.admin.transferProxyAdminOwnership(PROXY_OWNER, deployer.zkWallet);
    console.log("  Ownership transferred.");
  } else {
    console.log(`\nProxyAdmin already owned by PROXY_OWNER (${PROXY_OWNER}).`);
  }

  // -------------------------------------------------------------------------
  // SUMMARY
  // -------------------------------------------------------------------------
  console.log("\n=== Deployment complete ===");
  console.log(`Token proxy (ZkTokenV2) : ${state.proxyAddress}`);
  console.log(`ZkTokenV1 implementation: ${state.v1ImplAddress}`);
  console.log(`ZkTokenV2 implementation: ${state.v2ImplAddress}`);
  console.log(`ProxyAdmin              : ${state.proxyAdminAddress}`);
  console.log(`Proxy owner             : ${PROXY_OWNER}`);
  console.log(`L2NativeTokenVault      : ${L2_NATIVE_TOKEN_VAULT}`);
  console.log(`\nState persisted to: ${DEPLOY_STATE_FILE}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
