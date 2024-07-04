# Delegating to Proposers
This script delegates a registrant's stake to a list of proposers.

## Set your environment variables
To delegate to proposers, you need to set the following environment variables:

- `REGISTRANT_PRIVATE_KEY`: The private key of the registrant account. This account will be used to delegate to proposers.
- `REGISTRY_ADDRESS`: The address of the deployed preconfirmation registry.
- `DELEGATEE_ADDRESSES`: A comma-separated list of addresses of the proposers to delegate to.

```bash
# example of DELEGATEE_ADDRESSES
DELEGATEE_ADDRESSES="0x123","0x456","0x789"
```

## Delegate to proposers

To delegate to proposers, run the following command in the root directory of this project and with foundry installed:

```bash
forge script script/Delegate.s.sol --rpc-url <RPC_URL> --broadcast -vvvv
```

Replace `<RPC_URL>` with the RPC URL of the network you want to delegate on.
