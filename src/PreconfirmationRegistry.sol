// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract PreconfirmationRegistry {
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

    event Registered(address indexed registrant, uint256 amount);
    event Delegated(address indexed registrant, address[] proposers);
    event PenaltyApplied(address indexed proposer, Penalty penalty);
    event ExitInitiated(address indexed registrant, uint256 amount);
    event Withdrawn(address indexed registrant, uint256 amount);

    constructor(
        uint256 _minimumCollateral,
        uint256 _activationDelay,
        uint256 _exitCooldown
    ) {
        MINIMUM_COLLATERAL = _minimumCollateral;
        ACTIVATION_DELAY = _activationDelay;
        EXIT_COOLDOWN = _exitCooldown;
    }

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
        emit Registered(msg.sender, msg.value);
    }

    function delegate(address[] calldata _proposers) external {
        require(registrants[msg.sender].enteredAt != 0, "Not registered");
        for (uint i = 0; i < _proposers.length; i++) {
            address proposer = _proposers[i];
            registrants[msg.sender].delegatedProposers.push(proposer);
            proposers[proposer].delegatedBy.push(msg.sender);
        }
        emit Delegated(msg.sender, _proposers);
    }

    function updateProposerStatus(address proposer) internal {}

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

    function applyPenalty(
        address proposer,
        bytes calldata penaltyConditions,
        bytes calldata penaltyConditionsSignature,
        bytes calldata data
    ) external {
        // This function needs to be implemented
        // It should verify the signature, execute the penalty conditions,
        // and apply the resulting penalty
    }

    function initiateExit(uint256 amount) external {
        Registrant storage registrant = registrants[msg.sender];
        require(registrant.enteredAt != 0, "Not registered");
        require(registrant.balance >= amount, "Insufficient balance");
        registrant.exitInitiatedAt = block.number;
        registrant.amountExiting = amount;

        // Update status of all proposers this registrant has delegated to
        this.updateStatus(registrant.delegatedProposers);

        emit ExitInitiated(msg.sender, amount);
    }

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

        // Update status of all proposers this registrant has delegated to
        this.updateStatus(registrant.delegatedProposers);

        emit Withdrawn(msg.sender, amountToWithdraw);
    }

    function getProposerStatus(
        address proposer
    ) external view returns (Status) {
        return proposers[proposer].status;
    }

    function getEffectiveCollateral(
        address proposer
    ) public view returns (uint256) {
        return proposers[proposer].effectiveCollateral;
    }

    function getRegistrantInfo(
        address registrant
    ) external view returns (Registrant memory) {
        return registrants[registrant];
    }

    function getProposerInfo(
        address proposer
    ) external view returns (Proposer memory) {
        return proposers[proposer];
    }
}
