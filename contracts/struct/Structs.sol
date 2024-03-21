// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract Structs {
    struct Escrows {
        uint id;
        address assignor;
        address assignee;
        uint amount;
        string details;
        string title;
        ContractStatus status;
        bool token;
        address tokenAddress;
    }

    struct Dispute {
        uint escrowId;
        address assignor;
        address assignee;
        uint amountDisputedAssignee;
        uint amountDisputedAssignor;
        string assignorDetails;
        string assigneeDetails;
        uint validatorId;
        disputeLevel disputeLevel;
        string[] assignorProfs;
        string[] assigneeProfs;
        bool assigneeCreatedDispute;
        bool validationStarted;
    }

    struct Validators {
        uint disputeId;
        address[] validator;
        uint votesForAssignor;
        uint votesForAssignee;
        bool assignorWon;
        bool assigneeWon;
        bool draw;
        bool nextChance;
        uint validationCreateTime;
    }

    enum ContractStatus {
        created,
        accepted,
        completed,
        approved,
        cancelled,
        disputed,
        disputedlevel2,
        closed
    }
    enum disputeLevel {
        level1,
        level2
    }
    
}
