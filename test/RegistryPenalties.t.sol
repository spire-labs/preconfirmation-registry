// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/PreconfirmationRegistry.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MockPenaltyConditions {
    function getPenalty(bytes calldata /* data */, address /* proposer */) public pure returns (PreconfirmationRegistry.Penalty memory) {
        return PreconfirmationRegistry.Penalty(1 ether, 0.5 ether, 100);
    }
}

contract MockHighPenaltyConditions {
    function getPenalty(bytes calldata /* data */, address /* proposer */) public pure returns (PreconfirmationRegistry.Penalty memory) {
        return PreconfirmationRegistry.Penalty(150 ether, 150 ether, 1000);
    }
}

contract MockPenaltyConditionsWithData {
    function getPenalty(bytes calldata data, address /* proposer */) public pure returns (PreconfirmationRegistry.Penalty memory) {
        uint256 amount = abi.decode(data, (uint256));
        return PreconfirmationRegistry.Penalty(amount, 0 ether, 0);
    }
}

contract MockPenaltyConditionsWithDataAndSignature {
    using ECDSA for bytes32;

    function getPenalty(bytes calldata data, address proposer) public pure returns (PreconfirmationRegistry.Penalty memory) {
        // decode data into amount and signature
        (uint256 amount, bytes memory signature) = abi.decode(data, (uint256, bytes));
        // verify signature
        bytes32 messageHash = keccak256(abi.encode(amount));
        address signer = messageHash.recover(signature);
        require(signer == proposer, "Invalid signature");
        return PreconfirmationRegistry.Penalty(amount, 0 ether, 0);
    }
}

contract PreconfirmationRegistryTest is Test {
    PreconfirmationRegistry registry;
    address proposer;
    uint256 proposerPrivateKey;
    address registrant1;
    address registrant2;

    function setUp() public {
        registry = new PreconfirmationRegistry(100 ether, 32, 32);
        (proposer, proposerPrivateKey) = makeAddrAndKey("proposer");
        registrant1 = makeAddr("registrant1");
        registrant2 = makeAddr("registrant2");

        // Setup registrants and delegation
        vm.deal(registrant1, 150 ether);
        vm.deal(registrant2, 150 ether);
        vm.prank(registrant1);
        registry.register{value: 150 ether}();
        vm.prank(registrant2);
        registry.register{value: 150 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        vm.prank(registrant1);
        registry.delegate(proposers);
        vm.prank(registrant2);
        registry.delegate(proposers);

        vm.roll(block.number + 32);

        address[] memory proposersToUpdate = new address[](1);
        proposersToUpdate[0] = proposer;
        registry.updateStatus(proposersToUpdate);
    }

    function testIsRegisteredProposer() public view {
        assertTrue(registry.isRegisteredProposer(proposer));
        assertFalse(registry.isRegisteredProposer(address(0)));
    }

    function testVerifySignature() public view {
        bytes memory message = "Hello, world!";
        bytes32 messageHash = keccak256(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(registry.verifySignature(vm.addr(1), message, signature));
        assertFalse(registry.verifySignature(vm.addr(2), message, signature));
    }

    function testExecuteMockPenaltyConditions() public {
        bytes memory penaltyConditions = type(MockPenaltyConditions).creationCode;
        PreconfirmationRegistry.Penalty memory penalty = registry.executePenaltyConditions(penaltyConditions, "", proposer);

        assertEq(penalty.weiSlashed, 1 ether);
        assertEq(penalty.weiFrozen, 0.5 ether);
        assertEq(penalty.blocksFrozen, 100);
    }

    function testExecuteMockPenaltyConditionsWithData() public {
        bytes memory penaltyConditions = type(MockPenaltyConditionsWithData).creationCode;
        bytes memory data = abi.encode(100 ether);
        PreconfirmationRegistry.Penalty memory penalty = registry.executePenaltyConditions(penaltyConditions, data, proposer);

        assertEq(penalty.weiSlashed, 100 ether);
        assertEq(penalty.weiFrozen, 0 ether);
        assertEq(penalty.blocksFrozen, 0);
    }

    function testExecuteMockPenaltyConditionsWithDataAndSignature() public {
        bytes memory penaltyConditions = type(MockPenaltyConditionsWithDataAndSignature).creationCode;

        bytes32 messageHash = keccak256(abi.encode(100 ether));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proposerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory data = abi.encode(100 ether, signature);

        PreconfirmationRegistry.Penalty memory penalty = registry.executePenaltyConditions(penaltyConditions, data, proposer);

        assertEq(penalty.weiSlashed, 100 ether);
        assertEq(penalty.weiFrozen, 0 ether);
        assertEq(penalty.blocksFrozen, 0);
    }

    function testIsPenaltyEmpty() public view {
        PreconfirmationRegistry.Penalty memory emptyPenalty = PreconfirmationRegistry.Penalty(0, 0, 0);
        PreconfirmationRegistry.Penalty memory nonEmptyPenalty = PreconfirmationRegistry.Penalty(1, 1, 1);

        assertTrue(registry.isPenaltyEmpty(emptyPenalty));
        assertFalse(registry.isPenaltyEmpty(nonEmptyPenalty));
    }

    function testApplyPenaltyToRegistrants() public {
        PreconfirmationRegistry.Penalty memory penalty = PreconfirmationRegistry.Penalty(2 ether, 1 ether, 100);

        uint256 initialProposerCollateral = registry.getProposerInfo(proposer).effectiveCollateral;
        uint256 initialRegistrant1Balance = registry.getRegistrantInfo(registrant1).balance;
        uint256 initialRegistrant2Balance = registry.getRegistrantInfo(registrant2).balance;

        registry.applyPenaltyToRegistrants(proposer, penalty);

        PreconfirmationRegistry.Proposer memory updatedProposer = registry.getProposerInfo(proposer);
        PreconfirmationRegistry.Registrant memory updatedRegistrant1 = registry.getRegistrantInfo(registrant1);
        PreconfirmationRegistry.Registrant memory updatedRegistrant2 = registry.getRegistrantInfo(registrant2);

        assertEq(updatedProposer.effectiveCollateral, initialProposerCollateral - 3 ether);
        assertEq(updatedRegistrant1.balance, initialRegistrant1Balance - 1 ether);
        assertEq(updatedRegistrant2.balance, initialRegistrant2Balance - 1 ether);
        assertEq(updatedRegistrant1.frozenBalance, 0.5 ether);
        assertEq(updatedRegistrant2.frozenBalance, 0.5 ether);
    }

    function testApplyHighPenaltyToRegistrants() public {
        PreconfirmationRegistry.Penalty memory penalty = PreconfirmationRegistry.Penalty(150 ether, 150 ether, 1000);

        uint256 initialProposerCollateral = registry.getProposerInfo(proposer).effectiveCollateral;
        uint256 initialRegistrant1Balance = registry.getRegistrantInfo(registrant1).balance;
        uint256 initialRegistrant2Balance = registry.getRegistrantInfo(registrant2).balance;

        registry.applyPenaltyToRegistrants(proposer, penalty);

        PreconfirmationRegistry.Proposer memory updatedProposer = registry.getProposerInfo(proposer);
        PreconfirmationRegistry.Registrant memory updatedRegistrant1 = registry.getRegistrantInfo(registrant1);
        PreconfirmationRegistry.Registrant memory updatedRegistrant2 = registry.getRegistrantInfo(registrant2);

        assertEq(updatedProposer.effectiveCollateral, initialProposerCollateral - 300 ether, "1");
        assertEq(updatedRegistrant1.balance, initialRegistrant1Balance - 75 ether, "2");
        assertEq(updatedRegistrant2.balance, initialRegistrant2Balance - 75 ether, "3");
        // should be 0 because slashing is applied first
        assertEq(updatedRegistrant1.frozenBalance, 75 ether, "4");
        assertEq(updatedRegistrant2.frozenBalance, 75 ether, "5");
    }
}