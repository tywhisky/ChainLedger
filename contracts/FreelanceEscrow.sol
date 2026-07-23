// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract FreelanceEscrow {
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

    State public state = State.Funded;

    event EscrowCreated(
        address indexed buyer,
        address indexed seller,
        address indexed arbiter,
        uint256 amount,
        uint256 deliveryDeadline
    );

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
    error DirectPaymentNotAllowed();
}
