// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.t.sol";
import {EIP712Util} from "./utils/EIP712Util.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {SecurityCouncil} from "../../src/SecurityCouncil.sol";
import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract TestSecurityCouncil is Test, EIP712Util {
    IProtocolUpgradeHandler protocolUpgradeHandler = IProtocolUpgradeHandler(address(new EmptyContract()));
    SecurityCouncil securityCouncil;
    Vm.Wallet[] wallets;
    address[] internal members;
    bytes32 internal securityCouncilDomainHash;

    /// @dev EIP-712 TypeHash for protocol upgrades approval by the Security Council.
    bytes32 internal constant APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("ApproveUpgradeSecurityCouncil(bytes32 id)");

    /// @dev EIP-712 TypeHash for soft emergency freeze approval by the Security Council.
    bytes32 internal constant SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("SoftFreeze(uint256 nonce,uint256 validUntil)");

    /// @dev EIP-712 TypeHash for hard emergency freeze approval by the Security Council.
    bytes32 internal constant HARD_FREEZE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("HardFreeze(uint256 nonce,uint256 validUntil)");

    /// @dev EIP-712 TypeHash for setting threshold for soft freeze approval by the Security Council.
    bytes32 internal constant SET_SOFT_FREEZE_THRESHOLD_TYPEHASH =
        keccak256("SetSoftFreezeThreshold(uint256 threshold,uint256 nonce,uint256 validUntil)");

    /// @dev EIP-712 TypeHash for unfreezing the protocol upgrade by the Security Council.
    bytes32 internal constant UNFREEZE_TYPEHASH = keccak256("Unfreeze(uint256 nonce,uint256 validUntil)");

    constructor() {
        Vm.Wallet[] memory wallets_ = new Vm.Wallet[](12);
        for (uint256 i = 0; i < 12; i++) {
            wallets_[i] = vm.createWallet(string(abi.encodePacked("Account: ", i)));
        }
        wallets_ = Utils.sortWalletsByAddress(wallets_);

        for (uint256 i = 0; i < 12; i++) {
            wallets.push(wallets_[i]);
            members.push(wallets_[i].addr);
        }

        securityCouncil = new SecurityCouncil(protocolUpgradeHandler, members);
        securityCouncilDomainHash = _buildDomainHash(address(securityCouncil), "SecurityCouncil", "1");
    }

    function test_RevertWhen_NotTwelveMembers(uint256 _numberOfMembers) public {
        _numberOfMembers = bound(_numberOfMembers, 0, 100);
        vm.assume(_numberOfMembers != 12);
        address[] memory members = new address[](_numberOfMembers);

        for (uint256 i = 0; i < _numberOfMembers; i++) {
            members[i] = address(uint160(i + 1));
        }

        if (_numberOfMembers >= 9) {
            vm.expectRevert("SecurityCouncil requires exactly 12 members");
        } else {
            vm.expectRevert("EIP-1271 threshold is too big");
        }

        new SecurityCouncil(protocolUpgradeHandler, members);
    }

    function test_RevertWhen_softFreezeSignatureExpired(uint256 _timestamp) public {
        _timestamp = bound(_timestamp, 0, block.timestamp);
        vm.expectRevert("Signature expired");
        securityCouncil.softFreeze(_timestamp, members, new bytes[](0));
    }

    function test_RevertWhen_hardFreezeSignatureExpired(uint256 _timestamp) public {
        _timestamp = bound(_timestamp, 0, block.timestamp);
        vm.expectRevert("Signature expired");
        securityCouncil.hardFreeze(_timestamp, members, new bytes[](0));
    }

    function test_RevertWhen_unfreezeSignatureExpired(uint256 _timestamp) public {
        _timestamp = bound(_timestamp, 0, block.timestamp);
        vm.expectRevert("Signature expired");
        securityCouncil.unfreeze(_timestamp, members, new bytes[](0));
    }

    function test_RevertWhen_setSoftFreezeThresholdSignatureExpired(uint256 _timestamp) public {
        _timestamp = bound(_timestamp, 0, block.timestamp);
        vm.expectRevert("Signature expired");
        securityCouncil.setSoftFreezeThreshold(1, _timestamp, members, new bytes[](0));
    }

    function test_RevertWhen_tryToSetTooBigThresholdForSoftFreeze(uint256 _newThreshold, uint256 _validUntil) public {
        _newThreshold = bound(_newThreshold, 10, 12);
        vm.expectRevert("Threshold is too big");
        securityCouncil.setSoftFreezeThreshold(_newThreshold, _validUntil, members, new bytes[](0));
    }

    function test_RevertWhen_tryToSetTooBigThresholdForSoftFreeze() public {
        vm.expectRevert("Threshold is too small");
        securityCouncil.setSoftFreezeThreshold(0, 0, members, new bytes[](0));
    }

    function test_approveUpgradeSecurityCouncil(bytes32 _id, uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask)
        public
    {
        _numberOfSignatures = bound(_numberOfSignatures, 6, 12);

        bytes32 message = keccak256(abi.encode(APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH, _id));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        securityCouncil.approveUpgradeSecurityCouncil(_id, signers, signatures);
    }

    // TODO: better test threshold
    function test_softFreeze(uint256 _validUntil, uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask) public {
        _numberOfSignatures = bound(_numberOfSignatures, 6, 12);
        _validUntil = bound(_validUntil, block.timestamp + 1, type(uint256).max);
        uint256 nonceBefore = securityCouncil.softFreezeNonce();

        bytes32 message = keccak256(abi.encode(SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH, nonceBefore, _validUntil));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        securityCouncil.softFreeze(_validUntil, signers, signatures);
        assertEq(nonceBefore + 1, securityCouncil.softFreezeNonce());
    }

    function test_hardFreeze(uint256 _validUntil, uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask) public {
        _numberOfSignatures = bound(_numberOfSignatures, 9, 12);
        _validUntil = bound(_validUntil, block.timestamp + 1, type(uint256).max);
        uint256 nonceBefore = securityCouncil.hardFreezeNonce();

        bytes32 message = keccak256(abi.encode(HARD_FREEZE_SECURITY_COUNCIL_TYPEHASH, nonceBefore, _validUntil));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        securityCouncil.hardFreeze(_validUntil, signers, signatures);
        assertEq(nonceBefore + 1, securityCouncil.hardFreezeNonce());
    }

    function test_unfreeze(uint256 _validUntil, uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask) public {
        _numberOfSignatures = bound(_numberOfSignatures, 9, 12);
        _validUntil = bound(_validUntil, block.timestamp + 1, type(uint256).max);
        uint256 nonceBefore = securityCouncil.unfreezeNonce();

        bytes32 message = keccak256(abi.encode(UNFREEZE_TYPEHASH, nonceBefore, _validUntil));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        securityCouncil.unfreeze(_validUntil, signers, signatures);
        assertEq(nonceBefore + 1, securityCouncil.unfreezeNonce());
    }

    function test_setSoftFreezeThreshold(
        uint256 _newThreshold,
        uint256 _validUntil,
        uint256 _numberOfSignatures,
        uint256 _isEOAOrEIP712Mask
    ) public {
        _newThreshold = bound(_newThreshold, 1, 9);
        _numberOfSignatures = bound(_numberOfSignatures, 9, 12);
        _validUntil = bound(_validUntil, block.timestamp + 1, type(uint256).max);
        uint256 nonceBefore = securityCouncil.softFreezeThresholdSettingNonce();

        bytes32 message =
            keccak256(abi.encode(SET_SOFT_FREEZE_THRESHOLD_TYPEHASH, _newThreshold, nonceBefore, _validUntil));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        securityCouncil.setSoftFreezeThreshold(_newThreshold, _validUntil, signers, signatures);
        assertEq(nonceBefore + 1, securityCouncil.softFreezeThresholdSettingNonce());
    }

    function _prepareSignersAndSignatures(uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask, bytes32 _message)
        internal
        returns (address[] memory signers, bytes[] memory signatures)
    {
        signers = new address[](_numberOfSignatures);
        signatures = new bytes[](_numberOfSignatures);
        bytes32 digest = _buildDigest(securityCouncilDomainHash, _message);
        for (uint256 i = 0; i < _numberOfSignatures; i++) {
            signers[i] = members[i];
            if ((_isEOAOrEIP712Mask & (1 << i)) != 0) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallets[i].privateKey, digest);
                signatures[i] = abi.encodePacked(r, s, v);
            } else {
                _mockEip712Call(signers[i], digest);
            }
        }
    }

    function _mockEip712Call(address _signer, bytes32 _digest) private {
        vm.mockCall(
            _signer,
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, _digest),
            abi.encode(IERC1271.isValidSignature.selector)
        );
    }
}
