// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PreconfirmationRegistry
 * @notice A contract for managing registrants and proposers in a preconfirmation system
 */
contract PreconfirmationRegistry {
    using ECDSA for bytes32;

    struct Registrant {
        uint256 balance;
        uint256 frozenBalance;
        uint256 enteredAt;
        uint256 exitInitiatedAt;
        uint256 amountExiting;
        address[] delegatedProposers;
    }

    struct Proposer {
        Status status;
        uint256 effectiveCollateral;
        address[] delegatedBy;
    }

    enum Status {
        INCLUDER,
        EXITING,
        PRECONFER
    }

    struct Penalty {
        uint256 weiSlashed;
        uint256 weiFrozen;
        uint256 blocksFrozen;
    }

    mapping(address => Registrant) public registrants;
    mapping(address => Proposer) public proposers;
    uint256 public immutable MINIMUM_COLLATERAL;
    uint256 public immutable ACTIVATION_DELAY;
    uint256 public immutable EXIT_COOLDOWN;
    uint256 totalBalance;

    event Registered(address indexed registrant, uint256 amount);
    event Delegated(address indexed registrant, address[] proposers);
    event PenaltyApplied(address indexed proposer, Penalty penalty);
    event ExitInitiated(address indexed registrant, uint256 amount);
    event Withdrawn(address indexed registrant, uint256 amount);

    /**
     * @notice Constructor to initialize the PreconfirmationRegistry
     * @param _minimumCollateral The minimum amount of collateral required for registration
     * @param _activationDelay The number of blocks to wait before activation
     * @param _exitCooldown The number of blocks to wait before exiting
     */
    constructor(
        uint256 _minimumCollateral,
        uint256 _activationDelay,
        uint256 _exitCooldown
    ) {
        MINIMUM_COLLATERAL = _minimumCollateral;
        ACTIVATION_DELAY = _activationDelay;
        EXIT_COOLDOWN = _exitCooldown;
    }

    /**
     * @notice Register a new registrant
     * @dev Requires a non-zero value to be sent with the transaction
     * @dev Emits a Registered event
     */
    function register() external payable {
        require(registrants[msg.sender].enteredAt == 0, "Already registered");
        require(msg.value > 0, "Insufficient registration amount");
        registrants[msg.sender] = Registrant({
            balance: msg.value,
            frozenBalance: 0,
            enteredAt: block.number + ACTIVATION_DELAY,
            exitInitiatedAt: 0,
            amountExiting: 0,
            delegatedProposers: new address[](0)
        });
        totalBalance += msg.value;
        emit Registered(msg.sender, msg.value);
    }

    /**
     * @notice Delegate to one or more proposers
     * @param _proposers An array of proposer addresses to delegate to
     * @dev Requires the sender to be registered
     * @dev Emits a Delegated event
     */
    function delegate(address[] calldata _proposers) external {
        require(registrants[msg.sender].enteredAt != 0, "Not registered");
        for (uint i = 0; i < _proposers.length; i++) {
            address proposer = _proposers[i];
            registrants[msg.sender].delegatedProposers.push(proposer);
            proposers[proposer].delegatedBy.push(msg.sender);
        }
        emit Delegated(msg.sender, _proposers);
    }

    /**
     * @notice Update the status of one or more proposers
     * @param _proposers An array of proposer addresses to update
     * @dev Updates the effective collateral and status of each proposer
     */
    function updateStatus(address[] calldata _proposers) public {
        for (uint i = 0; i < _proposers.length; i++) {
            uint256 effectiveCollateral = 0;
            uint256 collateralExiting = 0;
            address proposer = _proposers[i];
            for (uint j = 0; j < proposers[proposer].delegatedBy.length; j++) {
                address registrant = proposers[proposer].delegatedBy[j];
                if (registrants[registrant].enteredAt <= block.number) {
                    effectiveCollateral +=
                        registrants[registrant].balance -
                        registrants[registrant].frozenBalance;
                    collateralExiting += registrants[registrant].amountExiting;
                }
            }

            if (effectiveCollateral - collateralExiting >= MINIMUM_COLLATERAL) {
                proposers[proposer].status = Status.PRECONFER;
            } else if (effectiveCollateral < MINIMUM_COLLATERAL) {
                proposers[proposer].status = Status.INCLUDER;
            } else {
                proposers[proposer].status = Status.EXITING;
            }
            proposers[proposer].effectiveCollateral = effectiveCollateral;
        }
    }

    /**
     * @notice Apply a penalty to a proposer
     * @param proposer The address of the proposer to penalize
     * @param penaltyConditions The bytecode of the penalty conditions contract
     * @param penaltyConditionsSignature The signature of the penalty conditions
     * @param data Additional data for penalty calculation
     * @dev Requires the proposer to be registered and the signature to be valid
     * @dev Emits a PenaltyApplied event if a non-empty penalty is applied
     */
    function applyPenalty(
        address proposer,
        bytes calldata penaltyConditions,
        bytes calldata penaltyConditionsSignature,
        bytes calldata data
    ) external {
        require(isRegisteredProposer(proposer), "Proposer not registered");
        require(
            verifySignature(
                proposer,
                penaltyConditions,
                penaltyConditionsSignature
            ),
            "Invalid signature"
        );

        Penalty memory penalty = executePenaltyConditions(
            penaltyConditions,
            data,
            proposer
        );
        if (isPenaltyEmpty(penalty)) {
            return;
        }

        applyPenaltyToRegistrants(proposer, penalty);

        emit PenaltyApplied(proposer, penalty);
    }

    /**
     * @notice Check if an address is a registered proposer
     * @param proposer The address to check
     * @return bool True if the address is a registered proposer, false otherwise
     */
    function isRegisteredProposer(address proposer) public view returns (bool) {
        return proposers[proposer].status != Status.INCLUDER;
    }

    /**
     * @notice Verify the signature of penalty conditions
     * @param proposer The address of the proposer
     * @param penaltyConditions The penalty conditions bytecode
     * @param signature The signature to verify
     * @return bool True if the signature is valid, false otherwise
     */
    function verifySignature(
        address proposer,
        bytes memory penaltyConditions,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 messageHash = keccak256(penaltyConditions);
        return messageHash.recover(signature) == proposer;
    }

    /**
     * @notice Execute penalty conditions and return the resulting penalty
     * @param penaltyConditions The bytecode of the penalty conditions contract
     * @param data Additional data for penalty calculation
     * @param proposer The address of the proposer
     * @return Penalty The calculated penalty
     * @dev Deploys the penalty conditions contract and calls its getPenalty function
     */
    function executePenaltyConditions(
        bytes memory penaltyConditions, 
        bytes memory data,
        address proposer
    ) public returns (Penalty memory) {
        address penaltyConditionsContract = deployFromBytecode(penaltyConditions);

        (bool success, bytes memory result) = penaltyConditionsContract.call(
                abi.encodeWithSignature(
                    "getPenalty(bytes,address)",
                    data,
                    proposer
                )
            );

        require(success, "Penalty conditions execution failed");

        return abi.decode(result, (Penalty));
    }

    /**
     * @notice Deploy a contract from bytecode
     * @param bytecode The bytecode of the contract to deploy
     * @return address The address of the deployed contract
     * @dev Uses inline assembly to deploy the contract
     */
    function deployFromBytecode(bytes memory bytecode) public returns (address) {
        address child;
        assembly{
            mstore(0x0, bytecode)
            child := create(0,0xa0, calldatasize())
        }
        return child;
   }

    /**
     * @notice Check if a penalty is empty (all values are zero)
     * @param penalty The penalty to check
     * @return bool True if the penalty is empty, false otherwise
     */
    function isPenaltyEmpty(Penalty memory penalty) public pure returns (bool) {
        return
            penalty.weiSlashed == 0 &&
            penalty.weiFrozen == 0 &&
            penalty.blocksFrozen == 0;
    }

    /**
     * @notice Apply a penalty to all registrants delegating to a proposer
     * @param proposer The address of the proposer
     * @param penalty The penalty to apply
     * @dev Updates the balances and frozen balances of affected registrants
     * @dev Updates the status of all proposers the affected registrants have delegated to
     */
    function applyPenaltyToRegistrants(
        address proposer,
        Penalty memory penalty
    ) public {
        Proposer storage prop = proposers[proposer];
        uint256 registrantCount = prop.delegatedBy.length;
        require(registrantCount > 0, "No registrants for this proposer");

        for (uint256 i = 0; i < registrantCount; i++) {
            address registrantAddr = prop.delegatedBy[i];
            Registrant storage registrant = registrants[registrantAddr];

            uint256 weiSlashedPerRegistrant = penalty.weiSlashed * registrant.balance / totalBalance;
            uint256 weiFrozenPerRegistrant = penalty.weiFrozen * registrant.balance / totalBalance;

            applySlashing(registrant, weiSlashedPerRegistrant);
            applyFreezing(registrant, weiFrozenPerRegistrant);
            
            this.updateStatus(registrant.delegatedProposers);
        }

        totalBalance -= penalty.weiSlashed + penalty.weiFrozen;
    }

    /**
     * @notice Apply slashing to a registrant's balance
     * @param registrant The registrant to slash
     * @param weiToSlash The amount of wei to slash
     * @return uint256 The actual amount of wei slashed
     * @dev Internal function, called by applyPenaltyToRegistrants
     */
    function applySlashing(
        Registrant storage registrant,
        uint256 weiToSlash
    ) internal returns (uint256) {
        uint256 availableToSlash = registrant.balance -
            registrant.frozenBalance;
        uint256 actualWeiSlashed = weiToSlash > availableToSlash
            ? availableToSlash
            : weiToSlash;
        registrant.balance -= actualWeiSlashed;
        return actualWeiSlashed;
    }

    /**
     * @notice Apply freezing to a registrant's balance
     * @param registrant The registrant to freeze
     * @param weiToFreeze The amount of wei to freeze
     * @return uint256 The actual amount of wei frozen
     * @dev Internal function, called by applyPenaltyToRegistrants
     */
    function applyFreezing(
        Registrant storage registrant,
        uint256 weiToFreeze
    ) internal returns (uint256) {
        uint256 availableToFreeze = registrant.balance -
            registrant.frozenBalance;
        uint256 actualWeiFrozen = weiToFreeze > availableToFreeze
            ? availableToFreeze
            : weiToFreeze;
        registrant.frozenBalance += actualWeiFrozen;
        return actualWeiFrozen;
    }

    /**
     * @notice Initiate the exit process for a registrant
     * @param amount The amount of wei to exit
     * @dev Requires the sender to be registered and have sufficient balance
     * @dev Emits an ExitInitiated event
     */
    function initiateExit(uint256 amount) external {
        Registrant storage registrant = registrants[msg.sender];
        require(registrant.enteredAt != 0, "Not registered");
        require(registrant.balance >= amount, "Insufficient balance");
        registrant.exitInitiatedAt = block.number;
        registrant.amountExiting = amount;
        totalBalance -= amount;

        this.updateStatus(registrant.delegatedProposers);

        emit ExitInitiated(msg.sender, amount);
    }

    /**
     * @notice Withdraw funds after the exit cooldown period
     * @param to The address to send the withdrawn funds to
     * @dev Requires the exit process to be initiated and the cooldown period to be over
     * @dev Emits a Withdrawn event
     */
    function withdraw(address to) external {
        Registrant storage registrant = registrants[msg.sender];
        require(registrant.exitInitiatedAt != 0, "Exit not initiated");
        require(
            block.number >= registrant.exitInitiatedAt + EXIT_COOLDOWN,
            "Cooldown period not over"
        );
        require(
            registrant.amountExiting <= registrant.balance,
            "Not enough funds to withdraw"
        );

        uint256 amountToWithdraw = registrant.amountExiting;
        registrant.balance -= amountToWithdraw;
        registrant.exitInitiatedAt = 0;
        registrant.amountExiting = 0;

        payable(to).transfer(amountToWithdraw);

        this.updateStatus(registrant.delegatedProposers);

        emit Withdrawn(msg.sender, amountToWithdraw);
    }

    /**
     * @notice Get the status of a proposer
     * @param proposer The address of the proposer
     * @return Status The current status of the proposer
     */
    function getProposerStatus(
        address proposer
    ) external view returns (Status) {
        return proposers[proposer].status;
    }

    /**
     * @notice Get the effective collateral of a proposer
     * @param proposer The address of the proposer
     * @return uint256 The effective collateral of the proposer
     */
    function getEffectiveCollateral(
        address proposer
    ) public view returns (uint256) {
        return proposers[proposer].effectiveCollateral;
    }

    /**
     * @notice Get the information of a registrant
     * @param registrant The address of the registrant
     * @return Registrant The registrant's information
     */
    function getRegistrantInfo(
        address registrant
    ) external view returns (Registrant memory) {
        return registrants[registrant];
    }

    /**
     * @notice Get the information of a proposer
     * @param proposer The address of the proposer
     * @return Proposer The proposer's information
     */
    function getProposerInfo(
        address proposer
    ) external view returns (Proposer memory) {
        return proposers[proposer];
    }
}
