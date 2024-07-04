# Writing Penalty Conditions for your Proposer Commitments
Penalty conditions (or slashing conditions) represent the conditions under which a proposer should be penalized (slashed or frozen). These can also be used to slash another form of collateral, such as restaked ETH in another contract.

## Overview
Penalty conditions are EVM bytecode that, when executed, eventually return a `Penalty` struct. The `Penalty` struct contains three fields:

- `weiSlashed`: the amount of wei that should be slashed from the proposer's balance
- `weiFrozen`: the amount of wei that should be frozen from the proposer's balance
- `blocksFrozen`: the number of blocks for which the proposer's balance should be frozen

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
4. The `getPenalty` function returns a `Penalty` struct or causes the transaction to revert.
5. The `PreconfirmationRegistry` contract applies the `Penalty` struct to the registrants who have delegated to the proposer, if the `Penalty` struct is not empty. If the `getPenalty` function reverts, the proposer is not slashed or frozen, and the `applyPenalty` function is reverted.
6. The `PreconfirmationRegistry` contract updates the proposer's status.
7. The `PreconfirmationRegistry` contract emits a `PenaltyApplied` event.

### Data?
The special `data` parameter is used to pass additional data to the `getPenalty` function. This can include any situational information about the preconfirmation commitment that is relevant to determining the appropriate penalty. For example, the `data` parameter could include a signature from the proposer, a block number, an L2 transaction hash, etc. 

This design choice is made so that a proposer only needs to sign off on the `penaltyConditions` bytecode once for all preconfirmation commitments they might make. The leader election module can also determine if a proposer has signed off on a `penaltyConditions` bytecode without the proposer having to make a commitment, which could be used to do leader election.

## Examples
See `test/RegistryPenalties.t.sol` (the contracts at the top) for examples of simple penalty conditions. 

## Writing and Testing your own Penalty Conditions
In this quick tutorial, we will write penalty conditions that freeze a proposer's balance for 100 blocks if they signed a promise about a blockhash and blocknumber that was not correct (this is just a toy example, you can use any situation you want).

### Determining the `data`
We need to list the requirements to determine if slashing should occur:
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
The `getPenalty` function is where the actual slashing logic is implemented. It takes in the `data` and the proposer's address and returns a `Penalty` struct. The `Penalty` struct is defined as follows:

```solidity
struct Penalty {
    uint256 weiSlashed;
    uint256 weiFrozen;
    uint256 blocksFrozen;
}
```

In this case, we will freeze the proposer's balance by `1 ether` for `100` blocks if the blockhash and blocknumber in the commitment are incorrect. 

```solidity
function getPenalty(
    bytes calldata data,
    address proposer
) external returns (Penalty memory) {
    BlockHashCommitmentData memory commitmentData = abi.decode(data, (BlockHashCommitmentData));

    // special check to make sure the block number is not too far in the past for blockhash() to be correct
    require(block.number - commitmentData.blockNumber < 256, "Block number too far in the past");    

    // verify signature
    bytes32 messageHash = keccak256(abi.encode(commitmentData.blockHash, commitmentData.blockNumber));
    address signer = messageHash.recover(commitmentData.signature);
    require(signer == proposer, "Invalid signature");
    
    if (commitmentData.blockHash != blockhash(commitmentData.blockNumber)) {
        return Penalty(0 ether, 1 ether, 100);
    }
    return Penalty(0 ether, 0 ether, 0);
}
```

### Putting it all together
Let's wrap it all up with a contract that imports the necessary libraries!

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
See examples in `test/RegistryPenalties.t.sol` (the contracts at the top) for examples of testing penalty conditions.

**See the foundry script in `script/PenaltyConditions.s.sol` for a working tool to test your penalty conditions on given data.**
### Usage
*install foundry with foundryup, clone this repo and navigate to the repo directory*

Create a `.env` file in the root directory of the repo with the following contents:
```
PROPOSER_ADDRESS=0x...
PENALTY_CONDITIONS_PATH="src/examples/BlockHashCommitment.sol:BlockHashCommitment"
PENALTY_CONDITIONS_DATA=0x...
```

`PROPOSER_ADDRESS` is the address of the proposer that will be used to call the `getPenalty` function.
`PENALTY_CONDITIONS_PATH` is the path to the penalty conditions contract, see forge docs for more info.
`PENALTY_CONDITIONS_DATA` is the data that will be passed to the `getPenalty` function. 

Then run the script:

```bash
forge script script/PenaltyConditions.s.sol:PenaltyConditionsScript
```

You can also see the forge script docs to do things like fork mainnet state and test against it.

For the example `.env` given above you can generate the `data` with the following with a block hash and number from etherscan:
```solidity
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

contract GenerateMockData is Test {
    address public proposer;
    uint256 public proposerPrivateKey;

    function setUp() public {
        (proposer, proposerPrivateKey) = makeAddrAndKey("proposer"); (
    }

    function testGenerateData() public {
        console.log(proposer);

        bytes32 messageHash = keccak256(abi.encode(/* blockHash */, /* blockNumber */));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(proposerPrivateKey, messageHash);
        bytes memory sig = abi.encodePacked(r, s, v);
    
        BlockHashCommitmentData memory data = BlockHashCommitmentData({
            blockNumber: /* blockNumber */,
            blockHash: /* blockHash */,
            signature: sig
        });

        console.logBytes(abi.encode(data));
    }
}
```

Fill out the above and copy the `0x...` printed by running (assuming your file is at `test/GenerateMockData.t.sol`) into your `.env` file:
```bash
forge test -vv --via-ir test/GenerateMockData.t.sol
```

Then run the script, forking mainnet so block numbers work:
```bash
forge script --fork-url https://eth.llamarpc.com --fork-block-number /* the block number you chose above + 1 */ -vv script/PenaltyConditions.s.sol:PenaltyConditionsScript
```

Mess around with the `data` and the `signature` until you get the desired penalty!

Here is an example `.env` with a penalty!
```bash
PROPOSER_ADDRESS="0x6bEf539e8319dACba4C2DaD055006E79682C0f32"
PENALTY_CONDITIONS_PATH="src/examples/BlockHashCommitment.sol:BlockHashCommitment"
PENALTY_CONDITIONS_DATA=0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000134ae33e3b392260379e4bb58e605f9c21284abe63b1bd130d8058ed1503e18c1bcb80d00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000041855bd7c264c16057c472a1aa6854534558a3cc9cd78d8db16a3625c5dde69b545ca8f43db7bb6f6a7c6d83fa3d1835c92b225cb7d0a70860c3a1159e85a3546e1b00000000000000000000000000000000000000000000000000000000000000
```

Run with:
```bash
forge script --fork-url https://eth.llamarpc.com --fork-block-number 20229684 -vv script/PenaltyConditions.s.sol:PenaltyConditionsScript
```

## Literally Anything Else
Message me on telegram: https://t.me/mteam888
