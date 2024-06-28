// -*- mode: Bluespec; -*-
module protocolUpgradeHandler {
    import hashing.* from "./hashing"
    import state.* from "./state"
    import types.* from "./types"

    /// -------------------------------------------------------------------------------------------
    /// ProtocolUpgradeHandler constants
    /// -------------------------------------------------------------------------------------------

    /// @dev Duration of the standard legal veto period.
    pure val STANDARD_LEGAL_VETO_PERIOD = 3 * 24 * 60 * 60;

    /// @dev Duration of the extended legal veto period.
    pure val EXTENDED_LEGAL_VETO_PERIOD = 7 * 24 * 60 * 60;

    /// @dev The mandatory delay period before an upgrade can be executed.
    /// This period is intended to provide a buffer after an upgrade's final approval and before its execution,
    /// allowing for final reviews and preparations for devs and users.
    pure val UPGRADE_DELAY_PERIOD = 1 * 24 * 60 * 60;

    /// @dev Time limit for an upgrade proposal to be approved by guardians or expire, and the waiting period for execution post-guardians approval.
    /// If the Security Council approves, the upgrade can proceed immediately; otherwise,
    /// the proposal will expire after this period if not approved, or wait this period after guardians approval.
    pure val UPGRADE_WAIT_OR_EXPIRE_PERIOD = 30 * 24 * 60 * 60;

    /// @dev Duration of a soft freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to decide whether they want to
    /// do hard freeze and protocol upgrade.
    pure val SOFT_FREEZE_PERIOD = 12 * 60 * 60;

    /// @dev Duration of a hard freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to perform emergency protocol upgrade.
    pure val HARD_FREEZE_PERIOD = 7 * 24 * 60 * 60;

    /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting governor.
    /// @param _securityCouncil The address to be assigned as the Security Council of the contract.
    /// @param _guardians The address to be assigned as the guardians of the contract.
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    pure def newProtocolUpgradeHandler(): Result[ProtocolUpgradeHandlerState] = {
        ok({
            securityCouncil: "securityCouncil address",
            emergencyUpgradeBoard: "emergencyUpgradeBoard address",
            guardians: "guardians address",
            upgradeStatus: Map(),
            lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
            protocolFrozenUntil: 0,
        })
    }

    /// @notice Initiates a soft protocol freeze.
    pure def protocolUpgradeHandlerSoftFreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(self.lastFreezeStatusInUpgradeCycle == FreezeStatusNone, "Protocol already frozen")
            .andRequire(evm.msgSender() == SECURITY_COUNCIL_ADDR, "Only Security Council is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val self2 = {
                ...self,
                lastFreezeStatusInUpgradeCycle: FreezeStatusSoft,
                protocolFrozenUntil: evm.blockTimestamp + SOFT_FREEZE_PERIOD
            }
            // _freeze pauses multiple contracts unconditionally. We set zkFrozen to true to reflect that.
            ok({ ...evm, protocolUpgradeHandler: self2, zkFrozen: true })
        }
    }

    /// @notice Initiates a hard protocol freeze.
    pure def protocolUpgradeHandlerHardFreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val freezeStatus = self.lastFreezeStatusInUpgradeCycle
        val e = require(freezeStatus == FreezeStatusNone
                or freezeStatus == FreezeStatusSoft or freezeStatus == FreezeStatusAfterSoftFreeze,
            "Protocol can't be hard frozen")
            .andRequire(evm.msgSender() == SECURITY_COUNCIL_ADDR, "Only Security Council is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val self2 = {
                ...self,
                lastFreezeStatusInUpgradeCycle: FreezeStatusHard,
                protocolFrozenUntil: evm.blockTimestamp + HARD_FREEZE_PERIOD
            }
            // _freeze pauses multiple contracts unconditionally. We set zkFrozen to true to reflect that.
            ok({ ...evm, protocolUpgradeHandler: self2, zkFrozen: true })
        }
    }

    /// @dev Reinforces the freezing state of the protocol if it is already within the frozen period. This function
    /// can be called by anyone to ensure the protocol remains in a frozen state, particularly useful if there is a need
    /// to confirm or re-apply the freeze due to partial or incomplete application during the initial freeze.
    pure def protocolUpgradeHandlerReinforceFreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.blockTimestamp<= self.protocolFrozenUntil, "Protocol should be already frozen")
        if (e != "") {
            err(evm, e)
        } else {
            // _freeze pauses multiple contracts unconditionally. We set zkFrozen to true to reflect that.
            ok({ ...evm, zkFrozen: true })
        }
    }

    /// @dev Unfreezes the protocol and resumes normal operations.
    pure def protocolUpgradeHandlerUnfreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require((evm.msgSender() == SECURITY_COUNCIL_ADDR) or
                    ((self.protocolFrozenUntil != 0) and (evm.blockTimestamp > self.protocolFrozenUntil)),
                "Only Security Council is allowed to call this function")
            .andRequire(self.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft
                        or self.lastFreezeStatusInUpgradeCycle == FreezeStatusHard, "Unexpected last freeze status")
        if (e != "") {
            err(evm, e)
        }
        else {
            val self2 = {
                    ...self,
                    lastFreezeStatusInUpgradeCycle:
                        if (self.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft) {
                            FreezeStatusAfterSoftFreeze
                        } else {
                            FreezeStatusAfterHardFreeze
                        },
                    protocolFrozenUntil: 0
                }
            ok({ ...evm, protocolUpgradeHandler: self2, zkFrozen: false })
        }
    }

    /// @dev Reinforces the unfreeze for protocol if it is not in the freeze mode. This function can be called
    /// by anyone to ensure the protocol remains in an unfrozen state, particularly useful if there is a need
    /// to confirm or re-apply the unfreeze due to partial or incomplete application during the initial unfreeze.
    pure def protocolUpgradeHandlerReinforceUnfreeze(evm: EvmState): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(self.protocolFrozenUntil == 0, "Protocol should be already unfrozen")
        if (e != "") {
            err(evm, e)
        } else {
            ok({ ...evm, zkFrozen: false })
        }
    }

    // TODO: verify the function
    pure def upgradeState(self: ProtocolUpgradeHandlerState, blockTimestamp: Uint256, _id: AbiElem): UpgradeState = {
        val upg = self.upgradeStatus.get(_id);

        // Upgrade doesn't exist
        if (upg.creationTimestamp == 0) {
            UpgradeStateNone
        } else {
            // Upgrade already executed
            if (upg.executed) {
                UpgradeStateDone
            } else {
                // Legal veto period
                val legalVetoTime: Uint256 = if (upg.guardiansExtendedLegalVeto == true) {
                    EXTENDED_LEGAL_VETO_PERIOD
                } else {
                    STANDARD_LEGAL_VETO_PERIOD
                }

                if (blockTimestamp < upg.creationTimestamp + legalVetoTime) {
                    UpgradeStateLegalVetoPeriod
                } else {
                    val waitOrExpiryTimestamp = upg.creationTimestamp + legalVetoTime + UPGRADE_WAIT_OR_EXPIRE_PERIOD;
                    
                    if (blockTimestamp >= waitOrExpiryTimestamp) {
                        if (not(upg.guardiansApproval)) {
                            UpgradeStateCanceled
                        } else {
                            val readyWithGuardiansTimestamp = waitOrExpiryTimestamp + UPGRADE_DELAY_PERIOD;
                            if (blockTimestamp >= readyWithGuardiansTimestamp)  {
                                UpgradeStateReady
                            } else {
                                UpgradeStateExecutionPending
                            }
                        }

                    } else {
                        if (upg.securityCouncilApprovalTimestamp == 0) {
                            UpgradeStateWaiting
                        } else {
                            val readyWithSecurityCouncilTimestamp = upg.securityCouncilApprovalTimestamp + UPGRADE_DELAY_PERIOD;
                            if (blockTimestamp >= readyWithSecurityCouncilTimestamp) {
                                UpgradeStateReady
                            } else {
                                UpgradeStateExecutionPending
                            }
                        }
                    }
                }
            }
        }
    }

    /// @dev Updates the address of the Security Council.
    /// @param _newSecurityCouncil The address of the new Security Council.
    pure def  protocolUpgradeHandlerUpdateSecurityCouncil(evm: EvmState, _newSecurityCouncil: Address): Result[EvmState] =  {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.msgSender() == PROTOCOL_UPGRADE_HANDLER_ADDR, "Only upgrade handler contract itself is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            pure val self2 = {
                ...self,
                securityCouncil: _newSecurityCouncil
            }
            ok({ ...evm, protocolUpgradeHandler: self2 })
        }
    }

    /// @dev Updates the address of the guardians.
    /// @param _newGuardians The address of the guardians.
    pure def  protocolUpgradeHandlerUpdateGuardians(evm: EvmState, _newGuardians: Address): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.msgSender() == PROTOCOL_UPGRADE_HANDLER_ADDR, "Only upgrade handler contract itself is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            pure val self2 = {
                ...self,
                guardians: _newGuardians
            }
            ok({ ...evm, protocolUpgradeHandler: self2 })
        }
    }

    /// @dev Updates the address of the emergency upgrade board.
    /// @param _newEmergencyUpgradeBoard The address of the guardians.
    pure def protocolUpgradeHandlerUpdateEmergencyUpgradeBoard(evm: EvmState, _newEmergencyUpgradeBoard: Address): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e = require(evm.msgSender() == PROTOCOL_UPGRADE_HANDLER_ADDR, "Only upgrade handler contract itself is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            pure val self2 = {
                ...self,
                emergencyUpgradeBoard: _newEmergencyUpgradeBoard
            }
            ok({ ...evm, protocolUpgradeHandler: self2 })
        }
    }

    /// @notice Initiates the upgrade process by verifying an L2 voting decision.
    /// @dev This function decodes and validates an upgrade proposal message from L2, setting the initial state for the upgrade process.
    /// @param _l2BatchNumber The batch number of the L2 transaction containing the upgrade proposal.
    /// @param _l2MessageIndex The index of the message within the L2 batch.
    /// @param _l2TxNumberInBatch The transaction number of the upgrade proposal in the L2 batch.
    /// @param _proof Merkle proof verifying the inclusion of the upgrade message in the L2 batch.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    pure def protocolUpgradeHandlerStartUpgrade(evm: EvmState, _proposal: UpgradeProposal): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e1 = require(_proposal.executor != self.emergencyUpgradeBoard, "Emergency Upgrade Board can't execute usual upgrade")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val id = keccak256_UpgradeProposal(_proposal)
            val upgState: UpgradeState = upgradeState(self, evm.blockTimestamp, id)
            val e2 = require(upgState == UpgradeStateNone, "Upgrade with this id already exists")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(id, old => {
                        ...old,
                        creationTimestamp: evm.blockTimestamp,
                    })
                }

                ok({ ...evm, protocolUpgradeHandler: self2 })
            }

        }
    }

    /// @notice Extends the legal veto period by the guardians.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    pure def protocolUpgradeHandlerExtendLegalVeto(evm: EvmState, _id: AbiElem): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        
        val e = require(evm.msgSender() == self.guardians, "Only guardians is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val e1 = require(not(self.upgradeStatus.get(_id).guardiansExtendedLegalVeto), "Legal veto period is already extended")
            if (e1 != "") {
                err(evm, e1)
            } else {
                val upgState = upgradeState(self, evm.blockTimestamp, _id)
                val e2 = require(upgState == UpgradeStateLegalVetoPeriod, "Upgrade with this id is not in the legal veto period")
                if (e2 != "") {
                    err(evm, e2)
                } else {
                    pure val self2 = {
                        ...self,
                        upgradeStatus: self.upgradeStatus.setBy(_id, old => {
                            ...old,
                            guardiansExtendedLegalVeto: true,
                        })
                    }

                    ok({ ...evm, protocolUpgradeHandler: self2 })
                }
            }
        }
    }

    /// @notice Approves an upgrade proposal by the Security Council.
    /// @dev Transitions the state of an upgrade proposal to 'VetoPeriod' after approval by the Security Council.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    pure def protocolUpgradeHandlerApproveUpgradeSecurityCouncil(evm: EvmState, _id: AbiElem): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e1 = require(evm.msgSender() == self.securityCouncil, "Only security council is allowed to call this function")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val upgState = upgradeState(self, evm.blockTimestamp, _id)
            val e2 = require(upgState == UpgradeStateWaiting, "Upgrade with this id is not waiting for the approval from Security Council")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(_id, old => {
                        ...old,
                        securityCouncilApprovalTimestamp: evm.blockTimestamp,
                    })
                }

                ok({ ...evm, protocolUpgradeHandler: self2 })
            }
        }
    }

    /// @notice Approves an upgrade proposal by the guardians.
    /// @dev Marks the upgrade proposal identified by `_id` as approved by guardians.
    /// @param _id The unique identifier of the upgrade proposal to approve.
    pure def protocolUpgradeHandlerApproveUpgradeGuardians(evm: EvmState, _id: AbiElem): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val e1 = require(evm.msgSender() == self.guardians, "Only guardians is allowed to call this function")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val upgState = upgradeState(self, evm.blockTimestamp, _id)
            val e2 = require(upgState == UpgradeStateWaiting, "Upgrade with this id is not waiting for the approval from Guardians")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(_id, old => {
                        ...old,
                        securityCouncilApprovalTimestamp: evm.blockTimestamp,
                    })
                }

                ok({ ...evm, protocolUpgradeHandler: self2 })
            }
        }
    }

    /// @notice Executes an upgrade proposal that has reached the 'Ready' state.
    /// @param _proposal The upgrade proposal to be executed, containing the target calls and optionally an executor.
    // TODO: The smart contract has this function as payable. Is it important in this context?
    pure def protocolUpgradeHandlerExecute(evm: EvmState, _proposal: UpgradeProposal): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler
        val id = keccak256_UpgradeProposal(_proposal)
        val upgState: UpgradeState = upgradeState(self, evm.blockTimestamp, id)
        val e1 = require(upgState == UpgradeStateReady, "Upgrade is not yet ready")
        if (e1 != "") {
            err(evm, e1)
        } else {
            val e2 = require(_proposal.executor == "0" or _proposal.executor == evm.msgSender(), "msg.sender is not authorized to perform the upgrade")
            if (e2 != "") {
                err(evm, e2)
            } else {
                pure val self2 = {
                    ...self,
                    upgradeStatus: self.upgradeStatus.setBy(id, old => {
                        ...old,
                        executed: true,
                    }),
                    lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                    protocolFrozenUntil: 0
                }

                ok({ ...evm, protocolUpgradeHandler: self2, zkFrozen: false })
            }
        }
    }

    /// @notice Executes an emergency upgrade proposal initiated by the emergency upgrade board.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    pure def protocolUpgradeHandlerExecuteEmergencyUpgrade(evm: EvmState, _proposal: UpgradeProposal): Result[EvmState] = {
        val self = evm.protocolUpgradeHandler

        val e = require(evm.msgSender() == self.emergencyUpgradeBoard, "Only Emergency Upgrade Board is allowed to call this function")
        if (e != "") {
            err(evm, e)
        } else {
            val id = keccak256_UpgradeProposal(_proposal)
            val upgState: UpgradeState = upgradeState(self, evm.blockTimestamp, id)
            val e1 = require(upgState == UpgradeStateNone, "Upgrade already exists")
            if (e1 != "") {
                err(evm, e1)
            } else {
                val e2 = require(_proposal.executor == evm.msgSender(), "msg.sender is not authorized to perform the upgrade")
                if (e2 != "") {
                    err(evm, e2)
                } else {
                    pure val self2 = {
                        ...self,
                        upgradeStatus: self.upgradeStatus.setBy(id, old => {
                            ...old,
                            executed: true,
                        }),
                        lastFreezeStatusInUpgradeCycle: FreezeStatusNone,
                        protocolFrozenUntil: 0
                    }

                    ok({ ...evm, protocolUpgradeHandler: self2, zkFrozen: false })
                }
            }
        }
    }
}