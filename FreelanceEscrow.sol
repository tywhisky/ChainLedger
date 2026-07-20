// SPDX-License-Identifier: MIT
// compiler version must be greater than or equal to 0.8.27 and less than 0.9.0
pragma solidity ^0.8.27;

enum State {
    Funded,
    Delivered,
    Disputed,
    Completed,
    Refunded,
    Cancelled
}

event EscrowCreated(
    address indexed buyer,
    address indexed seller,
    address indexed arbiter,
    uint256 amount,
    uint256 deliveryDeadline
);

event DeliveryMarked(
    address indexed seller,
    uint256 deliveryAt,
    uint256 reviewDeadline
);

event DeliveryApproved(
    address indexed buyer,
    address indexed seller,
    uint256 amount
);

event ReviewTimeoutClaimed(
    address indexed seller,
    uint256 amount
);

event DisputeOpened(
    address indexed buyer,
    uint256 disputedAt,
    uint256 arbitrationDeadline
);

event DisputeResolved(
    address indexed arbiter,
    address indexed recipient,
    uint256 amount,
    bool releasedToSeller
);

event EscrowCancelled(
    address indexed seller,
    address indexed buyer,
    uint256 amount
);

event EscrowRefunded(
    address indexed buyer,
    uint256 amount
);

event Withdrawal(
    address indexed account,
    uint256 amount
);

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
        require(_seller != address(0), InvalidSellerAddress());
        require(_arbiter != address(0), InvalidArbiterAddress());
        require(
            msg.sender != _seller && _seller != _arbiter && _arbiter != msg.sender,
            RolesMustBeDistinct(msg.sender, _seller, _arbiter)
        );
        require(
            _deliveryDeadline > block.timestamp,
            DeadlinePassed(block.timestamp, _deliveryDeadline)
        );
        require(_reviewPeriod != 0, InvalidReviewPeriod());
        require(_arbitrationPeriod != 0, InvalidArbitrationPeriod());
        require(msg.value > 0, ZeroAmount());

        buyer = msg.sender;
        seller = _seller;
        arbiter = _arbiter; 
        deliveryDeadline = _deliveryDeadline;
        reviewPeriod = _reviewPeriod;
        arbitrationPeriod = _arbitrationPeriod;
        depositAmount = msg.value;

        emit EscrowCreated(buyer, seller, arbiter, depositAmount, deliveryDeadline);
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }

    fallback() external payable {
        revert DirectPaymentNotAllowed();
    }

    function cancelBySeller() external onlySeller inState(State.Funded) {
        state = State.Cancelled;
        pendingWithdrawals[buyer] += depositAmount;
        emit EscrowCancelled(seller, buyer, depositAmount);
    }

    function markDelivered() external onlySeller inState(State.Funded) {
        require(
            block.timestamp < deliveryDeadline,
            DeadlinePassed(block.timestamp, deliveryDeadline)
        );
        deliveryAt = block.timestamp;
        reviewDeadline = deliveryAt + reviewPeriod;
        state = State.Delivered;

        emit DeliveryMarked(seller, deliveryAt, reviewDeadline);
    }

    function approveDelivery() external onlyBuyer inState(State.Delivered) {
        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;

        emit DeliveryApproved(buyer, seller, depositAmount);
    }

    function openDispute() external onlyBuyer inState(State.Delivered) {
        require(
            block.timestamp < reviewDeadline,
            DeadlinePassed(block.timestamp, reviewDeadline)
        );
        disputedAt = block.timestamp;
        arbitrationDeadline = disputedAt + arbitrationPeriod;
        state = State.Disputed;
        emit DisputeOpened(buyer, disputedAt, arbitrationDeadline);
    }

    function resolveDispute(bool releaseToSeller) external onlyArbiter inState(State.Disputed) {
        require(
            block.timestamp < arbitrationDeadline,
            DeadlinePassed(block.timestamp, arbitrationDeadline)
        );
        if (releaseToSeller) {
            state = State.Completed;
            pendingWithdrawals[seller] += depositAmount;
            emit DisputeResolved(arbiter, seller, depositAmount, releaseToSeller);
        } else {
            state = State.Refunded; 
            pendingWithdrawals[buyer] += depositAmount;
            emit DisputeResolved(arbiter, buyer, depositAmount, releaseToSeller);
            emit EscrowRefunded(buyer, depositAmount);
        }
    }

    function refundAfterDeliveryTimeout() external onlyBuyer inState(State.Funded) {
        require(
            block.timestamp >= deliveryDeadline,
            DeadlineNotReached(block.timestamp, deliveryDeadline)
        );
        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;
        emit EscrowRefunded(buyer, depositAmount);
    }

    function claimAfterReviewTimeout() external onlySeller inState(State.Delivered) {
        require(
            block.timestamp >= reviewDeadline,
            DeadlineNotReached(block.timestamp, reviewDeadline)
        );
        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;
        emit ReviewTimeoutClaimed(seller, depositAmount);
    }

    function refundAfterArbitrationTimeout() external inState(State.Disputed) {
        require(
            block.timestamp >= arbitrationDeadline,
            DeadlineNotReached(block.timestamp, arbitrationDeadline)
        );
        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;
        emit EscrowRefunded(buyer, depositAmount);
    }

    function withdraw() external sellerOrBuyer nonReentrant{
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, NothingToWithdraw(msg.sender));
        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call {value: amount}("");
        if (!success) revert TransferFailed(msg.sender, amount);
        emit Withdrawal(msg.sender, amount);
    }

    modifier onlyBuyer() {
        require(msg.sender == buyer, Unauthorized(msg.sender));
        _;
    }

    modifier onlySeller() {
        require(msg.sender == seller, Unauthorized(msg.sender));
        _;
    }

    modifier sellerOrBuyer() {
        require(
            msg.sender == buyer || msg.sender == seller,
            Unauthorized(msg.sender)
        );
        _;
    }

    modifier inState(State expectedState) {
        require(state == expectedState, InvalidState(state, expectedState));
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, Unauthorized(msg.sender));
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
    error TransferFailed(address recipient, uint256 amount);
    error InvalidSellerAddress();
    error InvalidArbiterAddress();
    error RolesMustBeDistinct(address buyer, address seller, address arbiter);
    error DeadlinePassed(uint256 currentTime, uint256 deadline);
    error DeadlineNotReached(uint256 currentTime, uint256 deadline);
    error InvalidReviewPeriod();
    error InvalidArbitrationPeriod();
    error ZeroAmount();
    error NothingToWithdraw(address account);
    error Unauthorized(address caller);
    error InvalidState(State current, State expected);
    error DirectPaymentNotAllowed();
}
