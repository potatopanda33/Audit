// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./event/Events.sol";
import "./struct/Structs.sol";

contract Cscrow is
Initializable,
Events,
Structs,
OwnableUpgradeable,
UUPSUpgradeable,
ReentrancyGuardUpgradeable
{
    uint public totalEscrows;
    uint public totalDisputes;
    uint public totalValidators;
    uint public commissionPercent;
    uint public validatorsPercent;

    IUniswapV2Router02 private uniswapRouter;
    address public usdtAddress;
    address public uniswapAddress;
    address public rewardPool;

    mapping(address => uint256) public companyProfits;
    mapping(uint => Escrows) public escrows;
    mapping(uint => Dispute) public disputes;
    mapping(uint => Validators) public validators;
    mapping(address => uint) public points;
    mapping(address => bool) public enabledTokens;
    mapping(address => uint256[]) public myContracts;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _routerAddress, address _usdtAddress) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        uniswapRouter = IUniswapV2Router02(_routerAddress);
        uniswapAddress = _routerAddress;
            usdtAddress = _usdtAddress;

        commissionPercent = 2;
        validatorsPercent = 10;
    }

    function contractExist(uint _id) private view {
        require(_id <= totalEscrows, "CNE");
    }

    function onlyAssignee(uint _id) private view {
        require(escrows[_id].assignee == msg.sender, "not authorized Assignee");
    }

    function onlyAssigner(uint _id) private view {
        require(escrows[_id].assignor == msg.sender, "not authorized Assigner");
    }

    function bothParties(uint _disputeId) private view {
        require(
            disputes[_disputeId].assignee == msg.sender ||
            disputes[_disputeId].assignor == msg.sender,
            "Not authorized"
        );
    }

    function checkStatus(uint _id, ContractStatus _status) private view {
        require(escrows[_id].status == _status, "Not accepted");
    }

    function createContract(
        address _assignee,
        uint _amount,
        string memory _details,
        string memory _title,
        bool _token,
        address _tokenAddress
    ) public payable nonReentrant {
        require(_assignee != address(0), "Invalid address");
        require(_amount > 0, "Amount < 0");
        ContractStatus status = ContractStatus.created;
        if (_token) {
            require(isTokenEnabled(_tokenAddress), "Token not enabled");
            IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);

            require(
                token.allowance(msg.sender, address(this)) >= _amount,
                "low allowance"
            );
            require(token.balanceOf(msg.sender) >= _amount, "low balance");
            token.transferFrom(msg.sender, address(this), _amount);
        } else {
            require(msg.value >= _amount, "low funds");
        }

        Escrows memory tmpEscrow = Escrows(
            totalEscrows,
            msg.sender,
            _assignee,
            _amount,
            _details,
            _title,
            status,
            _token,
            _tokenAddress
        );
        escrows[totalEscrows] = tmpEscrow;
        myContracts[msg.sender].push(totalEscrows);
        myContracts[_assignee].push(totalEscrows);
        totalEscrows += 1;
        emit ContractCreated(totalEscrows, msg.sender, _assignee);
    }

    function withdrawContract(uint _id) public {
        onlyAssigner(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.created);
        escrows[_id].status = ContractStatus.closed;
        sendFundsAfterValidation(
            _id,
            escrows[_id].amount,
            escrows[_id].assignor
        );
    }

    function acceptContract(uint _id) public {
        onlyAssignee(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.created);
        escrows[_id].status = ContractStatus.accepted;
        emit ContractAccepted(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee
        );
    }

    function notAcceptContract(uint _id) public {
        onlyAssignee(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.created);
        escrows[_id].status = ContractStatus.cancelled;
        sendFundsAfterValidation(
            _id,
            escrows[_id].amount,
            escrows[_id].assignor
        );
        emit ContractCancelled(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee
        );
    }

    function completeContract(uint _id) public {
        onlyAssignee(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.accepted);
        escrows[_id].status = ContractStatus.completed;
        emit ContractCompleted(
            _id,
            escrows[_id].assignor,
            escrows[_id].assignee
        );
    }

    function approveContract(uint _id) public {
        onlyAssigner(_id);
        contractExist(_id);
        checkStatus(_id, ContractStatus.completed);

        Escrows storage escrow = escrows[_id];
        uint amount = escrow.amount;
        uint commission = (amount * commissionPercent) / 100;
        uint assigneeAmount = amount - commission;
        // Transfer commission to the appropriate account
        address profitsAccount = escrow.token ? escrow.tokenAddress : address(0);
        companyProfits[profitsAccount] += commission;

        if (escrow.token) {
            convertTokenToUsdt(profitsAccount, companyProfits[profitsAccount]);
            companyProfits[escrows[_id].tokenAddress] = 0;
        } else {
//            convertEthToUsdt(companyProfits[profitsAccount]);
//            companyProfits[profitsAccount] = 0;
        }
        sendFundsAfterValidation(_id, assigneeAmount, escrows[_id].assignee);
        escrows[_id].status = ContractStatus.approved;
        emit ContractEnded(_id, escrows[_id].assignor, escrows[_id].assignee);
    }

    function createDisputeLevel1(
        uint _id,
        uint _amount,
        string memory _details
    ) external {
        require(
            escrows[_id].assignee == msg.sender ||
            escrows[_id].assignor == msg.sender,
            "Not authorized"
        );
        contractExist(_id);
        require(
            escrows[_id].status == ContractStatus.accepted ||
            escrows[_id].status == ContractStatus.completed,
            "Not accepted"
        );
        escrows[_id].status = ContractStatus.disputed;
        string[] memory assigneeProfs;
        string[] memory assignorProfs;
        Dispute memory dispute;
        if (msg.sender == escrows[_id].assignee) {
            dispute = Dispute(
                _id,
                escrows[_id].assignor,
                escrows[_id].assignee,
                _amount,
                0,
                "",
                _details,
                totalValidators,
                disputeLevel.level1,
                assignorProfs,
                assigneeProfs,
                true,
                false
            );
        } else {
            dispute = Dispute(
                _id,
                escrows[_id].assignor,
                escrows[_id].assignee,
                0,
                _amount,
                _details,
                "",
                totalValidators,
                disputeLevel.level1,
                assignorProfs,
                assigneeProfs,
                false,
                false
            );
        }

        disputes[totalDisputes] = dispute;
        totalDisputes += 1;
    }

    function acceptDispute(uint _disputeId) public {
        Dispute storage dispute = disputes[_disputeId];
        Escrows storage escrow = escrows[dispute.escrowId];
        require(dispute.disputeLevel == disputeLevel.level1, "Dispute not created");
        bothParties(_disputeId);
        contractExist(dispute.escrowId);
        checkStatus(dispute.escrowId, ContractStatus.disputed);
        // Determine the party that initiated the dispute
        address acceptor = dispute.assigneeCreatedDispute ? dispute.assignor : dispute.assignee;
        require(msg.sender == acceptor, "Not authorized");
        uint256 amount = escrow.amount;
        uint256 commission = (amount * commissionPercent) / 100;
        uint256 remaining = amount - commission;
        uint256 secondPartyAmount = 0;

        if (msg.sender == dispute.assignee) {
            secondPartyAmount = remaining - dispute.amountDisputedAssignee;
            sendFundsAfterValidation(dispute.escrowId, dispute.amountDisputedAssignee, msg.sender);
        } else if (msg.sender == dispute.assignor) {
            secondPartyAmount = remaining - dispute.amountDisputedAssignor;
            sendFundsAfterValidation(dispute.escrowId, dispute.amountDisputedAssignor, msg.sender);
        }

        // Send remaining funds to the other party if applicable
        if (secondPartyAmount > 0) {
            address secondPartyAddress = dispute.assigneeCreatedDispute ? escrow.assignor : escrow.assignee;
            sendFundsAfterValidation(dispute.escrowId, secondPartyAmount, secondPartyAddress);
        }

        // Transfer commission to the appropriate account
        address profitsAccount = escrow.token ? escrow.tokenAddress : address(0);
        companyProfits[profitsAccount] += commission;

        // Reset company profits for the token or ETH
        if (escrow.token) {
            convertTokenToUsdt(profitsAccount, companyProfits[profitsAccount]);
            companyProfits[escrow.tokenAddress] = 0;
        } else {
//            convertEthToUsdt(companyProfits[profitsAccount]);
//            companyProfits[profitsAccount] = 0;
        }

        escrow.status = ContractStatus.closed;

    emit ContractCancelled(dispute.escrowId, escrow.assignor, escrow.assignee);
    }

    function createDisputeLevel2(
        uint256 _disputeId,
        uint256 _amount,
        string memory _details,
        string[] memory _profs
    ) external {
        require(_disputeId <= totalDisputes, "Dispute does not exist");
        Dispute storage dispute = disputes[_disputeId];

        require(dispute.disputeLevel == disputeLevel.level1, "Level 1 dispute not created");

        // Ensure that the sender is authorized to create a level 2 dispute
        require(
            (dispute.assigneeCreatedDispute && msg.sender == dispute.assignor) ||
            (!dispute.assigneeCreatedDispute && msg.sender == dispute.assignee),
            "Not authorized"
        );

        bothParties(_disputeId);

        uint256 escrowId = dispute.escrowId;
        checkStatus(escrowId, ContractStatus.disputed);

        // Update dispute level to level 2
        dispute.disputeLevel = disputeLevel.level2;

        // Add level 2 dispute details
        addProfs(_disputeId, _amount, _details, _profs);
    }

    function addProofsForDisputeLevel2(
        uint256 _disputeId,
        uint256 _amount,
        string memory _details,
        string[] memory _profs
    ) external {
        require(_disputeId <= totalDisputes, "Dispute does not exist");
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.disputeLevel == disputeLevel.level2, "Level 2 dispute not created");
        bothParties(_disputeId);
        // Add level 2 dispute details
        addProfs(_disputeId, _amount, _details, _profs);
        uint256 escrowId = dispute.escrowId;
        checkStatus(escrowId, ContractStatus.disputed);
        // Initialize validators for the dispute
        Validators memory newValidator = Validators({
            disputeId: _disputeId,
            validator: new address[](0), // Initialize the dynamic array
            votesForAssignor: 0,
            votesForAssignee: 0,
            assignorWon: false,
            assigneeWon: false,
            draw: false,
            nextChance: false,
            validationCreateTime: block.timestamp
        });
        validators[totalValidators] = newValidator;
        totalValidators += 1;
        dispute.validationStarted = true;
//        address[] memory _validators;
//
//        Validators memory tmpValidate = Validators(
//            _disputeId,
//            _validators,
//            0,
//            0,
//            false,
//            false,
//            false,
//            false,
//            block.timestamp
//        );
    }
//    start from here.

    function getProofs(
        uint256 _diputeId
    ) external view returns (string[] memory, string[] memory) {
        return (
            disputes[_diputeId].assignorProfs,
            disputes[_diputeId].assigneeProfs
        );
    }

    function addProfs(
        uint256 _disputeId,
        uint256 _amount,
        string memory _details,
        string[] memory _profs
    ) internal {
        bothParties(_disputeId);
        if (msg.sender == disputes[_disputeId].assignee) {
            disputes[_disputeId].assigneeProfs = _profs;
            disputes[_disputeId].assigneeDetails = _details;
            disputes[_disputeId].amountDisputedAssignee = _amount;
        } else {
            disputes[_disputeId].assignorProfs = _profs;
            disputes[_disputeId].assignorDetails = _details;
            disputes[_disputeId].amountDisputedAssignor = _amount;
        }
    }

    function validate(uint _validateId, uint voteFor) public {
        require(_validateId <= totalValidators, "VNE");
        require(validators[_validateId].disputeId <= totalDisputes, "DNE");
        require(!alreadyVoted(_validateId), "Already voted");

        require(
            validators[_validateId].validationCreateTime + 24 hours >=
            block.timestamp,
            "Time expired"
        );
        if (voteFor == 0) {
            validators[_validateId].votesForAssignor += 1;
        } else if (voteFor == 1) {
            validators[_validateId].votesForAssignee += 1;
        }
        validators[_validateId].validator.push(msg.sender);
        points[msg.sender] += 1;
    }

    function resolveDispute(uint _disputeId) external onlyOwner {
        require(_disputeId <= totalDisputes, "DNE");
        uint validateId = disputes[_disputeId].validatorId;
        uint escrow = disputes[_disputeId].escrowId;
        uint amount = escrows[escrow].amount;
        uint disputeAmount;
        if (disputes[_disputeId].assigneeCreatedDispute) {
            disputeAmount = disputes[_disputeId].amountDisputedAssignee;
        } else {
            disputeAmount = disputes[_disputeId].amountDisputedAssignor;
        }

        uint commission = (amount * commissionPercent) / 100;
        uint validatorAmount = (amount * validatorsPercent) / 100;

        uint remaining = amount - (commission + validatorAmount);

        uint amountToOtherParty = remaining - disputeAmount;

        uint amountToParties = remaining / 2;

//        require(
//            validators[validateId].validationCreateTime + 24 hours <=
//            block.timestamp,
//            "Time remaining"
//        );

        if (
            validators[validateId].votesForAssignor ==
            validators[validateId].votesForAssignee
        ) {
            if (!validators[validateId].nextChance) {
                validators[validateId].validationCreateTime = block.timestamp;
                validators[validateId].nextChance = true;
            } else {
                if (escrows[escrow].token) {
                    companyProfits[escrows[escrow].tokenAddress] += commission;
                    convertTokenToUsdt(escrows[escrow].tokenAddress, companyProfits[escrows[escrow].tokenAddress]);
                    companyProfits[escrows[escrow].tokenAddress] = 0;
                } else {
                    companyProfits[address(0)] += commission;
//                    convertEthToUsdt(companyProfits[address(0)]);
//                    companyProfits[address(0)] = 0;
                }

                validators[validateId].draw = true;
                sendFundsAfterValidation(
                    escrow,
                    amountToParties,
                    disputes[_disputeId].assignor
                );
                sendFundsAfterValidation(
                    escrow,
                    amountToParties,
                    disputes[_disputeId].assignee
                );
                sentCommissionToValidators(
                    validators[validateId].validator,
                    validatorAmount,
                    escrows[escrow].token,
                    escrows[escrow].tokenAddress
                );
            }
        } else {
            if (
                validators[validateId].votesForAssignor >
                validators[validateId].votesForAssignee
            ) {
                validators[validateId].assignorWon = true;
                sendFundsAfterValidation(
                    escrow,
                    disputes[_disputeId].amountDisputedAssignor,
                    disputes[_disputeId].assignor
                );
                if (amountToOtherParty > 0) {
                    sendFundsAfterValidation(
                        escrow,
                        amountToOtherParty,
                        disputes[_disputeId].assignee
                    );
                }
            } else if (
                validators[validateId].votesForAssignor <
                validators[validateId].votesForAssignee
            ) {
                validators[validateId].assigneeWon = true;
                sendFundsAfterValidation(
                    escrow,
                    disputes[_disputeId].amountDisputedAssignee,
                    disputes[_disputeId].assignee
                );
                if (amountToOtherParty > 0) {
                    sendFundsAfterValidation(
                        escrow,
                        amountToOtherParty,
                        disputes[_disputeId].assignee
                    );
                }
            }
            if (escrows[escrow].token) {
                companyProfits[escrows[escrow].tokenAddress] += commission;
                convertTokenToUsdt(escrows[escrow].tokenAddress, companyProfits[escrows[escrow].tokenAddress]);
                companyProfits[escrows[escrow].tokenAddress] = 0;
            } else {
                companyProfits[address(0)] += commission;
//                convertEthToUsdt(companyProfits[address(0)]);
//                companyProfits[address(0)] = 0;
            }

            sentCommissionToValidators(
                validators[validateId].validator,
                validatorAmount,
                escrows[escrow].token,
                escrows[escrow].tokenAddress
            );
        }

        escrows[escrow].status = ContractStatus.closed;
    }

    function sendFundsAfterValidation(
        uint _id,
        uint _amount,
        address _to
    ) internal {
        if (escrows[_id].token) {
            transferToken(escrows[_id].tokenAddress, _to, _amount);
        } else {
            transferNative(_to, _amount);
        }
    }

    function sentCommissionToValidators(
        address[] memory _address,
        uint _amount,
        bool _token,
        address _tokenAddress
    ) internal {
        uint perValidatorAmount = _amount / 10;
        if (_token) {
            for (uint i = 0; i < _address.length; i++) {
                if (i == 10) {
                    break;
                }
                transferToken(_tokenAddress, _address[i], perValidatorAmount);
            }
        } else {
            for (uint i = 0; i < _address.length; i++) {
                if (i == 10) {
                    break;
                }
                transferNative(_address[i], perValidatorAmount);
            }
        }
    }

    function transferNative(
        address _address,
        uint _amount
    ) internal nonReentrant {
        require(_amount <= address(this).balance, "No Funds");
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Amount not sent");
    }

    function transferToken(
        address _tokenAddress,
        address _address,
        uint _amount
    ) internal {
        IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
        require(_amount <= token.balanceOf(address(this)), "No Funds");
//        token.transferFrom(address(this), _address, _amount);
        token.transfer(_address, _amount);
    }

    function alreadyVoted(uint _id) public view returns (bool) {
        for (uint i = 0; i < validators[_id].validator.length; i++) {
            if (validators[_id].validator[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    function getMyContracts(
        address _address
    ) external view returns (uint256[] memory) {
        return myContracts[_address];
    }

    function withdrawCompleteCommissionNative() public onlyOwner {
        uint profit = companyProfits[address(0)];
        transferNative(owner(), profit);
        companyProfits[address(0)] = 0;
    }

    function withdrawCompleteCommissionToken(address _token) public onlyOwner {
        uint profit = companyProfits[_token];
        transferToken(_token, owner(), profit);
        companyProfits[_token] = 0;
    }

    function convertEthToUsdt(uint256 amount) internal nonReentrant {
        // Swap ETH for USDT using Uniswap
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = usdtAddress;

        // Specify the deadline for the transaction
        uint256 deadline = block.timestamp + 600; // Replace with an appropriate deadline

        // Perform the swap
        uniswapRouter.swapExactETHForTokens{value: amount}(
            amount,
            path,
            rewardPool,
            deadline
        );
    }

    function convertTokenToUsdt(
        address tokenAddress,
        uint256 tokenAmount
    ) internal {
        require(tokenAddress != address(0), "Invalid token address");
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        if(tokenAddress == usdtAddress) {
            token.transfer(rewardPool, tokenAmount);
        } else {
            // Approve Uniswap to spend the token
            token.approve(address(uniswapRouter), tokenAmount);

            // Swap the token for USDT using Uniswap
            address[] memory path = new address[](2);
            path[0] = tokenAddress;
            path[1] = usdtAddress;

            // Specify the deadline for the transaction
            uint256 deadline = block.timestamp + 600; // Replace with an appropriate deadline

            // Perform the swap
            uniswapRouter.swapExactTokensForTokens(
                tokenAmount,
                0,
                path,
                rewardPool,
                deadline
            );
        }
    }

    function getPoints(address _address) public view returns (uint) {
        return points[_address];
    }

    function addEnableTokens(address[] memory _tokens) public onlyOwner {
        for (uint i = 0; i < _tokens.length; i++) {
            enabledTokens[_tokens[i]] = true;
        }
    }

    function isTokenEnabled(address _token) public view returns (bool) {
        return enabledTokens[_token];
    }

    function updateCommissionPercent(uint _commissionPercent) public onlyOwner {
        commissionPercent = _commissionPercent;
    }

    function updateRewardPool(address _rewardPool) public onlyOwner {
        rewardPool = _rewardPool;
    }

    function updateValidatorPercent(uint _validatorsPercent) public onlyOwner {
        validatorsPercent = _validatorsPercent;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}