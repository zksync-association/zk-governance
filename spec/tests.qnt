module tests {
    import guardians.* from "./guardians"
    import hashing.* from "./hashing"
    import multisig.* from "./multisig"
    import protocolUpgradeHandler.* from "./protocolUpgradeHandler"
    import securityCouncil.* from "./securityCouncil"
    import state.* from "./state"
    import types.* from "./types"


    run multisig_Test = {
        val m = newMultisig(Set("a", "b", "c", "d"), 2)
        if (isOk(m)) {
            val magic = m.v.isValidSignature([], List("a", "b", "c", "d", "a", "b", "c", "d"))
            assert(magic == EIP1271_MAGICVALUE)
        } else {
            assert(false)
        }
    }


    run multisig_2_Test = {
        val m = newMultisig(Set("a","b","c","d"), 2)
        if (isOk(m)) {
            assert(EIP1271_MAGICVALUE == m.v.isValidSignature([], List("a","b","c", "d", "a","b","c", "d")))
        } else {
            assert(false)
        }
    }

    run newSecurityCouncil_ok_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
        val sc = newSecurityCouncil(members)
        if (isOk(sc)) {
            assert(sc.v.multisig.members == members)
        } else {
            assert(false)
        }
    }

    run newSecurityCouncil_small_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11")
        val sc = newSecurityCouncil(members)
        assert(isErr(sc))
    }

    run newSecurityCouncil_large_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12", "a13")
        val sc = newSecurityCouncil(members)
        assert(isErr(sc))
    }

    run securityCouncilSoftFreeze_Test = {
        val members = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "a10", "a11", "a12")
        val guardiansMembers = Set("g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8")
        val zkFoundationMultisig = newMultisig(members, 3)
        val sc = newSecurityCouncil(members)
        val guardians = newGuardians(guardiansMembers)
        if (isErr(sc) or isErr(guardians) or isErr(zkFoundationMultisig)) {
            assert(false)
        } else {
            
            val evm = {
                blockTimestamp: 50,
                securityCouncil: sc.v,
                guardians: guardians.v,
                zkFoundation: zkFoundationMultisig.v,
                protocolUpgradeHandler: {
                    securityCouncil: "sc1",
                    guardians: "g",
                    emergencyUpgradeBoard: "b",
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
            }
            val nine = Set("a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9")
            val evm2 = evm.externalCall("sender", "SECURITY_COUNCIL_ADDR", "softFreeze")
            val res = securityCouncilSoftFreeze(evm, 100, nine, nine)
            if (isErr(res)) {
                assert(false)
            } else {
                and {
                    assert(res.v.protocolUpgradeHandler.lastFreezeStatusInUpgradeCycle == FreezeStatusSoft),
                    assert(res.v.protocolUpgradeHandler.protocolFrozenUntil == 50 + 12 * 3600),
                    assert(res.v.zkFrozen),
                }
            }
            
        }
    }
}    