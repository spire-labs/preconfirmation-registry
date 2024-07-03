# Writing Penalty Conditions for you Proposer Commitments
Penalty conditions (or slashing conditions) represent the conditions under which a proposer should be penalized (slashing or frozen). These can also be used to slash another form of collateral, such as restaked ETH in another contract.

## Overview
Penalty conditions are EVM bytecode that, when executed, eventually return a `Penalty` struct. The `Penalty` struct contains three fields:

- `weiSlashed`: the amount of wei that should be slashed from the proposer's balance
- `weiFrozen`: the amount of wei that should be frozen from the proposer's balance
- `blocksFrozen`: the number of blocks that should be frozen from the proposer's balance

Note that slashing takes priority over freezing, meaning that if a proposer has no balance after being slashed, they will not be frozen.

The `Penalty` struct is defined as follows:

```solidity
struct Penalty {
    uint256 weiSlashed;
    uint256 weiFrozen;
    uint256 blocksFrozen;
}
```

The `Penalty` struct is returned by the `getPenalty` function, which is defined as follows:

```solidity
function getPenalty(
    bytes calldata data,
    address proposer
) external returns (Penalty memory);
```

Here is the flow:
1. The proposer calls `PreconfirmationRegistry.applyPenalty` with the `penaltyConditions` bytecode and the proposer's signature of the `penaltyConditions` bytecode.
2. The `PreconfirmationRegistry` contract verifies the signature and deploys the `penaltyConditions` bytecode.
3. The address where the `penaltyConditions` bytecode was deployed is called with the `data` and the proposer's address, at the function `getPenalty`.
4. The `getPenalty` function returns a `Penalty` struct or reverts.
5. The `PreconfirmationRegistry` contract applies the `Penalty` struct to the registrants that have delegated to the proposer, if the `Penalty` struct is not empty. If the `getPenalty` function reverts, the proposer is not slashed or frozen and `applyPenalty` is reverted.
6. The `PreconfirmationRegistry` contract updates the proposer's status.
7. The `PreconfirmationRegistry` contract emits a `PenaltyApplied` event.

### Data?
The special `data` parameter is used to pass additional data to the `getPenalty` function. This can include any situational information about the preconfirmation commitment that is relevant to determining the appropriate penalty. For example, the `data` parameter could include a signature from the proposer, a block number, a L2 transaction hash, etc. 

This design choice is made so that proposer only need to sign off on the `penaltyConditions` bytecode once for all preconfirmation commitments they might make. The leader election module can also determine if a proposer has signed off on a `penaltyConditions` bytecode without the proposer having to make a commitment, which could be used to do leader election.

## Examples
See `test/RegistryPenalties.t.sol` (the contracts at the top) for examples of some super simple penalty conditions. 

## Writing and Testing your own Penalty Conditions
In this quick tutorial we will write penalty conditions that freezes a proposer's balance for 100 blocks if they signed a promise about a blockhash and blocknumber that was not correct (this is just a toy example, you can use any situation you want).

### Determining the `data`
Listing what we will need to determine if slashing should occur:
- The block number for which the commitment was made
- The blockhash for which the commitment was made
- A signature from the proposer (let's say an ECDSA signature of `keccak256(abi.encode(blockhash, blocknumber))`) that we can verify.

I'll lay out my `data` with a solidity struct:
```solidity
struct BlockHashCommitmentData {
    uint256 blockNumber;
    bytes32 blockHash;
    bytes signature;
}
```

### Writing the `getPenalty` function
The `getPenalty` function is where the actual slashing logic is implemented. It takes in the `data` and the proposer's address, and returns a `Penalty` struct. The `Penalty` struct is defined as follows:

```solidity
struct Penalty {
    uint256 weiSlashed;
    uint256 weiFrozen;
    uint256 blocksFrozen;
}
```

In this case, we will slash the proposer's balance by `1 ether` and freeze their balance for `100` blocks if blockhash and blocknumber in the commitment is incorrect.

```solidity
function getPenalty(
    bytes calldata data,
    address proposer
) external returns (Penalty memory) {
    // special check to make sure the block number is not too far in the past for blockhash() to be correct
    require(block.number - commitmentData.blockNumber < 256, "Block number too far in the past");    

    BlockHashCommitmentData memory commitmentData = abi.decode(data, (BlockHashCommitmentData));

    // verify signature
    bytes32 messageHash = keccak256(abi.encode(commitmentData.blockHash, commitmentData.blockNumber));
    address signer = messageHash.recover(commitmentData.signature);
    require(signer == proposer, "Invalid signature");
    
    if (commitmentData.blockHash != blockhash(commitmentData.blockNumber)) {
        return Penalty(1 ether, 0 ether, 100);
    }
    return Penalty(0 ether, 0 ether, 0);
}
```

### Putting it all together
Let's wrap it all up with a contract that imports necessary libraries!

```solidity
// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BlockHashCommitment {
    using ECDSA for bytes32;

    struct BlockHashCommitmentData {
        uint256 blockNumber;
        bytes32 blockHash;
        bytes signature;
    }

    struct Penalty {
        uint256 weiSlashed;
        uint256 weiFrozen;
        uint256 blocksFrozen;
    }

    function getPenalty(
        bytes calldata data,
        address proposer
    ) external returns (Penalty memory) {
        /* see above */
    }
}
```

### Testing the penalty conditions
See exampels in `test/RegistryPenalties.t.sol` (the contracts at the top) for examples of testing penalty conditions.

*I'm currently working on a foundry script that will compile and test your penalty conditions for you. Stay tuned!*
