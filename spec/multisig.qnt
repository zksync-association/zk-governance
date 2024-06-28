module multisig {
    import hashing.* from "./hashing"
    import state.* from "./state"
    import types.* from "./types"
    
    /// -------------------------------------------------------------------------------------------
    /// EIP1271 constants
    /// -------------------------------------------------------------------------------------------

    // EIP1271 magic value meaning that the signature is correct.
    pure val EIP1271_MAGICVALUE = "0x1626ba7e"


    // Multisig contract initialization
    pure def newMultisig(_members: Set[Address], _eip1271Threshold: Uint256): Result[MultisigState] = {
        pure val e = require(_eip1271Threshold > 0, "EIP-1271 threshold is too small").
                    andRequire(_eip1271Threshold <= _members.size(), "EIP-1271 threshold is too big")
        if (e != "") {
            err({ members: Set(), EIP1271_THRESHOLD: 0 }, e)
        } else {
            pure val v = { members: _members, EIP1271_THRESHOLD: _eip1271Threshold }
            ok(v)
        }
    }

    // The function to check if the provided signatures meet the threshold requirement.
    // Signatures must be from unique members and are expected in the same order as the members list (sorted order).
    // @param _digest The hash of the data being signed.
    // @param _signers An array of signers associated with the signatures.
    // @param _signatures An array of signatures to be validated.
    // @param _threshold The minimum number of valid signatures required to pass the check.
    pure def checkSignatures(self: MultisigState, _digest: AbiEncoded, _signers: Set[Address], _signatures: Set[Bytes], _threshold: Uint256): Error = {
        // Ensure the total number of signatures meets or exceeds the threshold.
        val sigSize = _signatures.size()
        val signersSize = _signers.size()
        require(sigSize >= _threshold, "Insufficient valid signatures")
            .andRequire(_signers.size() == sigSize, "Inconsistent signers/signatures length")
            .andRequire(_signers == _signatures, "Signature verification failed")
    }

    pure def isValidSignature(self: MultisigState, _digest: AbiEncoded, _signature: List[Bytes]): Bytes4 = {
        val _signatureSize = length(_signature)
        // lst.indices().map(i => lst[i])
        val signers = _signature.indices().filter(i => i < _signatureSize / 2).map(i => _signature[i])
        val signatures = _signature.indices().filter(i => i >= _signatureSize / 2).map(i => _signature[i])
        pure val err = self.checkSignatures(_digest, signers, signatures, self.EIP1271_THRESHOLD)
        if (err != "") err
        else EIP1271_MAGICVALUE
    }
}