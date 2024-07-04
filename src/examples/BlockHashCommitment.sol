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
    ) external view returns (Penalty memory) {
        BlockHashCommitmentData memory commitmentData = abi.decode(
            data,
            (BlockHashCommitmentData)
        );

        // special check to make sure the block number is not too far in the past for blockhash() to be correct
        require(
            block.number - commitmentData.blockNumber < 256,
            "Block number too far in the past"
        );

        // verify signature
        bytes32 messageHash = keccak256(
            abi.encode(commitmentData.blockHash, commitmentData.blockNumber)
        );
        address signer = messageHash.recover(commitmentData.signature);
        require(signer == proposer, "Invalid signature");

        if (commitmentData.blockHash != blockhash(commitmentData.blockNumber)) {
            return Penalty(0 ether, 1 ether, 100);
        }
        return Penalty(0 ether, 0 ether, 0);
    }
}
