// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PreconfirmationRegistry.sol";

contract PreconfirmationRegistryTest is Test {
    PreconfirmationRegistry public registry;
    address public registrant;
    address public proposer;
    uint256 constant MINIMUM_COLLATERAL = 1 ether;
    uint256 constant ACTIVATION_DELAY = 32;
    uint256 constant EXIT_COOLDOWN = 32;

    function setUp() public {
        registry = new PreconfirmationRegistry(
            MINIMUM_COLLATERAL,
            ACTIVATION_DELAY,
            EXIT_COOLDOWN
        );
        registrant = vm.addr(1);
        proposer = vm.addr(2);
        vm.deal(registrant, 10 ether);
    }

    function testRegister() public {
        vm.prank(registrant);
        registry.register{value: 2 ether}();

        PreconfirmationRegistry.Registrant memory info = registry
            .getRegistrantInfo(registrant);
        assertEq(info.balance, 2 ether);
        assertEq(info.frozenBalance, 0);
        assertEq(info.enteredAt, block.number + 32);
        assertEq(info.exitInitiatedAt, 0);
        assertEq(info.delegatedProposers.length, 0);
    }

    function testRegisterZeroValue() public {
        vm.prank(registrant);
        vm.expectRevert("Insufficient registration amount");
        registry.register{value: 0}();
    }

    function testDelegate() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory registrantInfo = registry
            .getRegistrantInfo(registrant);
        PreconfirmationRegistry.Proposer memory proposerInfo = registry
            .getProposerInfo(proposer);
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

        PreconfirmationRegistry.Status status = registry.getProposerStatus(
            proposer
        );
        assertEq(uint(status), uint(PreconfirmationRegistry.Status.PRECONFER));
        assertEq(registry.getEffectiveCollateral(proposer), 2 ether);
    }

    function testApplyPenalty() public {
        // This test is a placeholder and needs to be implemented
        // once the penalty conditions and signature verification are finalized
    }

    function testInitiateExit() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);

        vm.roll(block.number + 32);
        registry.initiateExit(1.5 ether);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory info = registry
            .getRegistrantInfo(registrant);
        assertEq(info.balance, 2 ether);
        assertEq(info.exitInitiatedAt, block.number);
        assertEq(info.amountExiting, 1.5 ether);

        PreconfirmationRegistry.Status status = registry.getProposerStatus(
            proposer
        );
        assertEq(uint(status), uint(PreconfirmationRegistry.Status.EXITING));
        assertEq(registry.getEffectiveCollateral(proposer), 2 ether);
    }

    function testWithdraw() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);

        vm.roll(block.number + 32);
        registry.initiateExit(1.5 ether);
        vm.roll(block.number + 32);
        uint256 balanceBefore = registrant.balance;
        registry.withdraw(registrant);
        vm.stopPrank();

        assertEq(registrant.balance - balanceBefore, 1.5 ether);
        assertEq(registry.getRegistrantInfo(registrant).balance, 0.5 ether);

        PreconfirmationRegistry.Status status = registry.getProposerStatus(
            proposer
        );
        assertEq(uint(status), uint(PreconfirmationRegistry.Status.INCLUDER));
        assertEq(registry.getEffectiveCollateral(proposer), 0.5 ether);
    }

    function testMultipleDelegations() public {
        address proposer2 = vm.addr(3);
        vm.deal(registrant, 3 ether);

        vm.startPrank(registrant);
        registry.register{value: 3 ether}();

        address[] memory proposers = new address[](2);
        proposers[0] = proposer;
        proposers[1] = proposer2;
        registry.delegate(proposers);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory registrantInfo = registry
            .getRegistrantInfo(registrant);
        PreconfirmationRegistry.Proposer memory proposerInfo1 = registry
            .getProposerInfo(proposer);
        PreconfirmationRegistry.Proposer memory proposerInfo2 = registry
            .getProposerInfo(proposer2);

        assertEq(registrantInfo.delegatedProposers.length, 2);
        assertEq(registrantInfo.delegatedProposers[0], proposer);
        assertEq(registrantInfo.delegatedProposers[1], proposer2);
        assertEq(proposerInfo1.delegatedBy.length, 1);
        assertEq(proposerInfo1.delegatedBy[0], registrant);
        assertEq(proposerInfo2.delegatedBy.length, 1);
        assertEq(proposerInfo2.delegatedBy[0], registrant);
    }

    function testUpdateStatusMultipleProposers() public {
        address proposer2 = vm.addr(3);
        vm.deal(registrant, 3 ether);

        vm.startPrank(registrant);
        registry.register{value: 3 ether}();

        address[] memory proposers = new address[](2);
        proposers[0] = proposer;
        proposers[1] = proposer2;
        registry.delegate(proposers);
        vm.stopPrank();

        vm.roll(block.number + 32);

        registry.updateStatus(proposers);

        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.PRECONFER)
        );
        assertEq(
            uint(registry.getProposerStatus(proposer2)),
            uint(PreconfirmationRegistry.Status.PRECONFER)
        );
        assertEq(registry.getEffectiveCollateral(proposer), 3 ether);
        assertEq(registry.getEffectiveCollateral(proposer2), 3 ether);
    }

    function testWithdrawToDifferentAddress() public {
        address withdrawAddress = vm.addr(3);

        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        registry.initiateExit(1 ether);
        vm.stopPrank();

        vm.roll(block.number + 32);

        uint256 balanceBefore = withdrawAddress.balance;
        vm.prank(registrant);
        registry.withdraw(withdrawAddress);

        assertEq(withdrawAddress.balance - balanceBefore, 1 ether);
    }

    function testInitiateExitInsufficientBalance() public {
        vm.startPrank(registrant);
        registry.register{value: 1 ether}();
        vm.expectRevert("Insufficient balance");
        registry.initiateExit(2 ether);
        vm.stopPrank();
    }

    function testRedelegate() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers1 = new address[](1);
        proposers1[0] = proposer;
        registry.delegate(proposers1);

        address proposer2 = vm.addr(3);
        address[] memory proposers2 = new address[](1);
        proposers2[0] = proposer2;
        registry.delegate(proposers2);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory registrantInfo = registry
            .getRegistrantInfo(registrant);
        PreconfirmationRegistry.Proposer memory proposerInfo1 = registry
            .getProposerInfo(proposer);
        PreconfirmationRegistry.Proposer memory proposerInfo2 = registry
            .getProposerInfo(proposer2);

        assertEq(registrantInfo.delegatedProposers.length, 2);
        assertEq(registrantInfo.delegatedProposers[0], proposer);
        assertEq(registrantInfo.delegatedProposers[1], proposer2);
        assertEq(proposerInfo1.delegatedBy.length, 1);
        assertEq(proposerInfo2.delegatedBy.length, 1);
        assertEq(proposerInfo2.delegatedBy[0], registrant);
    }

    function testUpdateStatusBelowMinimum() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        vm.roll(block.number + 32);
        registry.updateStatus(proposers);

        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.PRECONFER)
        );

        vm.prank(registrant);
        registry.initiateExit(1.5 ether);

        registry.updateStatus(proposers);

        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.EXITING)
        );
        assertEq(registry.getEffectiveCollateral(proposer), 2 ether);

        vm.roll(block.number + 32);

        vm.prank(registrant);
        registry.withdraw(registrant);

        registry.updateStatus(proposers);

        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.INCLUDER)
        );
        assertEq(registry.getEffectiveCollateral(proposer), 0.5 ether);
    }

    function testWithdrawTwice() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        registry.initiateExit(1 ether);
        vm.stopPrank();

        vm.roll(block.number + 32);

        vm.prank(registrant);
        registry.withdraw(registrant);

        vm.prank(registrant);
        vm.expectRevert("Exit not initiated");
        registry.withdraw(registrant);
    }

    function testMultipleExits() public {
        vm.startPrank(registrant);
        registry.register{value: 3 ether}();
        registry.initiateExit(1 ether);

        vm.roll(block.number + 1);

        registry.initiateExit(2 ether);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory info = registry
            .getRegistrantInfo(registrant);
        assertEq(info.amountExiting, 2 ether);
        assertEq(info.exitInitiatedAt, block.number);
    }

    function testUpdateStatusNonExistentProposer() public {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0);
        registry.updateStatus(proposers);

        assertEq(
            uint(registry.getProposerStatus(address(0))),
            uint(PreconfirmationRegistry.Status.INCLUDER)
        );
    }

    function testRetrieveInformation() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory registrantInfo = registry
            .getRegistrantInfo(registrant);
        PreconfirmationRegistry.Proposer memory proposerInfo = registry
            .getProposerInfo(proposer);

        assertEq(registrantInfo.balance, 2 ether);
        assertEq(registrantInfo.enteredAt, block.number + ACTIVATION_DELAY);
        assertEq(registrantInfo.delegatedProposers.length, 1);
        assertEq(registrantInfo.delegatedProposers[0], proposer);

        assertEq(proposerInfo.delegatedBy.length, 1);
        assertEq(proposerInfo.delegatedBy[0], registrant);
        assertEq(
            uint(proposerInfo.status),
            uint(PreconfirmationRegistry.Status.INCLUDER)
        );
    }

    function testActivationDelay() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        // Before activation delay
        registry.updateStatus(proposers);
        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.INCLUDER)
        );

        // After activation delay
        vm.roll(block.number + ACTIVATION_DELAY);
        registry.updateStatus(proposers);
        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.PRECONFER)
        );
    }

    function testDelegateBeforeActivationDelay() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        registry.delegate(proposers);
        vm.stopPrank();

        registry.updateStatus(proposers);
        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.INCLUDER)
        );
        assertEq(registry.getEffectiveCollateral(proposer), 0);

        vm.roll(block.number + ACTIVATION_DELAY - 1);
        registry.updateStatus(proposers);
        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.INCLUDER)
        );
        assertEq(registry.getEffectiveCollateral(proposer), 0);

        vm.roll(block.number + 1);
        registry.updateStatus(proposers);
        assertEq(
            uint(registry.getProposerStatus(proposer)),
            uint(PreconfirmationRegistry.Status.PRECONFER)
        );
        assertEq(registry.getEffectiveCollateral(proposer), 2 ether);
    }

    function testWithdrawBeforeExitCooldown() public {
        vm.startPrank(registrant);
        registry.register{value: 2 ether}();
        registry.initiateExit(1 ether);

        vm.roll(block.number + EXIT_COOLDOWN - 1);

        vm.expectRevert("Cooldown period not over");
        registry.withdraw(registrant);

        vm.roll(block.number + 1);
        registry.withdraw(registrant);
        vm.stopPrank();

        PreconfirmationRegistry.Registrant memory info = registry
            .getRegistrantInfo(registrant);
        assertEq(info.balance, 1 ether);
        assertEq(info.amountExiting, 0);
    }
}
