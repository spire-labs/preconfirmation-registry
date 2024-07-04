# Registering as a Registrant
This script registers a registrant with a deployed preconfirmation registry.

## Set your environment variables
To register as a registrant, you need to set the following environment variables:

- `REGISTRANT_PRIVATE_KEY`: The private key of the registrant account. This account will be used to register as a registrant.
- `REGISTRY_ADDRESS`: The address of the deployed preconfirmation registry.
- `REGISTER_AMOUNT_WEI`: The amount of wei to register with the registry.

## Register as a registrant

To register as a registrant, run the following command in the root directory of this project and with foundry installed:

```bash
forge script script/Register.s.sol --rpc-url <RPC_URL> --broadcast -vvvv
```

Replace `<RPC_URL>` with the RPC URL of the network you want to register on.
