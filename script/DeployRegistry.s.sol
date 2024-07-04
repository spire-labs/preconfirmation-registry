// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PreconfirmationRegistry.sol";

// This script deploys the preconfirmation registry.

contract DeployRegistryScript is Script {
    function run() public {
        // env variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 minimumCollateral = vm.envUint("MINIMUM_COLLATERAL");
        uint256 activationDelay = vm.envUint("ACTIVATION_DELAY");
        uint256 exitCooldown = vm.envUint("EXIT_COOLDOWN");

        vm.startBroadcast(deployerPrivateKey);

        new PreconfirmationRegistry(minimumCollateral, activationDelay, exitCooldown);
    }
}