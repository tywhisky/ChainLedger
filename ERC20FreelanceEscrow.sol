// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract ERC20FreelanceEscrow {
    enum State {
        Unfunded,
        Funded,
        Delivered,
        Disputed,
        Completed,
        Refunded,
        Cancelled
    }

    IERC20 public immutable token;
    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;

    uint256 public immutable depositAmount;
    uint256 public immutable deliveryPeriod;
    uint256 public immutable reviewPeriod;
    uint256 public immutable arbitrationPeriod;

    uint256 public deliveryDeadline;
    uint256 public deliveryAt;
    uint256 public reviewDeadline;
    uint256 public disputedAt;
    uint256 public arbitrationDeadline;

    mapping(address => uint256) public pendingWithdrawals;

    State public state = State.Unfunded;

    event EscrowCreated(
        address indexed token,
        address indexed buyer,
        address indexed seller,
        address arbiter,
        uint256 amount
    );
    event EscrowFunded(
        address indexed buyer,
        address indexed token,
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
    event ReviewTimeoutClaimed(address indexed seller, uint256 amount);
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
    event EscrowRefunded(address indexed buyer, uint256 amount);
    event Withdrawal(
        address indexed account,
        address indexed token,
        uint256 amount
    );

    constructor(
        address tokenAddress,
        address sellerAddress,
        address arbiterAddress,
        uint256 amount,
        uint256 deliveryPeriodSeconds,
        uint256 reviewPeriodSeconds,
        uint256 arbitrationPeriodSeconds
    ) {
        require(
            tokenAddress != address(0) && tokenAddress.code.length > 0,
            InvalidToken(tokenAddress)
        );
        require(sellerAddress != address(0), InvalidSellerAddress());
        require(arbiterAddress != address(0), InvalidArbiterAddress());
        require(
            msg.sender != sellerAddress &&
                sellerAddress != arbiterAddress &&
                arbiterAddress != msg.sender,
            RolesMustBeDistinct(msg.sender, sellerAddress, arbiterAddress)
        );
        require(amount > 0, ZeroAmount());
        require(deliveryPeriodSeconds > 0, InvalidDeliveryPeriod());
        require(reviewPeriodSeconds > 0, InvalidReviewPeriod());
        require(arbitrationPeriodSeconds > 0, InvalidArbitrationPeriod());

        token = IERC20(tokenAddress);
        buyer = msg.sender;
        seller = sellerAddress;
        arbiter = arbiterAddress;
        depositAmount = amount;
        deliveryPeriod = deliveryPeriodSeconds;
        reviewPeriod = reviewPeriodSeconds;
        arbitrationPeriod = arbitrationPeriodSeconds;

        emit EscrowCreated(
            tokenAddress,
            buyer,
            seller,
            arbiter,
            depositAmount
        );
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }

    fallback() external payable {
        revert DirectPaymentNotAllowed();
    }

    function fund() external onlyBuyer inState(State.Unfunded) nonReentrant {
        uint256 balanceBefore = token.balanceOf(address(this));
        bool success = token.transferFrom(buyer, address(this), depositAmount);
        if (!success) {
            revert TokenTransferFailed(
                address(token),
                buyer,
                address(this),
                depositAmount
            );
        }

        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received != depositAmount) {
            revert IncorrectAmountReceived(depositAmount, received);
        }

        state = State.Funded;
        deliveryDeadline = block.timestamp + deliveryPeriod;

        emit EscrowFunded(
            buyer,
            address(token),
            depositAmount,
            deliveryDeadline
        );
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

    function resolveDispute(
        bool releaseToSeller
    ) external onlyArbiter inState(State.Disputed) {
        require(
            block.timestamp < arbitrationDeadline,
            DeadlinePassed(block.timestamp, arbitrationDeadline)
        );

        if (releaseToSeller) {
            state = State.Completed;
            pendingWithdrawals[seller] += depositAmount;
            emit DisputeResolved(arbiter, seller, depositAmount, true);
        } else {
            state = State.Refunded;
            pendingWithdrawals[buyer] += depositAmount;
            emit DisputeResolved(arbiter, buyer, depositAmount, false);
            emit EscrowRefunded(buyer, depositAmount);
        }
    }

    function refundAfterDeliveryTimeout()
        external
        onlyBuyer
        inState(State.Funded)
    {
        require(
            block.timestamp >= deliveryDeadline,
            DeadlineNotReached(block.timestamp, deliveryDeadline)
        );
        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;
        emit EscrowRefunded(buyer, depositAmount);
    }

    function claimAfterReviewTimeout()
        external
        onlySeller
        inState(State.Delivered)
    {
        require(
            block.timestamp >= reviewDeadline,
            DeadlineNotReached(block.timestamp, reviewDeadline)
        );
        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;
        emit ReviewTimeoutClaimed(seller, depositAmount);
    }

    function refundAfterArbitrationTimeout()
        external
        inState(State.Disputed)
    {
        require(
            block.timestamp >= arbitrationDeadline,
            DeadlineNotReached(block.timestamp, arbitrationDeadline)
        );
        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;
        emit EscrowRefunded(buyer, depositAmount);
    }

    function withdraw() external sellerOrBuyer nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, NothingToWithdraw(msg.sender));

        pendingWithdrawals[msg.sender] = 0;
        bool success = token.transfer(msg.sender, amount);
        if (!success) {
            revert TokenTransferFailed(
                address(token),
                address(this),
                msg.sender,
                amount
            );
        }

        emit Withdrawal(msg.sender, address(token), amount);
    }

    modifier onlyBuyer() {
        require(msg.sender == buyer, Unauthorized(msg.sender));
        _;
    }

    modifier onlySeller() {
        require(msg.sender == seller, Unauthorized(msg.sender));
        _;
    }

    modifier onlyArbiter() {
        require(msg.sender == arbiter, Unauthorized(msg.sender));
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

    bool private _entered;

    modifier nonReentrant() {
        if (_entered) revert Reentrancy();
        _entered = true;
        _;
        _entered = false;
    }

    error Reentrancy();
    error InvalidToken(address token);
    error InvalidSellerAddress();
    error InvalidArbiterAddress();
    error RolesMustBeDistinct(address buyer, address seller, address arbiter);
    error InvalidDeliveryPeriod();
    error InvalidReviewPeriod();
    error InvalidArbitrationPeriod();
    error ZeroAmount();
    error Unauthorized(address caller);
    error InvalidState(State current, State expected);
    error DeadlinePassed(uint256 currentTime, uint256 deadline);
    error DeadlineNotReached(uint256 currentTime, uint256 deadline);
    error NothingToWithdraw(address account);
    error TokenTransferFailed(
        address token,
        address from,
        address to,
        uint256 amount
    );
    error IncorrectAmountReceived(uint256 expected, uint256 received);
    error DirectPaymentNotAllowed();
}
