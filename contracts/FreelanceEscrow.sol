// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FreelanceEscrow is ReentrancyGuard {
    enum State {
        Funded,
        Delivered,
        Disputed,
        Completed,
        Refunded,
        Cancelled
    }

    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;

    uint256 public immutable depositAmount;
    uint256 public immutable deliveryDeadline;
    uint256 public immutable reviewPeriod;
    uint256 public immutable arbitrationPeriod;

    uint256 public deliveredAt;
    uint256 public reviewDeadline;

    mapping(address account => uint256 amount) public pendingWithdrawals;

    State public state = State.Funded;

    event EscrowCreated(
        address indexed buyer,
        address indexed seller,
        address indexed arbiter,
        uint256 amount,
        uint256 deliveryDeadline
    );

    event DeliveryMarked(
        address indexed seller,
        uint256 deliveredAt,
        uint256 reviewDeadline
    );
    event DeliveryApproved(
        address indexed buyer,
        address indexed seller,
        uint256 amount
    );
    event Withdrawal(address indexed account, uint256 amount);

    constructor(
        address sellerAddress,
        address arbiterAddress,
        uint256 deliveryDeadlineTimestamp,
        uint256 reviewPeriodSeconds,
        uint256 arbitrationPeriodSeconds
    ) payable {
        if (msg.value == 0) revert ZeroDeposit();
        if (sellerAddress == address(0)) {
            revert InvalidAddress(sellerAddress);
        }
        if (arbiterAddress == address(0)) {
            revert InvalidAddress(arbiterAddress);
        }
        if (
            msg.sender == sellerAddress ||
            msg.sender == arbiterAddress ||
            sellerAddress == arbiterAddress
        ) {
            revert RolesMustBeDistinct(
                msg.sender,
                sellerAddress,
                arbiterAddress
            );
        }
        if (deliveryDeadlineTimestamp <= block.timestamp) {
            revert InvalidDeliveryDeadline(
                block.timestamp,
                deliveryDeadlineTimestamp
            );
        }
        if (reviewPeriodSeconds == 0) revert InvalidReviewPeriod();
        if (arbitrationPeriodSeconds == 0) {
            revert InvalidArbitrationPeriod();
        }

        buyer = msg.sender;
        seller = sellerAddress;
        arbiter = arbiterAddress;
        depositAmount = msg.value;
        deliveryDeadline = deliveryDeadlineTimestamp;
        reviewPeriod = reviewPeriodSeconds;
        arbitrationPeriod = arbitrationPeriodSeconds;

        emit EscrowCreated(
            buyer,
            seller,
            arbiter,
            depositAmount,
            deliveryDeadline
        );
    }

    function markDelivered() external onlySeller inState(State.Funded) {
        if (block.timestamp >= deliveryDeadline) {
            revert DeadlinePassed(block.timestamp, deliveryDeadline);
        }

        deliveredAt = block.timestamp;
        reviewDeadline = deliveredAt + reviewPeriod;
        state = State.Delivered;

        emit DeliveryMarked(seller, deliveredAt, reviewDeadline);
    }

    function approveDelivery() external onlyBuyer inState(State.Delivered) {
        if (block.timestamp >= reviewDeadline) {
            revert DeadlinePassed(block.timestamp, reviewDeadline);
        }

        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;

        emit DeliveryApproved(buyer, seller, depositAmount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw(msg.sender);

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);
    }

    modifier onlyBuyer() {
        if (msg.sender != buyer) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlySeller() {
        if (msg.sender != seller) revert Unauthorized(msg.sender);
        _;
    }

    modifier inState(State expectedState) {
        if (state != expectedState) revert InvalidState(state, expectedState);
        _;
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }

    fallback() external payable {
        revert DirectPaymentNotAllowed();
    }

    error ZeroDeposit();
    error InvalidAddress(address account);
    error RolesMustBeDistinct(
        address buyer,
        address seller,
        address arbiter
    );
    error InvalidDeliveryDeadline(uint256 currentTime, uint256 deadline);
    error InvalidReviewPeriod();
    error InvalidArbitrationPeriod();
    error Unauthorized(address caller);
    error InvalidState(State current, State expected);
    error DeadlinePassed(uint256 currentTime, uint256 deadline);
    error NothingToWithdraw(address account);
    error TransferFailed(address recipient, uint256 amount);
    error DirectPaymentNotAllowed();
}
