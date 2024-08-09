// -*- mode: Bluespec; -*-
module main {
    import emergencyUpgradeBoard.* from "./emergencyUpgradeBoard"
    import guardians.* from "./guardians"
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import securityCouncil.* from "./securityCouncil"
    import state.* from "./state"
    import types.* from "./types"

    pure val SECURITY_COUNCIL_MEMBERS = Set("sc1", "sc2", "sc3", "sc4", "sc5", "sc6", "sc7", "sc8", "sc9", "sc10", "sc11", "sc12")
    pure val SECURITY_COUNCIL_MEMBERS_QUORUM = SECURITY_COUNCIL_MEMBERS.powerset().filter(ms => ms.size() >= 9)
    pure val GUARDIAN_MEMBERS = Set("g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8")
    pure val ZK_FOUNDATION_MEMBERS = Set("zkf1", "zkf2", "zkf3", "zkf4", "zkf5", "zkf6", "zkf7", "zkf8")
    pure val NON_MEMBERS = Set("nobody1", "nobody2", "nobody3", ZERO_ADDRESS)
    pure val ALL_SENDERS = Set(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, GUARDIANS_ADDR, EMERGENCY_UPGRADE_BOARD_ADDR, ANY_ADDRESS)
    pure val ALL_MEMBERS = SECURITY_COUNCIL_MEMBERS.union(GUARDIAN_MEMBERS).union(ZK_FOUNDATION_MEMBERS).union(NON_MEMBERS);
    pure val ALL_ADDRESSES = ALL_SENDERS

    pure val L2_PROPOSALS = Set("L2Prop1", "L2Prop2", "L2Prop3")
    pure val TX_REQUESTS = Set("txr1", "txr2", "txr3")
    pure val CALLS = Set("call1")
    pure val SALTS = Set("salt1")
    pure val NEW_CONTRACTS_ADDRESSES = Set("0xaddr1", "0xaddr2", "0xaddr3")

    pure val TIMESTAMPS = 0.to(1024)
    pure val WrongUpgradeIDs = Set(AbiStr("nid1"), AbiStr("nid2"))
    pure val THRESHOLD=1.to(30)
    pure val hyperchainIds=1.to(3)
    pure val ids = 1.to(100)
    var evm: EvmState

    var freezeOps: List[Function]
    var strictFreezeOps: List[Function]
    var upgradeStateMachine: AbiElem -> (UpgradeState, UpgradeState, Function)

    action init =
        val zkFoundationMultisig = newMultisig(ZK_FOUNDATION_MEMBERS, 5)
        val sc = newSecurityCouncil(SECURITY_COUNCIL_MEMBERS)
        val guardians = newGuardians(GUARDIAN_MEMBERS)
        nondet timestamp = TIMESTAMPS.oneOf()
        all {
            isOk(zkFoundationMultisig),
            isOk(sc),
            isOk(guardians),
            evm' = {
                blockTimestamp: 1,
                securityCouncil: sc.v,
                guardians: guardians.v,
                zkFoundation: zkFoundationMultisig.v,
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
                frozenChains: Map(),
                ghostCallHistory: {
                    lastSender: "",
                    calls: [],
                },
                emittedEvents: [
                    EventChangeSecurityCouncil((ZERO_ADDRESS, SECURITY_COUNCIL_ADDR)),
                    EventChangeGuardians((ZERO_ADDRESS, GUARDIANS_ADDR)),
                    EventChangeEmergencyUpgradeBoard((ZERO_ADDRESS, EMERGENCY_UPGRADE_BOARD_ADDR))
                ],
            },
            freezeOps' = [],
            strictFreezeOps' = [],
            upgradeStateMachine' = Map(),
        }

    action advanceTime = {
        nondet newTimestamp = oneOf(TIMESTAMPS)
        all {
            newTimestamp > evm.blockTimestamp,
            evm' = {
                ...evm,
                blockTimestamp: newTimestamp,
            },
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action step = any {
        advanceTime,
        // Security Council actions
        SecurityCouncil::ApproveUpgradeSecurityCouncil,
        SecurityCouncil::SoftFreeze,
        SecurityCouncil::HardFreeze,
        SecurityCouncil::Unfreeze,
        SecurityCouncil::SetSoftFreezeThreshold,
        // Protocol upgrade handler actions
        // upgradability
        ProtocolUpgradeHandler::StartUpgrade,
        ProtocolUpgradeHandler::ExtendLegalVeto, 
        ProtocolUpgradeHandler::ApproveUpgradeSecurityCouncil,
        ProtocolUpgradeHandler::ApproveUpgradeGuardians,
        ProtocolUpgradeHandler::Execute,
        ProtocolUpgradeHandler::ExecuteEmergencyUpgrade,
        // freezability
        ProtocolUpgradeHandler::SoftFreeze,
        ProtocolUpgradeHandler::HardFreeze,
        ProtocolUpgradeHandler::ReinforceFreeze,
        ProtocolUpgradeHandler::ReinforceFreezeOneChain,
        ProtocolUpgradeHandler::Unfreeze,
        ProtocolUpgradeHandler::ReinforceUnfreeze,
        ProtocolUpgradeHandler::ReinforceUnfreezeOneChain,
        // self-upgrades
        //ProtocolUpgradeHandler::UpdateSecurityCouncil,
        //ProtocolUpgradeHandler::UpdateGuardians,
        //ProtocolUpgradeHandler::UpdateEmergencyUpgradeBoard,
        // Guardians
        Guardians::ExtendLegalVeto,
        Guardians::ApproveUpgradeGuardians,
        Guardians::ProposeL2GovernorProposal,
        Guardians::CancelL2GovernorProposal,
        // Emergency upgrades
        EmergencyUpgradeBoard::ExecuteEmergencyUpgrade
    }

    // Security council

    action SecurityCouncil::ApproveUpgradeSecurityCouncil = {
        nondet id = oneOf(getAllUpgradeIDs(evm).union(WrongUpgradeIDs))
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, FunctionApproveUpgradeSecurityCouncil)
        val result = securityCouncil::ApproveUpgradeSecurityCouncil(evm2, id, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action SecurityCouncil::SoftFreeze = {
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, FunctionSoftFreeze)
        val result = securityCouncil::SoftFreeze(evm2, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionSoftFreeze),
            strictFreezeOps' = strictFreezeOps.append(FunctionSoftFreeze),
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action SecurityCouncil::HardFreeze = {
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, FunctionHardFreeze)
        val result = securityCouncil::HardFreeze(evm2, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionHardFreeze),
            strictFreezeOps' = strictFreezeOps.append(FunctionHardFreeze),
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action SecurityCouncil::Unfreeze = {
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, FunctionUnfreeze)
        val result = securityCouncil::Unfreeze(evm2, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionUnfreeze),
            strictFreezeOps' = strictFreezeOps.append(FunctionUnfreeze),
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action SecurityCouncil::SetSoftFreezeThreshold = {
        nondet threshold = oneOf(THRESHOLD)
        nondet validUntil = oneOf(TIMESTAMPS)
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2 = evm.externalCall(sender, SECURITY_COUNCIL_ADDR, FunctionSetSoftFreezeThreshold)
        val result = securityCouncil::SetSoftFreezeThreshold(evm2, threshold, validUntil, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    // Protocol handler

    action ProtocolUpgradeHandler::StartUpgrade = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet calls = oneOf(CALLS)
        nondet executor = oneOf(ALL_ADDRESSES)
        nondet salt = oneOf(SALTS)
        val proposal = { calls: calls, executor: executor, salt: salt }
        val proposalId = keccak256_UpgradeProposal(proposal)
        val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionStartUpgrade)
        val result = protocolUpgradeHandler::StartUpgrade(evm2, proposal)
        val upg1 = upgradeState(result.v.protocolUpgradeHandler, result.v.blockTimestamp, proposalId)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine.put(proposalId, (upg0, upg1, FunctionStartUpgrade)),

        }
    }

    action ProtocolUpgradeHandler::ExtendLegalVeto = {
        nondet sender = oneOf(ALL_SENDERS)
        // non-deterministically choose a proposal and generate its hash
        nondet calls = oneOf(CALLS)
        nondet executor = oneOf(ALL_ADDRESSES)
        nondet salt = oneOf(SALTS)
        val proposal = { calls: calls, executor: executor, salt: salt }
        val proposalId = keccak256_UpgradeProposal(proposal)
        val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExtendLegalVeto)
        val result = protocolUpgradeHandler::ExtendLegalVeto(evm2, proposalId)
        val upg1 = upgradeState(result.v.protocolUpgradeHandler, result.v.blockTimestamp, proposalId)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine.put(proposalId, (upg0, upg1, FunctionExtendLegalVeto)),
        }
    }

    action ProtocolUpgradeHandler::ApproveUpgradeSecurityCouncil = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet calls = oneOf(CALLS)
        nondet executor = oneOf(ALL_ADDRESSES)
        nondet salt = oneOf(SALTS)
        val proposal = { calls: calls, executor: executor, salt: salt }
        val proposalId = keccak256_UpgradeProposal(proposal)
        val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeSecurityCouncil)
        val result = protocolUpgradeHandler::ApproveUpgradeSecurityCouncil(evm2, proposalId)
        val upg1 = upgradeState(result.v.protocolUpgradeHandler, result.v.blockTimestamp, proposalId)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine.put(proposalId, (upg0, upg1, FunctionApproveUpgradeSecurityCouncil)),
        }
    }

    action ProtocolUpgradeHandler::ApproveUpgradeGuardians = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet calls = oneOf(CALLS)
        nondet executor = oneOf(ALL_ADDRESSES)
        nondet salt = oneOf(SALTS)
        val proposal = { calls: calls, executor: executor, salt: salt }
        val proposalId = keccak256_UpgradeProposal(proposal)
        val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionApproveUpgradeGuardians)
        val result = protocolUpgradeHandler::ApproveUpgradeGuardians(evm2, proposalId)
        val upg1 = upgradeState(result.v.protocolUpgradeHandler, result.v.blockTimestamp, proposalId)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine.put(proposalId, (upg0, upg1, FunctionApproveUpgradeGuardians)),
        }
    }

    action ProtocolUpgradeHandler::Execute = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet calls = oneOf(CALLS)
        nondet executor = oneOf(ALL_ADDRESSES)
        nondet salt = oneOf(SALTS)
        val proposal = { calls: calls, executor: executor, salt: salt }
        val proposalId = keccak256_UpgradeProposal(proposal)
        val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecute)
        val result = protocolUpgradeHandler::Execute(evm2, proposal)
        val upg1 = upgradeState(result.v.protocolUpgradeHandler, result.v.blockTimestamp, proposalId)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine.put(proposalId, (upg0, upg1, FunctionExecute)),
        }
    }

    action ProtocolUpgradeHandler::ExecuteEmergencyUpgrade = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet calls = oneOf(CALLS)
        nondet executor = oneOf(ALL_ADDRESSES)
        nondet salt = oneOf(SALTS)
        val proposal = { calls: calls, executor: executor, salt: salt }
        val proposalId = keccak256_UpgradeProposal(proposal)
        val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecuteEmergencyUpgrade)
        val result = protocolUpgradeHandler::ExecuteEmergencyUpgrade(evm2, proposal)
        val upg1 = upgradeState(result.v.protocolUpgradeHandler, result.v.blockTimestamp, proposalId)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = [],
            strictFreezeOps' = [],
            upgradeStateMachine' = upgradeStateMachine.put(proposalId, (upg0, upg1, FunctionExecuteEmergencyUpgrade)),
        }
    }

    action ProtocolUpgradeHandler::UpdateSecurityCouncil = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet newAddr = oneOf(NEW_CONTRACTS_ADDRESSES)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionUpdateSecurityCouncil)
        val result = protocolUpgradeHandler::UpdateSecurityCouncil(evm2, newAddr)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::UpdateGuardians = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet newAddr = oneOf(NEW_CONTRACTS_ADDRESSES)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionUpdateGuardians)
        val result = protocolUpgradeHandler::UpdateGuardians(evm2, newAddr)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::UpdateEmergencyUpgradeBoard = {
        nondet sender = oneOf(ALL_SENDERS)
        nondet newAddr = oneOf(NEW_CONTRACTS_ADDRESSES)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionUpdateEmergencyUpgradeBoard)
        val result = protocolUpgradeHandler::UpdateEmergencyUpgradeBoard(evm2, newAddr)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::SoftFreeze = {
        nondet sender = ALL_SENDERS.oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionSoftFreeze)
        val result = protocolUpgradeHandler::SoftFreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionSoftFreeze),
            strictFreezeOps' = strictFreezeOps.append(FunctionSoftFreeze),
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::HardFreeze = {
        nondet sender = ALL_SENDERS.oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionHardFreeze)
        val result = protocolUpgradeHandler::HardFreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionHardFreeze),
            strictFreezeOps' = strictFreezeOps.append(FunctionHardFreeze),
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::ReinforceFreeze = {
        nondet sender = ALL_SENDERS.oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionReinforceFreeze)
        val result = protocolUpgradeHandler::ReinforceFreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionReinforceFreeze),
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::ReinforceFreezeOneChain = {
        nondet sender = ALL_SENDERS.oneOf()
        nondet chainID = oneOf(hyperchainIds)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionReinforceFreezeOneChain(chainID))
        val result = protocolUpgradeHandler::ReinforceFreezeOneChain(evm2, chainID)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionReinforceFreezeOneChain(chainID)),
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::Unfreeze = {
        nondet sender = ALL_SENDERS.oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionUnfreeze)
        val result = protocolUpgradeHandler::Unfreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionUnfreeze),
            strictFreezeOps' = strictFreezeOps.append(FunctionUnfreeze),
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::ReinforceUnfreeze = {
        nondet sender = ALL_SENDERS.oneOf()
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionReinforceUnfreeze)
        val result = protocolUpgradeHandler::ReinforceUnfreeze(evm2)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionReinforceUnfreeze),
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action ProtocolUpgradeHandler::ReinforceUnfreezeOneChain = {
        nondet sender = ALL_SENDERS.union(NON_MEMBERS).oneOf()
        nondet chainID = oneOf(hyperchainIds)
        val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionReinforceUnfreezeOneChain(chainID))
        val result = protocolUpgradeHandler::ReinforceUnfreezeOneChain(evm2, chainID)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps.append(FunctionReinforceUnfreezeOneChain(chainID)),
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    // Guardians

    action Guardians::ExtendLegalVeto = {
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        nondet _id = oneOf(ids)
        val evm2: EvmState = evm.externalCall(sender, GUARDIANS_ADDR, FunctionExtendLegalVeto)
        val result = guardians::ExtendLegalVeto(evm2, AbiInt(_id), signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action Guardians::ApproveUpgradeGuardians = {
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2: EvmState = evm.externalCall(sender, GUARDIANS_ADDR, FunctionApproveUpgradeGuardians)
        nondet _id = oneOf(ids)
        val result = guardians::ApproveUpgradeGuardians(evm2, AbiInt(_id), signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action Guardians::ProposeL2GovernorProposal = {
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2: EvmState = evm.externalCall(sender, GUARDIANS_ADDR, FunctionProposeL2GovernorProposal)
        nondet l2Proposal = L2_PROPOSALS.oneOf()
        nondet txRequest = TX_REQUESTS.oneOf()
        val result = guardians::ProposeL2GovernorProposal(evm2, l2Proposal, txRequest, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    action Guardians::CancelL2GovernorProposal = {
        nondet sender = ALL_SENDERS.oneOf()
        nondet signers = ALL_MEMBERS.powerset().oneOf()
        nondet signatures = ALL_MEMBERS.powerset().oneOf()
        val evm2: EvmState = evm.externalCall(sender, GUARDIANS_ADDR, FunctionCancelL2GovernorProposal)
        nondet l2Proposal = L2_PROPOSALS.oneOf()
        nondet txRequest = TX_REQUESTS.oneOf()
        val result = guardians::CancelL2GovernorProposal(evm2, l2Proposal, txRequest, signers, signatures)
        all {
            isOk(result),
            evm' = result.v,
            freezeOps' = freezeOps,
            strictFreezeOps' = strictFreezeOps,
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    // EmergencyUpgradeBoard

    action EmergencyUpgradeBoard::ExecuteEmergencyUpgrade = {
        nondet sender = ALL_SENDERS.oneOf()
        val evm2: EvmState = evm.externalCall(sender, EMERGENCY_UPGRADE_BOARD_ADDR, FunctionExecuteEmergencyUpgrade)
        nondet calls = CALLS.oneOf()
        nondet salt = SALTS.oneOf()
        nondet _guardiansSignatures = ALL_MEMBERS.powerset().oneOf()
        nondet _securityCouncilSignatures = ALL_MEMBERS.powerset().oneOf()
        nondet _zkFoundationSignatures = ALL_MEMBERS.powerset().oneOf()
        val result = emergencyUpgradeBoard::ExecuteEmergencyUpgrade(evm2, calls, salt, _guardiansSignatures, _securityCouncilSignatures, _zkFoundationSignatures)
        all {
            isOk(result),
            evm' = result.v,
            // Any upgrade resets the freeze log.
            freezeOps' = [],
            strictFreezeOps' = [],
            upgradeStateMachine' = upgradeStateMachine,
        }
    }

    // -------------------------------------------------------------------------
    // Invariants to check
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Access control

    val onlySecurityCouncilIsAllowedToCallSoftFreezeInv =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionSoftFreeze)
                implies (e.caller == SECURITY_COUNCIL_ADDR)
        })

    val onlySecurityCouncilIsAllowedToCallUnfreezeInv =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionUnfreeze)
                implies (e.caller == SECURITY_COUNCIL_ADDR)
        })

    val onlySecurityCouncilIsAllowedToCallHardFreezeInv =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionHardFreeze)
                implies (e.caller == SECURITY_COUNCIL_ADDR)
        }) 
    
    val onlySecurityCouncilIsAllowedToCallApproveUpgradeSecurityCouncil =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionApproveUpgradeSecurityCouncil)
                implies (e.caller == SECURITY_COUNCIL_ADDR)
        }) 

    val onlyGuardiansIsAllowedToCallExtendLegalVetoInv =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionExtendLegalVeto)
                implies (e.caller == GUARDIANS_ADDR)
        }) 

    val onlyGuardiansIsAllowedToCallApproveUpgradeGuardiansInv =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionApproveUpgradeGuardians)
                implies (e.caller == GUARDIANS_ADDR)
        })
    
    val onlyEmergencyUpgradeBoardIsAllowedToCallExecuteEmergencyUpgrade =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionExecuteEmergencyUpgrade)
                implies (e.caller == EMERGENCY_UPGRADE_BOARD_ADDR)
        })

    val onlyProtocolUpdateHandlerIsAllowedToCallUpdateSecurityCouncil =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionUpdateSecurityCouncil)
                implies (e.caller == PROTOCOL_UPGRADE_HANDLER_ADDR)
        })
    
    val onlyProtocolUpdateHandlerIsAllowedToCallUpdateGuardians =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionUpdateGuardians)
                implies (e.caller == PROTOCOL_UPGRADE_HANDLER_ADDR)
        })
    
    val onlyProtocolUpdateHandlerIsAllowedToCallUpdateEmergencyUpgradeBoard =
        evm.ghostCallHistory.calls.indices().forall(i => {
            val e = evm.ghostCallHistory.calls[i]
            (e.callee == PROTOCOL_UPGRADE_HANDLER_ADDR) and (e.method == FunctionUpdateEmergencyUpgradeBoard)
                implies (e.caller == PROTOCOL_UPGRADE_HANDLER_ADDR)
        })


    val accessControlPolicyInv = and {
        // security council
        onlySecurityCouncilIsAllowedToCallSoftFreezeInv,
        onlySecurityCouncilIsAllowedToCallHardFreezeInv,
        onlySecurityCouncilIsAllowedToCallApproveUpgradeSecurityCouncil,
        onlySecurityCouncilIsAllowedToCallUnfreezeInv,
        // guardians
        onlyGuardiansIsAllowedToCallExtendLegalVetoInv,
        onlyGuardiansIsAllowedToCallApproveUpgradeGuardiansInv,
        // protocolUpgradeHandler
        onlyProtocolUpdateHandlerIsAllowedToCallUpdateSecurityCouncil,
        onlyProtocolUpdateHandlerIsAllowedToCallUpdateGuardians,
        onlyProtocolUpdateHandlerIsAllowedToCallUpdateEmergencyUpgradeBoard,
        // emergencyUpgradeBoard
        onlyEmergencyUpgradeBoardIsAllowedToCallExecuteEmergencyUpgrade
    }

    /// Guardians requires exactly 8 members and
    /// SecurityCouncil requires exactly 12 members
    val membersNumbersCorrectInv = and {
        evm.securityCouncil.multisig.members.size() == 12,
        evm.guardians.multisig.members.size() == 8,
    }

    // Zero address can't be a member while multisig initialization
    val noZeroAddrInMultisig = and {
        not(evm.securityCouncil.multisig.members.contains(ZERO_ADDRESS)),
        not(evm.guardians.multisig.members.contains(ZERO_ADDRESS)),
        not(evm.zkFoundation.members.contains(ZERO_ADDRESS))
    }

    // -------------------------------------------------------------------------
    // Upgradability related invariants

    val upgradabilityInv = and {
        upgradeIsExecutedIfApprovedByGuardiansAndSecurityCouncilInv,
        emergencyUpgradeUnfreezesStateInv,
        regularUpgradeDoesnotUnfreezeStateInv,
        emergencyUpgradeMaybeExecutedInFrozenInv,
        emergencyUpgradeMustBeExecutedOnce,
        upgradeMustBeExecutedOnce,
        freezesRequireEmergencyUpgradeInv,
        upgradesAllowedOpsInv,
        updateSecurityCouncilInv,
        updateGuardiansInv,
        updateUpdateEmergencyUpgradeBoardInv
    }
    // The invariant should as follows: if there is an upgrade then we have seen ordered approval and execution calls
    val upgradeIsExecutedIfApprovedByGuardiansAndSecurityCouncilInv = {
        val upgrades = evm.protocolUpgradeHandler.upgradeStatus
        
        upgrades.keys().forall(id => {
            val upgrade = upgrades.get(id)
            upgrade.executed implies ( or {
                // While the ZKsync protocol is frozen, an upgrade to address the threat may be passed as an Emergency Upgrade.
    
                and {
                    evm.emittedEvents.indices().exists(i => and {
                        evm.emittedEvents[i] == EventEmergencyUpgradeExecuted(id),
                    }),

                },
                // After a Soft Freeze and/or a Hard Freeze has been initiated,
                // an Emergency Upgrade must be passed before any subsequent freezes may be initiated.
    
                and {
                    not(evm.zkFrozen),
                    evm.emittedEvents.indices().exists(i => and {
                        evm.emittedEvents[i] == EventUpgradeExecuted(id),

                        or {
                            evm.emittedEvents.indices().exists(ii => and {
                                ii < i,
                                evm.emittedEvents[ii] == EventUpgradeApprovedBySecurityCouncil(id),
                            }),
                            
                            evm.emittedEvents.indices().exists( iii => and {
                                evm.emittedEvents[iii] == EventUpgradeApprovedByGuardians(id),
                                iii < i,
                            })

                        },

                    }),
                }
            })
        })
    }

    // Once frozen, an Emergency Upgrade may be executed in order to remove the freeze and/or initiate a subsequent freeze.
    // Also, An Emergency Upgrade during a freeze may include a message executed solely
    // for the purpose of allowing the Security Council to initiate a subsequent freeze.
    val emergencyUpgradeUnfreezesStateInv = {
        val sender = EMERGENCY_UPGRADE_BOARD_ADDR
        val executor = EMERGENCY_UPGRADE_BOARD_ADDR
        CALLS.forall(calls => {
            SALTS.forall(salt => {
                val proposal = { calls: calls, executor: executor, salt: salt }
                val proposalId = keccak256_UpgradeProposal(proposal)
                val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecuteEmergencyUpgrade)
                val result = protocolUpgradeHandler::ExecuteEmergencyUpgrade(evm2, proposal)
                val evm3 = result.v
                
                val isFrozen = evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle.in(Set(FreezeStatusHard, FreezeStatusSoft))
                val isNotExecuted = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId) != UpgradeStateDone
                // Once frozen, ...
                (isFrozen and isNotExecuted) implies and {
                    // ...an Emergency Upgrade may be executed in order to remove the freeze
                    isOk(result),
                    evm3.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusNone,
                    // ...and/or initiate a subsequent freeze (soft freeze)
                    {
                        val evm4 = evm3.externalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionSoftFreeze)
                        val result4 = protocolUpgradeHandler::SoftFreeze(evm4)
                        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusNone) implies isOk(result4)
                    },
                    // ...and/or initiate a subsequent freeze (hard freeze)
                    {
                        val evm5 = evm3.externalCall(SECURITY_COUNCIL_ADDR, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionHardFreeze)
                        val result5 = protocolUpgradeHandler::HardFreeze(evm5)
                        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusNone) implies isOk(result5)
                    }
                }
            })
        })
    }

    // Regular Upgrade execution doesn't affect freezing.
    val regularUpgradeDoesnotUnfreezeStateInv = {
        val sender = ANY_ADDRESS
        val executor = ANY_ADDRESS
        CALLS.forall(calls => {
            SALTS.forall(salt => {
                val proposal = { calls: calls, executor: executor, salt: salt }
                val proposalId = keccak256_UpgradeProposal(proposal)
                val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecuteEmergencyUpgrade)
                val result = protocolUpgradeHandler::Execute(evm2, proposal)
                isOk(result) implies result.v.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle
            })
        })
    }

    // This property should be violated.
    // TODO: find out why quint produces "Operator EQ cannot be applied to arguments of types (Bool, Str)"
    temporal upgradeUnfreezeActionProp = {
        always({
            and {
                next(evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle) == FreezeStatusNone,
                evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle != FreezeStatusNone
            } implies {
                next(evm.ghostCallHistory.calls[evm.ghostCallHistory.calls.length() - 1].method) == FunctionExecuteEmergencyUpgrade
            }
        })
    }

    // An Emergency Upgrade may be executed, whether a freeze is active or not, with sufficient approval from the Emergency Upgrade Multisig.
    val emergencyUpgradeMaybeExecutedInFrozenInv = {
        val sender = EMERGENCY_UPGRADE_BOARD_ADDR
        val executor = EMERGENCY_UPGRADE_BOARD_ADDR
        CALLS.forall(calls => {
            SALTS.forall(salt => {
                val proposal = { calls: calls, executor: executor, salt: salt }
                val proposalId = keccak256_UpgradeProposal(proposal)
                val upg0 = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, proposalId)
                val evm2 = evm.externalCall(sender, PROTOCOL_UPGRADE_HANDLER_ADDR, FunctionExecuteEmergencyUpgrade)
                val result = protocolUpgradeHandler::ExecuteEmergencyUpgrade(evm2, proposal)
                or {
                    upg0 != UpgradeStateNone,
                    isOk(result)
                }
            })
        })
    }

    // In order to execute an Emergency Upgrade with the Emergency Upgrade Multisig,
    // all three (3) Emergency Upgrade Signers must each reach the signing threshold on their respective multisig
    val emergencyUpgradeMultisigInv = {
        val sender = EMERGENCY_UPGRADE_BOARD_ADDR
        val executor = EMERGENCY_UPGRADE_BOARD_ADDR
        CALLS.forall(calls => {
            SALTS.forall(salt => {
                GUARDIAN_MEMBERS.powerset().forall(guardians => {
                    SECURITY_COUNCIL_MEMBERS.powerset().forall(council => {
                        ZK_FOUNDATION_MEMBERS.powerset().forall(foundation => {
                            val proposal = { calls: calls, executor: executor, salt: salt }
                            val proposalId = keccak256_UpgradeProposal(proposal)
                            val evm2 = evm.externalCall(sender, EMERGENCY_UPGRADE_BOARD_ADDR, FunctionExecuteEmergencyUpgrade)
                            val result = emergencyUpgradeBoard::ExecuteEmergencyUpgrade(evm2, calls, salt, guardians, council, foundation)
                            
                            isOk(result) implies and {
                                guardians.size() >= 5,
                                council.size() >= 9,
                                foundation.size() >= 5,
                            }
                        })
                    })
                })
            })
        })
    }

    // An Emergency Upgrade cannot be executed twice: there are no two equal executed emergency upgrades.
    val emergencyUpgradeMustBeExecutedOnce =
        evm.emittedEvents.indices().forall(i => {
            evm.emittedEvents.indices().forall(j => {
                match (evm.emittedEvents[i]) {
                | EventEmergencyUpgradeExecuted(id1) =>
                    match (evm.emittedEvents[j]) {
                    | EventEmergencyUpgradeExecuted(id2) =>
                        (id1 == id2 implies i == j)

                    | _ => true
                    }

                | _ => true    
                }
        })
    })

    // An Upgrade cannot be executed twice: there are no two equal executed upgrades.
    val upgradeMustBeExecutedOnce =
        evm.emittedEvents.indices().forall(i => {
            evm.emittedEvents.indices().forall(j => {
                match (evm.emittedEvents[i]) {
                | EventUpgradeExecuted(id1) =>
                    match (evm.emittedEvents[j]) {
                        | EventUpgradeExecuted(id2) =>
                            (id1 == id2 implies i == j)

                        | _ => true
                    }

                | _ => true    
                }
        })
    })

    // After a Soft Freeze and a Hard Freeze have been initiated,
    // an Emergency Upgrade must be passed before any subsequent freezes may be initiated.
    val freezesRequireEmergencyUpgradeInv =
        def hasEmergencyUpgrade(eventIndices) = {
            eventIndices.exists(k => {
                match (evm.emittedEvents[k]) {
                | EventEmergencyUpgradeExecuted(_) => true
                | _ => false
                }
            })
        }
        evm.emittedEvents.indices().forall(i => {
            evm.emittedEvents.indices().forall(j => or {
                j <= i,
                match (evm.emittedEvents[i]) {
                | EventHardFreeze(id1) =>
                    match (evm.emittedEvents[j]) {
                        | EventSoftFreeze(id2) =>
                            hasEmergencyUpgrade(evm.emittedEvents.indices().filter(k => i < k and k < j))

                        | EventHardFreeze(id2) =>
                            hasEmergencyUpgrade(evm.emittedEvents.indices().filter(k => i < k and k < j))

                        | _ => true
                    }

                | _ => true    
                }
        })
    })

    val allowedUpgradeOps = [
        (UpgradeStateNone, UpgradeStateNone, FunctionStartUpgrade),
        (UpgradeStateNone, UpgradeStateLegalVetoPeriod, FunctionStartUpgrade),
        // (UpgradeStateLegalVetoPeriod, x!=UpgradeStateLegalVetoPeriod, FunctionExtendLegalVeto)
        // not possible since ExtendLegalVeto increases legalVetoTime
        (UpgradeStateLegalVetoPeriod, UpgradeStateLegalVetoPeriod, FunctionExtendLegalVeto),
        // (UpgradeStateWaiting, UpgradeStateReady, FunctionApproveUpgradeSecurityCouncil),
        // is not here since we calculate the next state for the same blockTimestamp
        (UpgradeStateWaiting, UpgradeStateExecutionPending, FunctionApproveUpgradeSecurityCouncil),
        (UpgradeStateWaiting, UpgradeStateWaiting, FunctionApproveUpgradeGuardians),

        (UpgradeStateReady, UpgradeStateDone, FunctionExecute),
        (UpgradeStateNone, UpgradeStateDone, FunctionExecuteEmergencyUpgrade),
    ]

    val upgradesAllowedOpsInv: bool = {
        val ids = upgradeStateMachine.keys()
        ids.forall( id =>
            allowedUpgradeOps.has_elem(upgradeStateMachine.get(id))
        )
    }

    // only the protocol upgrade handler can (successfully) call updateSecurityCouncil
    val updateSecurityCouncilInv = {
        evm.ghostCallHistory.calls.indices().forall(i => {
            val call = evm.ghostCallHistory.calls[i]
            (call.callee == PROTOCOL_UPGRADE_HANDLER_ADDR and call.method == FunctionUpdateSecurityCouncil)
                implies (call.caller == PROTOCOL_UPGRADE_HANDLER_ADDR)
        })
    }

    val updateGuardiansInv = {
        evm.ghostCallHistory.calls.indices().forall(i => {
            val call = evm.ghostCallHistory.calls[i]
            (call.callee == PROTOCOL_UPGRADE_HANDLER_ADDR and call.method == FunctionUpdateGuardians)
                implies (call.caller == PROTOCOL_UPGRADE_HANDLER_ADDR)
        })
    }

    val updateUpdateEmergencyUpgradeBoardInv = {
        evm.ghostCallHistory.calls.indices().forall(i => {
            val call = evm.ghostCallHistory.calls[i]
            (call.callee == PROTOCOL_UPGRADE_HANDLER_ADDR and call.method == FunctionUpdateEmergencyUpgradeBoard)
                implies (call.caller == PROTOCOL_UPGRADE_HANDLER_ADDR)
        })
    }

    // TODO: this invariant is violated
    // https://github.com/zksync-association/zk-governance/pull/4/files#r1711102202
    val upgradeStatusCreationTimestampIsZeroWhenNoneInv = {
        val status = evm.protocolUpgradeHandler.upgradeStatus
        status.keys().forall(id => {
            val state = upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, id)
            status.get(id).creationTimestamp == 0 iff state == UpgradeStateNone
        })
    }

    // -------------------------------------------------------------------------
    // Freezability related invariants

    /// This value is automatically reset to 9 after each soft freeze, but it can be
    /// set by the 9 SC members and requires to be not bigger than 9, and not smaller than 1.
    val softFreezeThresholdNotBiggerThanNineInv = and {
        evm.securityCouncil.softFreezeThreshold <= 9,
        evm.securityCouncil.softFreezeThreshold > 0
    };

    val laxedFreezeDisallowedOpsInv = {
        freezeOps.length() > 1 implies
        indices(freezeOps).forall(i => {
            indices(freezeOps).forall(j => and { 
                i < j implies
                and {
                    freezeOps[i] == FunctionHardFreeze implies not(Set(FunctionHardFreeze, FunctionSoftFreeze).contains(freezeOps[j])),
                    freezeOps[i] == FunctionSoftFreeze implies freezeOps[j] != FunctionSoftFreeze,
                    freezeOps[i] == FunctionUnfreeze implies freezeOps[i+1] != FunctionUnfreeze,
                }
            })
        })
    }

    val freezeLaxedDisallowedOpsInv: bool = {
        val ids = upgradeStateMachine.keys()
        ids.forall( id =>
            allowedUpgradeOps.has_elem(upgradeStateMachine.get(id))
        )
    }

    // This invariant exhaustively enumerates all possible allowed sequence of strict *-freeze operations.
    val strictFreezeAllowedOpsInv = or {
        strictFreezeOps == [],
        strictFreezeOps == [FunctionSoftFreeze],
        strictFreezeOps == [FunctionHardFreeze],
        strictFreezeOps == [FunctionSoftFreeze, FunctionHardFreeze],
        strictFreezeOps == [FunctionHardFreeze, FunctionUnfreeze],
        strictFreezeOps == [FunctionSoftFreeze, FunctionHardFreeze, FunctionUnfreeze],
        strictFreezeOps == [FunctionSoftFreeze, FunctionUnfreeze],
        strictFreezeOps == [FunctionSoftFreeze, FunctionUnfreeze, FunctionHardFreeze],
        strictFreezeOps == [FunctionSoftFreeze, FunctionUnfreeze, FunctionHardFreeze, FunctionUnfreeze],
    }

    // Unidirectional freeze from Soft -> Hard is allowed, but not the other way around
    val hardToSoftFreezeNotAllowedInv = {
        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft)
            implies freezeOps.indices().forall(i => freezeOps[i] != FunctionHardFreeze)
    }

    val softFreezeInv = {
        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft)
            implies freezeOps.indices().filter(i => freezeOps[i] == FunctionSoftFreeze).size() == 1
    }

    val hardFreezeInv = {
        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusHard)
            implies freezeOps.indices().filter(i => freezeOps[i] == FunctionHardFreeze).size() == 1
    }

    val afterSoftFreezeInv = {
        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusAfterSoftFreeze)
            implies and {
                freezeOps.indices().filter(i => freezeOps[i] == FunctionSoftFreeze).size() == 1,
                freezeOps.indices().filter(i => freezeOps[i] == FunctionUnfreeze).size() >= 1,
            }
    }

    val afterHardFreezeInv = {
        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusAfterHardFreeze)
        implies and {
            freezeOps.indices().filter(i => freezeOps[i] == FunctionHardFreeze).size() == 1,
            freezeOps.indices().filter(i => freezeOps[i] == FunctionUnfreeze).size() >= 1,
        }
    }

    val freezeStatusNoneInv = {
        (evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusNone)
            implies freezeOps == []
    }

    // After a Soft Freeze and/or a Hard Freeze has been initiated, the Security Council may unfreeze (“Unfreeze”)
    // the contracts at their discretion, with the approval of nine (9) Signers on the Security Multisig.
    val securityCouncilMayUnfreezeInv = {
        val validUntil = evm.blockTimestamp + 1
        SECURITY_COUNCIL_MEMBERS_QUORUM.forall(someMembers => or {
            val freezeStatus = evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle
            freezeStatus != FreezeStatusSoft and freezeStatus != FreezeStatusHard,
            isOk(securityCouncil::Unfreeze(evm, validUntil, someMembers, someMembers))
        })
    }

    // unfreeze is allowed to call from any address after the freezing period has been reached
    val anyAddressMayUnfreezeInv = {
        val freezeStatus = evm.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle
        and {
            evm.blockTimestamp > evm.protocolUpgradeHandler.protocolFrozenUntil,
            freezeStatus.in(Set(FreezeStatusSoft, FreezeStatusHard))
        } implies
            isOk(protocolUpgradeHandler::Unfreeze(evm))
    }

    val freezeSafetyFastInv = all {
        laxedFreezeDisallowedOpsInv,
        strictFreezeAllowedOpsInv,
        freezeLaxedDisallowedOpsInv,
        hardToSoftFreezeNotAllowedInv,
        afterSoftFreezeInv,
        afterHardFreezeInv,
        softFreezeInv,
        hardFreezeInv,
        freezeStatusNoneInv,
        anyAddressMayUnfreezeInv,
        zkFrozenUntilWeakInv,
    }

    val freezeSafetySlowInv = and {
        securityCouncilMayUnfreezeInv
    }

    // A weak version of zkFrozenUntilStrongInv:
    // If ZK is frozen, then the unfreezing deadline has not been met.
    // Alternatively, if the unfreezing deadline has not been met, then ZK is frozen.
    val zkFrozenUntilWeakInv = or {
        (evm.blockTimestamp > evm.protocolUpgradeHandler.protocolFrozenUntil),
        evm.zkFrozen
    }

    // All invariants
    val all_invariants = all {
        accessControlPolicyInv,
        freezeSafetyFastInv, freezeSafetySlowInv,
        softFreezeThresholdNotBiggerThanNineInv,
        noZeroAddrInMultisig,
        membersNumbersCorrectInv,
        upgradabilityInv
    }
        
    /// -------------------------------------------------------------------------
    // Falsy invariants to check reachability of certain states
    /// -------------------------------------------------------------------------

    val noneToLegalVetoPeriodExample = {
        upgradeStateMachine.keys().forall(id => {
            val upgradeOp = upgradeStateMachine.get(id)
            or {
                upgradeOp._1 != UpgradeStateNone,
                upgradeOp._2 != UpgradeStateLegalVetoPeriod,
            }
        })
    }

    val legalVetoPeriodToExecutionPendingExample = {
        upgradeStateMachine.keys().forall(id => {
            val upgradeOp = upgradeStateMachine.get(id)
            or {
                upgradeOp._1 != UpgradeStateLegalVetoPeriod,
                upgradeOp._2 != UpgradeStateExecutionPending,
            }
        })
    }
    
    val timeBelow1000Example =
        evm.blockTimestamp < 1000

    val zkFrozenExample =
        not(evm.zkFrozen)

    val isSoftFreezeCalled = {
        not(freezeOps.has_elem(FunctionSoftFreeze))
    }

    val isHardFreezeCalled = {
        not(freezeOps.has_elem(FunctionHardFreeze))
    }

    val noProposalsInWaitingState = {
        val ids = evm.protocolUpgradeHandler.upgradeStatus.keys()
        ids.forall( id =>
            not(upgradeState(evm.protocolUpgradeHandler, evm.blockTimestamp, id) == UpgradeStateWaiting)
        )
    } 

    val allowedUpgradeOpsNo = [
        (UpgradeStateNone, UpgradeStateNone, FunctionStartUpgrade),
        (UpgradeStateNone, UpgradeStateLegalVetoPeriod, FunctionStartUpgrade),
        (UpgradeStateLegalVetoPeriod, UpgradeStateLegalVetoPeriod, FunctionExtendLegalVeto),
        (UpgradeStateWaiting, UpgradeStateExecutionPending, FunctionApproveUpgradeSecurityCouncil),
        (UpgradeStateWaiting, UpgradeStateWaiting, FunctionApproveUpgradeGuardians),
        (UpgradeStateReady, UpgradeStateDone, FunctionExecute),
        (UpgradeStateNone, UpgradeStateNone, FunctionExecuteEmergencyUpgrade),
    ]


    val upgradeInState: bool = {
        val ids = upgradeStateMachine.keys()
        ids.forall( id =>
            allowedUpgradeOpsNo.has_elem(upgradeStateMachine.get(id))
        )
    }
}