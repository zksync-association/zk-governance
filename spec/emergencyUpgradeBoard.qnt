// -*- mode: Bluespec; -*-
module emergencyUpgradeBoard {
    import guardians.* from "./guardians"
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import securityCouncil.* from "./securityCouncil"
    import state.* from "./state"
    import types.* from "./types"

    /// -------------------------------------------------------------------------------------------
    /// EmergencyUpgradeBoard constants
    /// -------------------------------------------------------------------------------------------

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the guardians.
    pure val EXECUTE_EMERGENCY_UPGRADE_GUARDIANS_TYPEHASH =
        keccak256_str("ExecuteEmergencyUpgradeGuardians(bytes32 id)");

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the Security Council.
    pure val EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
        keccak256_str("ExecuteEmergencyUpgradeSecurityCouncil(bytes32 id)");

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the ZK Foundation.
    pure val EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH =
        keccak256_str("ExecuteEmergencyUpgradeZKFoundation(bytes32 id)");

    /// @notice Executes an emergency protocol upgrade approved by the Security Council, Guardians and ZK Foundation.
    /// @param _calls Array of `Call` structures specifying the calls to be made in the upgrade.
    /// @param _salt A bytes32 value used for creating unique upgrade proposal hashes.
    /// @param _guardiansSignatures Encoded signers & signatures from the guardians multisig, required to authorize the emergency upgrade.
    /// @param _securityCouncilSignatures Encoded signers & signatures from the Security Council multisig, required to authorize the emergency upgrade.
    /// @param _zkFoundationSignatures Signatures from the ZK Foundation multisig, required to authorize the emergency upgrade.
    pure def executeEmergencyUpgrade(
        evm: EvmState,
        _calls: List[Call],
        _salt: Bytes32,
        _guardiansSignatures: List[Bytes],
        _securityCouncilSignatures: List[Bytes],
        _zkFoundationSignatures: List[Bytes]
    ) : Result[EvmState] = {
        val proposal: UpgradeProposal = {
            calls: _calls,
            executor: EMERGENCY_UPGRADE_BOARD_ADDR,
            salt: _salt,
        }
        val id = keccak256_UpgradeProposal(proposal)

        val securityCouncilDigest = _hashTypedDataV4(
            "security council", "1",
            keccak256(abi_encode2(EXECUTE_EMERGENCY_UPGRADE_GUARDIANS_TYPEHASH, id))
        )

        val guardiansDigest = _hashTypedDataV4(
            "guardians", "1",
            keccak256(abi_encode2(EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH, id))
        )

        val zkFoundationDigest = _hashTypedDataV4(
            "guardians", "1",
            keccak256(abi_encode2(EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH, id))
        )

        val e1 = isValidSignature(evm.securityCouncil.multisig, securityCouncilDigest, _securityCouncilSignatures)
        if (e1 != "" ) {
            err(evm, e1)
        } else {
            val e2 = isValidSignature(evm.guardians.multisig, guardiansDigest, _guardiansSignatures)
            if (e2 != "" ) {
                err(evm, e2)
            } else {
                val e3 = isValidSignature(evm.zkFoundation, zkFoundationDigest, _zkFoundationSignatures)
                if (e3 != "" ) {
                    err({ ...evm}, e3)
                } else {
                    protocolUpgradeHandlerExecuteEmergencyUpgrade(evm, proposal)
                }
            }
        }
    }
}