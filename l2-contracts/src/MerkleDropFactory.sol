// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.24;

import "src/interfaces/IERC20.sol";
import "src/MerkleLib.sol";

/// @title A factory pattern for merkledrops, that is, airdrops using merkleproofs to compute eligibility
/// @author metapriest, adrian.wachel, marek.babiarz, radoslaw.gorecki
/// @notice This contract is permissionless and public facing. Any fees must be included in the data of the merkle tree.
/// @dev The contract cannot introspect into the contents of the merkle tree, except when provided a merkle proof,
/// @dev therefore the total liabilities of the merkle tree are untrusted and tree balances must be managed separately
contract MerkleDropFactory {
    using MerkleLib for bytes32;

    // the number of airdrops in this contract
    uint public numTrees;

    // this represents a single airdrop
    struct MerkleTree {
        bytes32 merkleRoot;  // merkleroot of tree whose leaves are (address,uint) pairs representing amount owed to user
        bytes32 ipfsHash; // ipfs hash of entire dataset, as backup in case our servers turn off...
        address tokenAddress; // address of token that is being airdropped
        uint tokenBalance; // amount of tokens allocated for this tree
        uint spentTokens; // amount of tokens dispensed from this tree
        mapping (bytes32 => bool) withdrawn;
    }

    // array-like map for all ze merkle trees (airdrops)
    mapping (uint => MerkleTree) public merkleTrees;

    // every time there's a withdraw
    event WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint value);

    // every time a tree is added
    event MerkleTreeAdded(uint indexed treeIndex, address indexed tokenAddress, bytes32 newRoot, bytes32 ipfsHash);

    // every time a tree is topped up
    event TokensDeposited(uint indexed treeIndex, address indexed tokenAddress, uint amount);

    error BadTreeIndex(uint treeIndex);
    error LeafAlreadyClaimed(uint treeIndex, bytes32 leafHash);
    error BadProof(uint treeIndex, bytes32 leaf, bytes32[] proof);
    error TokensNotTransferred(uint treeIndex, bytes32 leaf);

    /// @notice Add a new merkle tree to the contract, creating a new merkle-drop
    /// @dev Anyone may call this function, therefore we must make sure trees cannot affect each other
    /// @param newRoot root hash of merkle tree representing liabilities == (destination, value) pairs
    /// @param ipfsHash the ipfs hash of the entire dataset, used for redundance so that creator can ensure merkleproof are always computable
    /// @param tokenAddress the address of the token contract that is being distributed
    /// @param tokenBalance the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function addMerkleTree(bytes32 newRoot, bytes32 ipfsHash, address tokenAddress, uint tokenBalance) public {
        // prefix operator ++ increments then evaluates
        MerkleTree storage tree = merkleTrees[++numTrees];
        tree.merkleRoot = newRoot;
        tree.ipfsHash = ipfsHash;
        tree.tokenAddress = tokenAddress;

        // you don't get to add a tree without funding it
        depositTokens(numTrees, tokenBalance);
        // I guess we should tell people (interfaces) what happened
        emit MerkleTreeAdded(numTrees, tokenAddress, newRoot, ipfsHash);
    }

    /// @notice Add funds to an existing merkle-drop
    /// @dev Anyone may call this function, the only risk here is that the token contract is malicious, rendering the tree malicious
    /// @param treeIndex index into array-like map of merkleTrees
    /// @param value the amount of tokens user wishes to use to fund the airdrop, note trees can be under/overfunded
    function depositTokens(uint treeIndex, uint value) public {
        if (treeIndex == 0 || treeIndex > numTrees) {
            revert BadTreeIndex(treeIndex);
        }
        // storage since we are editing
        MerkleTree storage merkleTree = merkleTrees[treeIndex];

        IERC20 token = IERC20(merkleTree.tokenAddress);
        uint balanceBefore = token.balanceOf(address(this));

        // yes this could fail, but the balance checker will handle that
        // balance checking also handles fee-on-transfer tokens
        // but not malicious tokens, which could lie about balances
        token.transferFrom(msg.sender, address(this), value);

        uint balanceAfter = token.balanceOf(address(this));

        uint diff = balanceAfter - balanceBefore;

        // bookkeeping to make sure trees don't share tokens
        merkleTree.tokenBalance += diff;

        // transfer tokens, if this is a malicious token, then this whole tree is malicious
        // but it does not effect the other trees
        emit TokensDeposited(treeIndex, merkleTree.tokenAddress, diff);
    }

    /// @notice Claim funds as a recipient in the merkle-drop
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// @dev who provides the proof and pays the gas, msg.sender is not used in this function
    /// @param treeIndex index into array-like map of merkleTrees, which tree should we apply the proof to?
    /// @param destination recipient of tokens
    /// @param value amount of tokens that will be sent to destination
    /// @param proof array of hashes bridging from leaf (hash of destination | value) to merkle root
    function withdraw(uint treeIndex, address destination, uint value, bytes32[] memory proof) public {
        // no withdrawing from uninitialized merkle trees
        if (treeIndex == 0 || treeIndex > numTrees) {
            revert BadTreeIndex(treeIndex);
        }

        // storage because we edit
        MerkleTree storage tree = merkleTrees[treeIndex];

        // compute merkle leaf, this is first element of proof
        bytes32 leaf = keccak256(abi.encode(destination, value));

        // no withdrawing same airdrop twice
        if (tree.withdrawn[leaf]) {
            revert LeafAlreadyClaimed(treeIndex, leaf);
        }

        // this calls to MerkleLib, will return false if recursive hashes do not end in merkle root
        if (tree.merkleRoot.verifyProof(leaf, proof) == false) {
            revert BadProof(treeIndex, leaf, proof);
        }

        // close re-entrance gate, prevent double claims
        tree.withdrawn[leaf] = true;

        IERC20 token = IERC20(tree.tokenAddress);
        uint balanceBefore = token.balanceOf(address(this));

        // transfer the tokens
        // NOTE: if the token contract is malicious this call could re-enter this function
        // which will fail because withdrawn will be set to true
        // Also if this line silently fails then diff will be 0, reverting whole transaction
        // This also covers the case of fee-on-transfer tokens, but again, not malicious tokens
        token.transfer(destination, value);

        uint balanceAfter = token.balanceOf(address(this));
        uint diff = balanceBefore - balanceAfter;
        if (diff == 0) {
            revert TokensNotTransferred(treeIndex, leaf);
        }

        // update struct
        tree.tokenBalance -= diff;
        tree.spentTokens += diff;

        emit WithdrawalOccurred(treeIndex, destination, value);
    }

    function getWithdrawn(uint treeIndex, bytes32 leaf) external view returns (bool) {
        return merkleTrees[treeIndex].withdrawn[leaf];
    }

}