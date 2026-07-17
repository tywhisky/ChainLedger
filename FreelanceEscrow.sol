// SPDX-License-Identifier: MIT
// compiler version must be greater than or equal to 0.8.26 and less than 0.9.0
pragma solidity ^0.8.26;

enum State {
    Funded,
    Delivered,
    Disputed,
    Completed,
    Refunded,
    Cancelled
}

contract FreelanceEscrow {
    address public immutable buyer;
    address public immutable seller; 
    address public immutable arbiter;

    uint256 public immutable deliveryDeadline;
    uint256 public immutable reviewPeriod;
    uint256 public immutable arbitrationPeriod;

    uint256 public immutable depositAmount;

    State public state = State.Funded;

    constructor(address _seller, 
                address _arbiter, 
                uint256 _deliveryDeadline, 
                uint256 _reviewPeriod, 
                uint256 _arbitrationPeriod) payable {
        require(_seller != address(0), "Not valid address of seller.");
        require(_arbiter != address(0), "Not valid address of arbiter.");
        require(msg.sender != _seller && _seller != _arbiter && _arbiter != msg.sender);
        require(_deliveryDeadline > block.timestamp);
        require(_reviewPeriod != 0);
        require(_arbitrationPeriod != 0);
        require(msg.value > 0);

        buyer = msg.sender;
        seller = _seller;
        arbiter = _arbiter; 
        deliveryDeadline = _deliveryDeadline;
        reviewPeriod = _reviewPeriod;
        arbitrationPeriod = _arbitrationPeriod;
        depositAmount = msg.value;
    }
}