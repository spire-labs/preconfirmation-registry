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
        registrant = address(0x1);
        proposer = address(0x2);
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

        PreconfirmationRegistry.Registrant memory info = registry.getRegistrantInfo(registrant);
        assertEq(info.delegatedProposers.length, 1);
        assertEq(info.delegatedProposers[0], proposer);
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
    }

    function testWithdraw() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        registry.initiateExit(1 ether);
        vm.stopPrank();

        vm.roll(block.number + 33);

        uint256 balanceBefore = registrant.balance;
        vm.prank(registrant);
        registry.withdraw();

        assertEq(registrant.balance - balanceBefore, 1 ether);
    }
}