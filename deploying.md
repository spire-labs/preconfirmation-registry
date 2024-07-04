# Deploying the Preconfirmation Registry

## Set your environment variables

Before deploying the registry, you need to set the following environment variables:

- `DEPLOYER_PRIVATE_KEY`: The private key of the deployer account. This account will be used to deploy the registry.
- `MINIMUM_COLLATERAL`: The minimum collateral required to register as a proposer.
- `ACTIVATION_DELAY`: The number of blocks the registrant must wait before being able to propose.
- `EXIT_COOLDOWN`: The number of blocks the registrant must wait before being able to withdraw their funds.

## Deploy the registry

To deploy the registry, run the following command in the root directory of this project and with foundry installed:

```bash
forge script script/DeployRegistry.s.sol --rpc-url <RPC_URL> --broadcast -vvvv
```

Replace `<RPC_URL>` with the RPC URL of the network you want to deploy to.

This script will deploy the registry and print the address of the deployed contract to the console.
