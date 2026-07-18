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
    uint256 public deliveryAt;
    uint256 public reviewDeadline;
    uint256 public disputedAt;
    uint256 public arbitrationDeadline;
    uint256 public immutable reviewPeriod;
    uint256 public immutable arbitrationPeriod;

    mapping(address => uint256) public pendingWithdrawals;

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

    function cancelBySeller() external onlySeller inState(State.Funded) {
        state = State.Cancelled;
        pendingWithdrawals[buyer] += depositAmount;
    }

    function markDelivered() external onlySeller inState(State.Funded) {
        require(block.timestamp < deliveryDeadline, "Escrow expired");
        deliveryAt = block.timestamp;
        reviewDeadline = deliveryAt + reviewPeriod;
        state = State.Delivered;
    }

    function approveDelivery() external onlyBuyer inState(State.Delivered) {
        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;
    }

    function openDispute() external onlyBuyer inState(State.Delivered) {
        require(block.timestamp < reviewDeadline);
        disputedAt = block.timestamp;
        arbitrationDeadline = disputedAt + arbitrationPeriod;
        state = State.Disputed;
    }

    function resolveDispute(bool releaseToSeller) external onlyArbiter inState(State.Disputed) {
        require(block.timestamp < arbitrationDeadline, "Expired for disputing");
        if (releaseToSeller) {
            state = State.Completed;
            pendingWithdrawals[seller] += depositAmount;
        } else {
            state = State.Refunded; 
            pendingWithdrawals[buyer] += depositAmount;
        }
    }

    function refundAfterDeliveryTimeout() external onlyBuyer inState(State.Funded) {
        require(block.timestamp >= deliveryDeadline, "Expired for delivering");
        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;
    }

    function claimAfterReviewTimeout() external onlySeller inState(State.Delivered) {
        require(block.timestamp >= reviewDeadline, "Expired for reviewing");
        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;
    }

    function refundAfterArbitrationTimeout() external inState(State.Disputed) {
        require(block.timestamp >= arbitrationDeadline, "Expired for arbitration");
        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;
    }

    function withdraw() external sellerOrBuyer nonReentrant{
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0);
        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call {value: amount}("");
        if (!success) revert TransferFailed();
    }

    modifier onlyBuyer() {
        require(msg.sender == buyer, "Not buyer");
        _;
    }

    modifier onlySeller() {
        require(msg.sender == seller, "Not seller");
        _;
    }

    modifier sellerOrBuyer() {
        require(msg.sender == buyer || msg.sender == seller, "Neither seller or buyer");
        _;
    }

    modifier inState(State _state) {
        require(state == _state, "The invalid state for current contract");
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Not arbiter");
        _;
    }

    bool private _entered;
    modifier nonReentrant() {
        if (_entered) revert Reentrancy();

        _entered = true;
        _;
        _entered = false;
    }

    error Reentrancy();
    error TransferFailed();
}
