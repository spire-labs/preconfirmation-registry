// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract PreconfirmationRegistry {
    struct Registrant {
        uint256 balance;
        uint256 frozenBalance;
        uint256 enteredAt;
        uint256 exitInitiatedAt;
        address[] delegatedProposers;
    }

    struct Proposer {
        Status status;
        uint256 effectiveCollateral;
    }

    enum Status { INCLUDER, EXITING, PRECONFER }

    struct Penalty {
        uint256 weiSlashed;
        uint256 weiFrozen;
        uint256 blocksFrozen;
    }

    mapping(address => Registrant) public registrants;
    mapping(address => Proposer) public proposers;
    uint256 public immutable MINIMUM_COLLATERAL;
    uint256 public constant EXIT_COOLDOWN = 32; // blocks

    event Registered(address indexed registrant, uint256 amount);
    event Delegated(address indexed registrant, address[] proposers);
    event PenaltyApplied(address indexed proposer, Penalty penalty);
    event ExitInitiated(address indexed registrant, uint256 amount);
    event Withdrawn(address indexed registrant, uint256 amount);

    constructor(uint256 _minimumCollateral) {
        MINIMUM_COLLATERAL = _minimumCollateral;
    }

    function register() external payable {
        require(registrants[msg.sender].enteredAt == 0, "Already registered");
        registrants[msg.sender] = Registrant({
            balance: msg.value,
            frozenBalance: 0,
            enteredAt: block.number + 32,
            exitInitiatedAt: 0,
            delegatedProposers: new address[](0)
        });
        emit Registered(msg.sender, msg.value);
    }

    function delegate(address[] calldata _proposers) external {
        require(registrants[msg.sender].enteredAt != 0, "Not registered");
        registrants[msg.sender].delegatedProposers = _proposers;
        emit Delegated(msg.sender, _proposers);
    }

    function updateStatus(address[] calldata _proposers) external {
        for (uint i = 0; i < _proposers.length; i++) {
            address proposer = _proposers[i];
            uint256 effectiveCollateral = getEffectiveCollateral(proposer);
            if (effectiveCollateral >= MINIMUM_COLLATERAL) {
                proposers[proposer].status = Status.PRECONFER;
            } else {
                proposers[proposer].status = Status.INCLUDER;
            }
            proposers[proposer].effectiveCollateral = effectiveCollateral;
        }
    }

    function applyPenalty(address proposer, bytes calldata penaltyConditions, bytes calldata penaltyConditionsSignature, bytes calldata data) external {
        // This function needs to be implemented
        // It should verify the signature, execute the penalty conditions,
        // and apply the resulting penalty
    }

    function initiateExit(uint256 amount) external {
        Registrant storage registrant = registrants[msg.sender];
        require(registrant.enteredAt != 0, "Not registered");
        require(registrant.balance >= amount, "Insufficient balance");
        registrant.exitInitiatedAt = block.number;
        emit ExitInitiated(msg.sender, amount);
    }

    function withdraw() external {
        Registrant storage registrant = registrants[msg.sender];
        require(registrant.exitInitiatedAt != 0, "Exit not initiated");
        require(block.number >= registrant.exitInitiatedAt + EXIT_COOLDOWN, "Cooldown period not over");
        uint256 amount = registrant.balance - registrant.frozenBalance;
        registrant.balance = registrant.frozenBalance;
        registrant.exitInitiatedAt = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getProposerStatus(address proposer) external view returns (Status) {
        return proposers[proposer].status;
    }

    function getEffectiveCollateral(address proposer) public view returns (uint256) {
        uint256 totalCollateral = 0;
        for (uint i = 0; i < registrants[proposer].delegatedProposers.length; i++) {
            address registrant = registrants[proposer].delegatedProposers[i];
            if (registrants[registrant].enteredAt <= block.number) {
                totalCollateral += registrants[registrant].balance - registrants[registrant].frozenBalance;
            }
        }
        return totalCollateral;
    }

    function getRegistrantInfo(address registrant) external view returns (Registrant memory) {
        return registrants[registrant];
    }

    function getProposerInfo(address proposer) external view returns (Proposer memory) {
        return proposers[proposer];
    }
}