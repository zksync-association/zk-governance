// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/interfaces/IZkCappedMinter.sol";

contract ZkMinterModTriggerV1 {
    IZkCappedMinter public minter;    // The ZkCappedMinter for which this project
    address public admin;             // The address that can change everything
    address[] public targets;            // The target contract to call
    bytes[] public functionSignatures;   // The function signature to execute (e.g., function selector)
    bytes[] public callDatas;            // The call data for the function

    modifier adminOnly {
        require(msg.sender == admin, "Only admin can call this");
        _;
    }


    constructor(
        address _admin,
        address[] memory _targetAddresses,
        bytes[] memory _functionSignatures,
        bytes[] memory _callDatas
    ) {
        require(
            _targetAddresses.length == _functionSignatures.length &&
            _functionSignatures.length == _callDatas.length,
            "Array lengths must match"
        );

        admin = _admin;
        targets = _targetAddresses;
        functionSignatures = _functionSignatures;
        callDatas = _callDatas;
    }


    function setMinter(address _minter) external adminOnly {
        minter = IZkCappedMinter(_minter);
    }

    function setTargets(address[] calldata _targets) external adminOnly {
        targets = _targets;
    }

    function setAdmin(address _admin) external adminOnly {
        admin = _admin;
    }


    function setFunctionSignatures(bytes[] calldata _functionSignatures) external adminOnly {
        // Manually copy to avoid nested calldata issues
        bytes[] memory newSignatures = new bytes[](_functionSignatures.length);
        for (uint256 i = 0; i < _functionSignatures.length; i++) {
            newSignatures[i] = _functionSignatures[i];
        }
        functionSignatures = newSignatures;
    }

    function setCallDatas(bytes[] calldata _callDatas) external adminOnly {
        // Manually copy to avoid nested calldata issues
        bytes[] memory newCallDatas = new bytes[](_callDatas.length);
        for (uint256 i = 0; i < _callDatas.length; i++) {
            newCallDatas[i] = _callDatas[i];
        }
        callDatas = newCallDatas;
    }

    // Function to set all call parameters at once
    function setCallParameters(
        address[] calldata _targets,
        bytes[] calldata _functionSignatures,
        bytes[] calldata _callDatas
    ) external adminOnly {
        require(
            _targets.length == _functionSignatures.length &&
            _functionSignatures.length == _callDatas.length,
            "Array lengths must match"
        );
        targets = _targets;

        // Manually copy to avoid nested calldata issues
        bytes[] memory newSignatures = new bytes[](_functionSignatures.length);
        bytes[] memory newCallDatas = new bytes[](_callDatas.length);
        for (uint256 i = 0; i < _functionSignatures.length; i++) {
            newSignatures[i] = _functionSignatures[i];
            newCallDatas[i] = _callDatas[i];
        }
        functionSignatures = newSignatures;
        callDatas = newCallDatas;
    }

    // Function to approve and call with arbitrary calldata
    function mint(uint256 _amount) external {
        minter.mint(address(this), _amount);

        require(targets.length == functionSignatures.length &&
                functionSignatures.length == callDatas.length,
                "Array lengths must match");

        // Iterate through all targets and execute calls
        for (uint256 i = 0; i < targets.length; i++) {
            // Combine function signature with provided callData
            bytes memory fullCallData = abi.encodePacked(functionSignatures[i], callDatas[i]);
            (bool success, ) = targets[i].call(fullCallData);
            require(success, "Function call failed");
        }
    }
}