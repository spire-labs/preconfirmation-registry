// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PreconfirmationRegistry.sol";

// This script delegates a registrant's stake to a delegatee.

contract DelegateScript is Script {
    function run() public {
        // read environment variables
        uint256 registrantPrivateKey = vm.envUint("REGISTRANT_PRIVATE_KEY");
        PreconfirmationRegistry registry = PreconfirmationRegistry(vm.envAddress("REGISTRY_ADDRESS"));
        address[] memory delegatees = vm.envAddress("DELEGATEE_ADDRESSES", ",");

        vm.startBroadcast(registrantPrivateKey);
        
        registry.delegate(delegatees);
    }
}