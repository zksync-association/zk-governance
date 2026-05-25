// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/ZkMinterModTriggerV1.sol";
import "src/ZkMinterModTargetExampleV1.sol";
import "src/MerkleDropFactory.sol";
import "src/ZkCappedMinterV2.sol";

contract MockERC20 is Test {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ZkMinterModTriggerV1Test is Test {
    ZkMinterModTriggerV1 public trigger;
    ZkMinterModTargetExampleV1 public target;
    MockERC20 public token;
    address public user = address(0x123);

    ZkCappedMinterV2 public cappedMinter;
    address cappedMinterAdmin = makeAddr("cappedMinterAdmin");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event TransferProcessed(address indexed sender, uint256 amount);

    function setUp() public virtual {
        token = new MockERC20();
        target = new ZkMinterModTargetExampleV1(address(token));

        // Prepare arrays for constructor: two calls
        // 1. Approve on token contract
        // 2. executeTransferAndLogic on target contract
        address[] memory targetAddresses = new address[](2);
        targetAddresses[0] = address(token); // Token contract for approve
        targetAddresses[1] = address(target); // Target contract for executeTransferAndLogic

        bytes[] memory functionSignatures = new bytes[](2);
        functionSignatures[0] = abi.encodeWithSignature("approve(address,uint256)");
        functionSignatures[1] = abi.encodeWithSignature("executeTransferAndLogic(uint256)");

        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encode(address(target), uint256(500 ether)); // Approve target to spend 500 ether
        callDatas[1] = abi.encode(uint256(500 ether)); // Execute transfer of 500 ether

        // Deploy ZkMinterModTriggerV1 with arrays
        trigger = new ZkMinterModTriggerV1(
            cappedMinterAdmin,
            targetAddresses,
            functionSignatures,
            callDatas
        );

        // Setup ZkCappedMinterV2
        uint48 startTime = uint48(block.timestamp);
        uint48 expirationTime = uint48(startTime + 3 days);
        uint256 cap = 500e18;

        cappedMinter = new ZkCappedMinterV2(
            IMintable(address(token)), // Assuming MockERC20 is compatible with IMintable
            cappedMinterAdmin,
            cap,
            startTime,
            expirationTime
        );
        vm.prank(cappedMinterAdmin);
        trigger.setMinter(address(cappedMinter));
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, address(trigger));
    }

    function testMintFullBalance() public {
        uint256 initialBalance = token.balanceOf(address(trigger));
        assertEq(initialBalance, 0);

        // Expect the event from TransferAndLogic
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(trigger), 500 ether);

        // Call mint with the actual amount needed (500 ether)
        vm.prank(user);
        trigger.mint(500 ether);  // Changed from 0 to 500 ether

        // Verify tokens were transferred to the target
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);

        // Verify allowance was set and consumed
        assertEq(token.allowance(address(trigger), address(target)), 0);
    }

    function test_RevertWhen_MintExceedsCap() public {
        // Deploy a new trigger with invalid call data (amount exceeds cap)
        address[] memory targetAddresses = new address[](2);
        targetAddresses[0] = address(token);
        targetAddresses[1] = address(target);

        bytes[] memory functionSignatures = new bytes[](2);
        functionSignatures[0] = abi.encodeWithSignature("approve(address,uint256)");
        functionSignatures[1] = abi.encodeWithSignature("executeTransferAndLogic(uint256)");

        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encode(address(target), uint256(500 ether));
        callDatas[1] = abi.encode(uint256(500 ether));

        ZkMinterModTriggerV1 badTrigger = new ZkMinterModTriggerV1(
            cappedMinterAdmin,
            targetAddresses,
            functionSignatures,
            callDatas
        );

        // Configure minter and roles
        vm.prank(cappedMinterAdmin);
        badTrigger.setMinter(address(cappedMinter));
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, address(badTrigger));

        // Should revert due to function call failure (invalid target)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ZkCappedMinterV2__CapExceeded(address,uint256)", address(badTrigger), 1000 ether));
        badTrigger.mint(1000 ether); // Try to mint 1000 ether (exceeds cap of 500 ether)
    }


    function testCallWithCustomCallData() public {
        // Expect the event with the fixed amount from callData
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(trigger), 500 ether);

        // Call initiateCall
        vm.prank(user);
        trigger.mint(500 ether);

        // Verify token transfer
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);

        // Verify allowance was set and consumed
        assertEq(token.allowance(address(trigger), address(target)), 0);
    }
}

contract MintFromZkCappedMinter is ZkMinterModTriggerV1Test {

    function setUp() public virtual override {
        // Call parent setUp first
        super.setUp();

    }

    function testMintFromCappedMinterAndInitiateCall() public {
        // Verify initial state
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 0);

        // Expect the TransferProcessed event with the fixed amount
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(trigger), 500 ether);

        // Execute the initiateCall flow
        vm.prank(user);
        trigger.mint(500 ether);

        // Verify final state
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);
        assertEq(token.allowance(address(trigger), address(target)), 0);
    }
}

contract MerkleTargetTest is Test {
    ZkMinterModTriggerV1 public caller;
    MerkleDropFactory public target;
    MockERC20 public token;
    address public user = address(0x123);
    ZkCappedMinterV2 public cappedMinter;
    address cappedMinterAdmin = makeAddr("cappedMinterAdmin");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint value);

    function setUp() public virtual {
        // Deploy the token and target contracts
        token = new MockERC20();
        target = new MerkleDropFactory();

        // Setup Merkle tree parameters
        uint256 withdrawAmount = 500 ether;
        address destination = address(0x456); // Where tokens will go
        bytes32 leaf = keccak256(abi.encode(destination, withdrawAmount));
        bytes32 merkleRoot = leaf; // Simplest tree: root = leaf (single entry)
        bytes32 ipfsHash = keccak256("ipfs data");

        // Prepare arrays for constructor: two calls
        // 1. Approve on token contract
        // 2. addMerkleTree on target contract
        address[] memory targetAddresses = new address[](2);
        targetAddresses[0] = address(token); // Token contract for approve
        targetAddresses[1] = address(target); // Target contract for addMerkleTree

        bytes[] memory functionSignatures = new bytes[](2);
        functionSignatures[0] = abi.encodeWithSignature("approve(address,uint256)");
        functionSignatures[1] = abi.encodeWithSignature("addMerkleTree(bytes32,bytes32,address,uint256)");

        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encode(address(target), uint256(500 ether)); // Approve target to spend 500 ether
        callDatas[1] = abi.encode(merkleRoot, ipfsHash, address(token), uint256(500 ether)); // Setup Merkle tree

        // Deploy ZkMinterModTriggerV1 with arrays
        caller = new ZkMinterModTriggerV1(
            cappedMinterAdmin,
            targetAddresses,
            functionSignatures,
            callDatas
        );

        // Setup ZkCappedMinterV2
        uint48 startTime = uint48(block.timestamp);
        uint48 expirationTime = uint48(startTime + 3 days);
        uint256 cap = 500e18;

        cappedMinter = new ZkCappedMinterV2(
            IMintable(address(token)),
            cappedMinterAdmin,
            cap,
            startTime,
            expirationTime
        );

        // Configure minter and roles
        vm.prank(cappedMinterAdmin);
        caller.setMinter(address(cappedMinter));
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, address(caller));
    }

    function testMintFromCappedMinterAndWithdrawFromMerkleDrop() public {
        // Setup Merkle tree parameters
        uint256 withdrawAmount = 500 ether;
        address destination = address(0x456); // Where tokens will go
        bytes32 leaf = keccak256(abi.encode(destination, withdrawAmount));
        bytes32 merkleRoot = leaf; // Simplest tree: root = leaf (single entry)
        bytes32 ipfsHash = keccak256("ipfs data");

        // Verify initial state
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(target)), 0);
        assertEq(token.balanceOf(destination), 0);
        assertEq(token.allowance(address(caller), address(target)), 0);

        // Call initiateCall
        vm.prank(user);
        caller.mint(500 ether);

        // Verify tokens were minted and transferred to target via addMerkleTree
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);
        assertEq(token.balanceOf(destination), 0);
        assertEq(token.allowance(address(caller), address(target)), 0); // Allowance consumed by transferFrom

        {
            // Verify tree setup
            (bytes32 merkleRoot1, bytes32 ipfsHash1, address tokenAddress1, uint256 tokenBalance1, uint256 spentTokens1) = target.merkleTrees(1);
            assertEq(merkleRoot1, merkleRoot);
            assertEq(ipfsHash1, ipfsHash);
            assertEq(tokenAddress1, address(token));
            assertEq(tokenBalance1, 500 ether);
            assertEq(spentTokens1, 0);
        }

        // Expect the WithdrawalOccurred event
        vm.expectEmit(true, true, false, true, address(target));
        emit WithdrawalOccurred(1, destination, withdrawAmount);

        {
            // Perform withdrawal
            bytes32[] memory proof = new bytes32[](0); // Empty proof for single-leaf tree
            vm.prank(destination); // Withdraw as the destination address
            target.withdraw(1, destination, 500 ether, proof);

            // Verify final balances
            assertEq(token.balanceOf(address(caller)), 0);
            assertEq(token.balanceOf(address(target)), 0);
            assertEq(token.balanceOf(destination), 500 ether);
        }
        {
            // Verify tree state after withdrawal
            (bytes32 merkleRoot2, bytes32 ipfsHash2, address tokenAddress2, uint256 tokenBalance2, uint256 spentTokens2) = target.merkleTrees(1);
            assertEq(merkleRoot2, merkleRoot);
            assertEq(ipfsHash2, ipfsHash);
            assertEq(tokenAddress2, address(token));
            assertEq(tokenBalance2, 0);
            assertEq(spentTokens2, 500 ether);
            assertTrue(target.getWithdrawn(1, leaf));
        }
    }

    function test_RevertWhen_ExceedsCap() public {
        // Deploy a new caller with call data exceeding the cap
        uint256 withdrawAmount = 600 ether; // Exceeds cap of 500 ether
        address destination = address(0x456);
        bytes32 leaf = keccak256(abi.encode(destination, withdrawAmount));
        bytes32 merkleRoot = leaf;
        bytes32 ipfsHash = keccak256("ipfs data");

        address[] memory targetAddresses = new address[](2);
        targetAddresses[0] = address(token);
        targetAddresses[1] = address(target);

        bytes[] memory functionSignatures = new bytes[](2);
        functionSignatures[0] = abi.encodeWithSignature("approve(address,uint256)");
        functionSignatures[1] = abi.encodeWithSignature("addMerkleTree(bytes32,bytes32,address,uint256)");

        bytes[] memory callDatas = new bytes[](2);
        callDatas[0] = abi.encode(address(target), uint256(600 ether)); // Approve 600 ether
        callDatas[1] = abi.encode(merkleRoot, ipfsHash, address(token), uint256(600 ether)); // Try to setup tree with 600 ether

        ZkMinterModTriggerV1 badCaller = new ZkMinterModTriggerV1(
            cappedMinterAdmin,
            targetAddresses,
            functionSignatures,
            callDatas
        );

        // Configure minter and roles
        vm.prank(cappedMinterAdmin);
        badCaller.setMinter(address(cappedMinter));
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, address(badCaller));

        // Should revert due to exceeding cap
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ZkCappedMinterV2__CapExceeded(address,uint256)", address(badCaller), 600 ether));
        badCaller.mint(600 ether);
    }
}