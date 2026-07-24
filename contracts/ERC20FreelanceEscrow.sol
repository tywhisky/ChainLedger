// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ERC-20 Freelance Escrow
/// @notice A single-order escrow funded with one fixed ERC-20 amount.
/// @dev Only fixed-balance tokens are supported. Fee-on-transfer tokens are
/// rejected while funding. Rebasing tokens are unsupported because balances
/// can change after funding; an under-collateralized withdrawal reverts
/// without consuming the recipient's credit.
contract ERC20FreelanceEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum State {
        AwaitingFunding,
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
    uint256 public immutable deliveryDeadline;
    uint256 public immutable reviewPeriod;
    uint256 public immutable arbitrationPeriod;

    uint256 public deliveredAt;
    uint256 public reviewDeadline;
    uint256 public disputedAt;
    uint256 public arbitrationDeadline;

    mapping(address account => uint256 amount) public pendingWithdrawals;

    State public state;

    event EscrowCreated(
        address indexed buyer,
        address indexed seller,
        address indexed arbiter,
        address token,
        uint256 amount,
        uint256 deliveryDeadline
    );
    event EscrowFunded(address indexed buyer, uint256 amount);
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
    event EscrowCancelled(
        address indexed seller,
        address indexed buyer,
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
    event EscrowRefunded(address indexed buyer, uint256 amount);
    event ReviewTimeoutClaimed(address indexed seller, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor(
        address tokenAddress,
        address sellerAddress,
        address arbiterAddress,
        uint256 depositAmountValue,
        uint256 deliveryDeadlineTimestamp,
        uint256 reviewPeriodSeconds,
        uint256 arbitrationPeriodSeconds
    ) {
        if (tokenAddress == address(0)) revert InvalidAddress(tokenAddress);
        if (sellerAddress == address(0)) revert InvalidAddress(sellerAddress);
        if (arbiterAddress == address(0)) revert InvalidAddress(arbiterAddress);
        if (depositAmountValue == 0) revert ZeroDeposit();
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

        token = IERC20(tokenAddress);
        buyer = msg.sender;
        seller = sellerAddress;
        arbiter = arbiterAddress;
        depositAmount = depositAmountValue;
        deliveryDeadline = deliveryDeadlineTimestamp;
        reviewPeriod = reviewPeriodSeconds;
        arbitrationPeriod = arbitrationPeriodSeconds;

        emit EscrowCreated(
            buyer,
            seller,
            arbiter,
            tokenAddress,
            depositAmountValue,
            deliveryDeadlineTimestamp
        );
    }

    /// @notice Pulls the approved deposit from the Buyer.
    /// @dev Reverts unless the escrow receives exactly `depositAmount`.
    function fund()
        external
        onlyBuyer
        inState(State.AwaitingFunding)
        nonReentrant
    {
        if (block.timestamp >= deliveryDeadline) {
            revert DeadlinePassed(block.timestamp, deliveryDeadline);
        }

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(buyer, address(this), depositAmount);
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 receivedAmount = balanceAfter >= balanceBefore
            ? balanceAfter - balanceBefore
            : 0;
        if (receivedAmount != depositAmount) {
            revert UnsupportedTokenTransfer(depositAmount, receivedAmount);
        }

        state = State.Funded;
        emit EscrowFunded(buyer, receivedAmount);
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

    function cancelBySeller() external onlySeller inState(State.Funded) {
        if (block.timestamp >= deliveryDeadline) {
            revert DeadlinePassed(block.timestamp, deliveryDeadline);
        }

        state = State.Cancelled;
        pendingWithdrawals[buyer] += depositAmount;

        emit EscrowCancelled(seller, buyer, depositAmount);
    }

    function approveDelivery() external onlyBuyer inState(State.Delivered) {
        if (block.timestamp >= reviewDeadline) {
            revert DeadlinePassed(block.timestamp, reviewDeadline);
        }

        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;

        emit DeliveryApproved(buyer, seller, depositAmount);
    }

    function openDispute() external onlyBuyer inState(State.Delivered) {
        if (block.timestamp >= reviewDeadline) {
            revert DeadlinePassed(block.timestamp, reviewDeadline);
        }

        disputedAt = block.timestamp;
        arbitrationDeadline = disputedAt + arbitrationPeriod;
        state = State.Disputed;

        emit DisputeOpened(buyer, disputedAt, arbitrationDeadline);
    }

    function resolveDispute(
        bool releaseToSeller
    ) external onlyArbiter inState(State.Disputed) {
        if (block.timestamp >= arbitrationDeadline) {
            revert DeadlinePassed(block.timestamp, arbitrationDeadline);
        }

        address recipient = releaseToSeller ? seller : buyer;
        state = releaseToSeller ? State.Completed : State.Refunded;
        pendingWithdrawals[recipient] += depositAmount;

        emit DisputeResolved(
            arbiter,
            recipient,
            depositAmount,
            releaseToSeller
        );
    }

    function refundAfterDeliveryTimeout() external inState(State.Funded) {
        if (block.timestamp < deliveryDeadline) {
            revert DeadlineNotReached(block.timestamp, deliveryDeadline);
        }

        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;

        emit EscrowRefunded(buyer, depositAmount);
    }

    function claimAfterReviewTimeout() external inState(State.Delivered) {
        if (block.timestamp < reviewDeadline) {
            revert DeadlineNotReached(block.timestamp, reviewDeadline);
        }

        state = State.Completed;
        pendingWithdrawals[seller] += depositAmount;

        emit ReviewTimeoutClaimed(seller, depositAmount);
    }

    function refundAfterArbitrationTimeout() external inState(State.Disputed) {
        if (block.timestamp < arbitrationDeadline) {
            revert DeadlineNotReached(block.timestamp, arbitrationDeadline);
        }

        state = State.Refunded;
        pendingWithdrawals[buyer] += depositAmount;

        emit EscrowRefunded(buyer, depositAmount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw(msg.sender);

        uint256 available = token.balanceOf(address(this));
        if (available < amount) {
            revert InsufficientEscrowBalance(amount, available);
        }

        pendingWithdrawals[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);

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

    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert Unauthorized(msg.sender);
        _;
    }

    modifier inState(State expectedState) {
        if (state != expectedState) revert InvalidState(state, expectedState);
        _;
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
    error DeadlineNotReached(uint256 currentTime, uint256 deadline);
    error NothingToWithdraw(address account);
    error UnsupportedTokenTransfer(uint256 expected, uint256 received);
    error InsufficientEscrowBalance(uint256 required, uint256 available);
}
