module main {
    import guardians.* from "./guardians"
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import securityCouncil.* from "./securityCouncil"
    import state.* from "./state"
    import types.* from "./types"

    val MEMBERS = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
    val GUARDIAN_MEMBERS = Set("g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8")
    val NON_MEMBERS = Set("x1", "x2", "x3")
    val L2_PROPOSALS = Set("L2Prop1", "L2Prop2", "L2Prop3")
    val TX_REQUESTS = Set("txr1", "txr2", "txr3")

    val TIMESTAMPS = 1.to(10^3)

    val WrongUpgradeIDs = Set(AbiStr("nid1"), AbiStr("nid2"))

    val THRESHOLD=1.to(30)

    var evm: EvmState

    var freezeCounter: { soft: int, hard: int }

    action init =
        val zkFoundatioMultisig = newMultisig(MEMBERS, 5)
        val sc = newSecurityCouncil(MEMBERS)
        val guardians = newGuardians(GUARDIAN_MEMBERS)
        nondet timestamp = TIMESTAMPS.oneOf()
        all {
            isOk(zkFoundatioMultisig),
            isOk(sc),
            isOk(guardians),
            evm' = {
                blockTimestamp: timestamp,
                securityCouncil: sc.v,
                guardians: guardians.v,
                zkFoundation: zkFoundatioMultisig.v,
                protocolUpgradeHandler: {
                    securityCouncil: SECURITY_COUNCIL_ADDR,
                    guardians: GUARDIANS_ADDR,
                    emergencyUpgradeBoard: EMERGENCY_UPGRADE_BOARD_ADDR,
                    upgradeStatus: Map(),
                    lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                    protocolFrozenUntil: 0,
                },
                priorityQueue: [],
                zkFrozen: false,
                ghostCallHistory: {
                    lastSender: "",
                    calls: [],
                }
            },
            freezeCounter' = { soft: 0, hard: 0 },
        }

    action advanceTime = {
        nondet newTimestamp = oneOf(TIMESTAMPS)
        all {
            newTimestamp > evm.blockTimestamp,
            evm' = {
                ...evm,
                blockTimestamp: newTimestamp,
            },
            freezeCounter' = freezeCounter,
        }
    }

    action step = any {
        advanceTime,
        callSecurityCouncilSoftFreeze,
        callSecurityCouncilHardFreeze,
        callSecurityCouncilApproveUpgradeSecurityCouncil,
        callSecurityCouncilUnfreeze,
        callSecurityCouncilSetSoftFreezeThreshold,
        callProtocolUpgradeHandlerSoftFreeze,
        callProtocolUpgradeHandlerHardFreeze,
        callProtocolUpgradeHandlerUnfreeze,
        callGuardiansProposeL2GovernorProposal,
        callGuardiansCancelL2GovernorProposal,
    }

    // Security council

    action callSecurityCouncilApproveUpgradeSecurityCouncil = {
        nondet id = oneOf(getAllUpgradeIDs(evm).union(WrongUpgradeIDs))
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, "softFreeze")
        val result = securityCouncilApproveUpgradeSecurityCouncil(evm2, id, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = freezeCounter,
        }
    }

    action callSecurityCouncilSoftFreeze = {
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, "softFreeze")
        val result = securityCouncilSoftFreeze(evm2, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = { ...freezeCounter, soft: freezeCounter.soft + 1 } ,
        }
    }

    action callSecurityCouncilHardFreeze = {
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, "hardFreeze")
        val result = securityCouncilHardFreeze(evm2, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = { ...freezeCounter, hard: freezeCounter.hard + 1 },
        }
    }

    action callSecurityCouncilUnfreeze = {
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, "unfreeze")
        val result = securityCouncilUnfreeze(evm2, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = freezeCounter,
        }
    }

    action callSecurityCouncilSetSoftFreezeThreshold = {
        nondet threshold = oneOf(THRESHOLD)
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val result = securityCouncilSetSoftFreezeThreshold(evm, threshold, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = freezeCounter,
        }
    }

    // Protocol handler

    action callProtocolUpgradeHandlerSoftFreeze = {
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, "softFreeze")
        val result = protocolUpgradeHandlerSoftFreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = { ...freezeCounter, soft: freezeCounter.soft + 1 } ,
        }
    }

    action callProtocolUpgradeHandlerHardFreeze = {
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, "hardFreeze")
        val result = protocolUpgradeHandlerHardFreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = { ...freezeCounter, hard: freezeCounter.hard + 1 } ,
        }
    }

    action callProtocolUpgradeHandlerUnfreeze = {
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, "unfreeze")
        val result = protocolUpgradeHandlerUnfreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = freezeCounter,
        }
    }

    action callGuardiansProposeL2GovernorProposal = {
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        val evm2: EvmState = evm.externalCall(sender, GUARDIANS_ADDR, "proposeL2GovernorProposal")
        nondet l2Proposal = L2_PROPOSALS.oneOf()
        nondet txRequest = TX_REQUESTS.oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val result = guardiansProposeL2GovernorProposal(evm2, l2Proposal, txRequest, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = freezeCounter,
        }
    }

    action callGuardiansCancelL2GovernorProposal = {
        nondet sender = MEMBERS.union(NON_MEMBERS).oneOf()
        val evm2: EvmState = evm.externalCall(sender, GUARDIANS_ADDR, "cancelL2GovernorProposal")
        nondet l2Proposal = L2_PROPOSALS.oneOf()
        nondet txRequest = TX_REQUESTS.oneOf()
        nondet signers = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        nondet signatures = MEMBERS.union(NON_MEMBERS).powerset().oneOf()
        val result = guardiansCancelL2GovernorProposal(evm2, l2Proposal, txRequest, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeCounter' = freezeCounter,
        }
    }

    // invariants
    val onlyCouncilCallsSoftFreeze =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == "softFreeze")
                implies (e.caller == SECURITY_COUNCIL_ADDR)
        })

    val zkFrozenInv =
        evm.zkFrozen implies evm.ghostCallHistory.calls.indices().exists(i => {
            val e = evm.ghostCallHistory.calls[i]
            e.caller == SECURITY_COUNCIL_ADDR
        })

    // soft and hard freezes should not be called twice,
    // and soft freeze should not be called after a hard one
    val freezeCounterInv = and {
        freezeCounter.soft <= 1,
        freezeCounter.hard <= 1,
        ((evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft)
            implies (freezeCounter.hard == 0))
    }

    // ZK should be frozen if and only if the unfreezing deadline has not been met.
    // This invariant is violated.
    val zkFrozenUntilStrongInv = {
        (evm.blockTimestamp <= evm.protocolUpgradeHandler.protocolFrozenUntil)
            iff
        evm.zkFrozen
    }

    // A weak version of zkFrozenUntilStrongInv:
    // If ZK is frozen, then the unfreezing deadline has not been met.
    // Alternatively, if the unfreezing deadline has not been met, then ZK is frozen.
    val zkFrozenUntilWeakInv = or {
        (evm.blockTimestamp > evm.protocolUpgradeHandler.protocolFrozenUntil),
        evm.zkFrozen
    }
        
    // falsy invariants
    val timeBelow1000Example =
        evm.blockTimestamp < 1000

    val zkFrozenExample =
        not(evm.zkFrozen)
}