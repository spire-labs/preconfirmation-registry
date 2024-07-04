// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PreconfirmationRegistry.sol";

// This script accepts a smart contract path as an env parameter and deploys it, then executes the getPenalty function with the provided data to determine the penalty. 
// Then, the penalty is displayed to the user.
// This script should be used to test penalty conditions contracts.
contract PenaltyConditionsScript is Script {
    function run() public {
        address proposerAddress = vm.envAddress("PROPOSER_ADDRESS");
        string memory path = vm.envString("PENALTY_CONDITIONS_PATH");
        bytes memory data = vm.envBytes("PENALTY_CONDITIONS_DATA");

        exec(path, data, proposerAddress);
    }

    function exec(string memory path, bytes memory data, address proposerAddress) public {
        // set up the preconfirmation registry
        PreconfirmationRegistry registry = new PreconfirmationRegistry(100 ether, 32, 32);

        // set up 2 registrants
        address registrant1 = makeAddr("registrant1");
        address registrant2 = makeAddr("registrant2");

        vm.deal(registrant1, 150 ether);
        vm.deal(registrant2, 150 ether);

        vm.prank(registrant1);
        registry.register{value: 150 ether}();

        vm.prank(registrant2);
        registry.register{value: 150 ether}();

        address[] memory proposers = new address[](1);
        proposers[0] = proposerAddress;

        vm.prank(registrant1);
        registry.delegate(proposers);

        vm.prank(registrant2);
        registry.delegate(proposers);

        vm.roll(block.number + 32);

        vm.prank(address(registry));

        // get the penalty conditions contract
        bytes memory penaltyConditions = vm.getCode(path);

        // get the penalty
        PreconfirmationRegistry.Penalty memory penalty = registry.executePenaltyConditions(penaltyConditions, data, proposerAddress); 

        // display the penalty
        console.log("Penalty:");
        console.log("weiSlashed: ", penalty.weiSlashed);
        console.log("weiFrozen: ", penalty.weiFrozen);
        console.log("blocksFrozen: ", penalty.blocksFrozen);
    }
}