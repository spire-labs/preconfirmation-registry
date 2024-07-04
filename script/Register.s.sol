// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PreconfirmationRegistry.sol";

// This script registers a registrant with the preconfirmation registry.

contract RegisterScript is Script {
    function run() public {
        // read environment variables
        uint256 registrantPrivateKey = vm.envUint("REGISTRANT_PRIVATE_KEY");
        PreconfirmationRegistry registry = PreconfirmationRegistry(vm.envAddress("REGISTRY_ADDRESS"));
        uint256 amountWei = vm.envUint("REGISTER_AMOUNT_WEI");

        vm.startBroadcast(registrantPrivateKey);
        
        registry.register{value: amountWei}();
    }
}