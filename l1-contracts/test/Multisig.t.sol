// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Multisig} from "../../src/Multisig.sol";
import {MultisigMock} from "./mocks/MultisigMock.t.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract TestMultisig is Test {
    bytes32 private constant DIGEST = bytes32(uint256(0x1001));
    bytes32 private constant INCORRECT_DIGEST = bytes32(uint256(0x1002));

    MultisigMock private implementer;
    bytes[] private correctSignatures;
    address[] private memberAddresses;
    uint256[] private memberPrivateKeys;

    function sign(uint256 _privateKey, bytes32 _digest) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, _digest);
        return abi.encodePacked(r, s, v);
    }

    function signMainDigest(uint256 _privateKey) private view returns (bytes memory) {
        return sign(_privateKey, DIGEST);
    }

    function _mockEip712Call(address _signer, bytes32 _digest) private {
        vm.mockCall(
            _signer,
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, _digest),
            abi.encode(IERC1271.isValidSignature.selector)
        );
    }

    constructor() {
        address[] memory members = new address[](3);
        bytes[] memory signatures = new bytes[](3);

        // These private keys are created in such an order that hte corresponding addresses are sorted:
        // - 0x335A87e7068a0f1eB6557F0C2ab9B352D441c310
        // - 0x3A80DA2886FDa545cdc4E5c4fA49861be958c7A2
        // - 0x61E6a954AE6aBdbbdbD0a179219A4669CC375697
        uint256[] memory privateKeys = new uint256[](3);
        privateKeys[0] = uint256(0x580f556735dea86fc45128e541b06b0def7b3e8e1b7afa511ab7c8dba94ce589);
        privateKeys[1] = uint256(0xbe9aa2d7e2423678501a5b2e122bf957c920804e707e915f374f7930cef5b637);
        privateKeys[2] = uint256(0xe4fcf7ab7eb2558b95c2a737eef779decddbb4ff8646b5c7c586d43ecdf02c18);

        memberPrivateKeys = privateKeys;

        for (uint256 i = 0; i < 3; i++) {
            members[i] = vm.addr(privateKeys[i]);
            signatures[i] = signMainDigest(privateKeys[i]);
        }

        memberAddresses = members;
        correctSignatures = signatures;

        implementer = new MultisigMock(members, 2);
    }

    function test_SortedArrayInConstructor() public {
        address[] memory members = new address[](3);

        members[0] = address(0x01);
        members[1] = address(0x02);
        members[2] = address(0x03);

        MultisigMock testImplementer = new MultisigMock(members, 2);
        address[] memory testMembers = testImplementer.getMembers();
        assertEq(members, testMembers);
    }

    function test_RevertWhen_DuplicateInConstructor() public {
        address[] memory members = new address[](3);

        members[0] = address(0x01);
        members[1] = address(0x02);
        members[2] = address(0x02);

        vm.expectRevert("Members not sorted or duplicate found");
        new MultisigMock(members, 2);
    }

    function test_RevertWhen_Eip712ThresholdIsZero() public {
        address[] memory members = new address[](0);

        vm.expectRevert("EIP-1271 threshold is too small");
        new MultisigMock(members, 0);
    }

    function test_RevertWhen_Eip712ThresholdIsTooBig() public {
        address[] memory members = new address[](1);
        members[0] = address(0x01);

        vm.expectRevert("EIP-1271 threshold is too big");
        new MultisigMock(members, 2);
    }

    function test_NonSortedMembersInConstructor() public {
        address[] memory members = new address[](3);

        members[0] = address(0x01);
        members[1] = address(0x03);
        members[2] = address(0x02);

        vm.expectRevert("Members not sorted or duplicate found");
        new MultisigMock(members, 2);
    }

    function test_InvalidNumberOfSignatures() public {
        vm.expectRevert("Insufficient valid signatures");
        implementer.checkSignatures(DIGEST, new address[](1), new bytes[](1), 2);
    }

    function test_CorrectSignatures() public {
        // Firstly, let's check the case when the exact threshold is met
        bytes[] memory smallThresholdSig = new bytes[](1);
        address[] memory smallThresholdAddr = new address[](1);
        smallThresholdSig[0] = correctSignatures[0];
        smallThresholdAddr[0] = memberAddresses[0];
        implementer.checkSignatures(DIGEST, smallThresholdAddr, smallThresholdSig, 1);

        // Secondly, let's check when more than the threshold is met
        bytes[] memory allSignatures = correctSignatures;
        address[] memory allMembers = memberAddresses;
        implementer.checkSignatures(DIGEST, allMembers, allSignatures, 2);

        // Thirdly, let's test that the gaps between signatures are allowed,
        // i.e. we do not need the second signature.
        bytes[] memory testSignatures = new bytes[](2);
        address[] memory testMembers = new address[](2);
        testSignatures[0] = correctSignatures[0];
        testSignatures[1] = correctSignatures[2];
        testMembers[0] = memberAddresses[0];
        testMembers[1] = memberAddresses[2];

        implementer.checkSignatures(DIGEST, testMembers, testSignatures, 2);
    }

    function test_DuplicatedSignatures() public {
        bytes[] memory badSignatures = correctSignatures;
        badSignatures[0] = correctSignatures[1];
        vm.expectRevert();
        implementer.checkSignatures(DIGEST, memberAddresses, badSignatures, 1);
    }

    function test_IncorrectSignature() public {
        // One can not use a bad signature
        bytes[] memory badSignatures = correctSignatures;
        badSignatures[0] = signMainDigest(0x1234);
        vm.expectRevert();
        implementer.checkSignatures(DIGEST, memberAddresses, badSignatures, 1);
    }

    function test_RevertWhen_membersLengthMismatchSignaturesLength() public {
        address[] memory members = new address[](2);
        bytes[] memory signatures = new bytes[](1);
        vm.expectRevert("Inconsistent signers/signatures length");
        implementer.checkSignatures(DIGEST, members, signatures, 1);
    }

    function test_RevertWhen_IncorrectDigest() public {
        // The correct members can not sign bad digest
        bytes[] memory badSignatures = new bytes[](3);
        for (uint256 i = 0; i < 3; i++) {
            badSignatures[i] = sign(memberPrivateKeys[i], INCORRECT_DIGEST);
        }
        vm.expectRevert();
        implementer.checkSignatures(DIGEST, memberAddresses, badSignatures, 1);
    }

    function test_Eip712Signature() public {
        address signer = memberAddresses[0];
        _mockEip712Call(signer, DIGEST);
        address[] memory members = new address[](1);
        bytes[] memory signatures = new bytes[](1);
        members[0] = signer;

        implementer.checkSignatures(DIGEST, members, signatures, 1);
    }

    function test_RevertWhen_isValidSignatureDecodingFailed() public {
        vm.expectRevert();
        implementer.isValidSignature(DIGEST, abi.encode("123"));
    }

    function test_isValidSignatureEIP712WithEnoughSignatures() public {
        _mockEip712Call(memberAddresses[0], DIGEST);
        _mockEip712Call(memberAddresses[1], DIGEST);
        address[] memory members = new address[](2);
        members[0] = memberAddresses[0];
        members[1] = memberAddresses[1];
        bytes[] memory signatures = new bytes[](2);

        implementer.isValidSignature(DIGEST, abi.encode(members, signatures));
    }

    function test_RevertWhen_isValidSignatureWithNotEnoughSignatures() public {
        _mockEip712Call(memberAddresses[0], DIGEST);
        address[] memory members = new address[](1);
        members[0] = memberAddresses[0];
        bytes[] memory signatures = new bytes[](1);

        vm.expectRevert("Insufficient valid signatures");
        implementer.isValidSignature(DIGEST, abi.encode(members, signatures));
    }
}
