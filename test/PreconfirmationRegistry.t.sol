// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PreconfirmationRegistry.sol";

contract PreconfirmationRegistryTest is Test {
    PreconfirmationRegistry public registry;
    address public registrant;
    address public proposer;
    uint256 constant MINIMUM_COLLATERAL = 1 ether;

    function setUp() public {
        registry = new PreconfirmationRegistry(MINIMUM_COLLATERAL);
        registrant = vm.addr(1);
        proposer = vm.addr(2);
        vm.deal(registrant, 10 ether);
    }

    function testRegister() public {
        vm.prank(registrant);
        registry.register{value: 2 ether}();

        PreconfirmationRegistry.Registrant memory info = registry.getRegistrantInfo(registrant);
        assertEq(info.balance, 2 ether);
        assertEq(info.frozenBalance, 0);
        assertEq(info.enteredAt, block.number + 32);
        assertEq(info.exitInitiatedAt, 0);
        assertEq(info.delegatedProposers.length, 0);
    }

    function testDelegate() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory registrantInfo = registry.getRegistrantInfo(registrant);
        PreconfirmationRegistry.Proposer memory proposerInfo = registry.getProposerInfo(proposer);
        assertEq(registrantInfo.delegatedProposers.length, 1);
        assertEq(registrantInfo.delegatedProposers[0], proposer);
        assertEq(proposerInfo.delegatedBy.length, 1);
        assertEq(proposerInfo.delegatedBy[0], registrant);

        // we do not test that the effective collateral is calculated correctly here, that is done in the testUpdateStatus test
    }

    function testUpdateStatus() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        vm.roll(block.number + 32);

        registry.updateStatus(proposers);

        PreconfirmationRegistry.Status status = registry.getProposerStatus(proposer);
        assertEq(uint(status), uint(PreconfirmationRegistry.Status.PRECONFER));
    }

    function testApplyPenalty() public {
        // This test is a placeholder and needs to be implemented
        // once the penalty conditions and signature verification are finalized
    }

    function testInitiateExit() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        registry.initiateExit(1 ether);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory info = registry.getRegistrantInfo(registrant);
        assertEq(info.balance, 2 ether);
        assertEq(info.exitInitiatedAt, block.number);
        assertEq(info.amountExiting, 1 ether);
    }

    function testWithdraw() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        registry.initiateExit(1 ether);
        vm.stopPrank();

        vm.roll(block.number + 33);

        uint256 balanceBefore = registrant.balance;
        vm.prank(registrant);
        registry.withdraw(registrant);

        assertEq(registrant.balance - balanceBefore, 1 ether);
    }
}