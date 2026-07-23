// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FreelanceEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum State {
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

    uint256 public immutable amount;
    uint256 public immutable deliveryPeriod;
    uint256 public immutable reviewPeriod;
    uint256 public immutable arbitrationPeriod;

    uint256 public deliveryDeadline;
    uint256 public deliveryAt;
    uint256 public reviewDeadline;
    uint256 public reviewAt;
    uint256 public arbitrationDeadline;
    uint256 public arbitrationAt;

    mapping(address => uint256) public pendingWithdrawals;

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
        address _token,
        address _seller,
        address _arbiter,
        uint256 _amount,
        uint256 _deliveryPeriod,
        uint256 _reviewPeriod,
        uint256 _arbitrationPeriod
    ) {
        require(
            _token != address(0) && _token.code.length > 0,
            InvalidToken(_token)
        );
        require(_seller != address(0), InvalidSellerAddress());
        require(_arbiter != address(0), InvalidArbiterAddress());
        require(
            msg.sender != seller && seller != arbiter && arbiter != msg.sender,
            RolesMustBeDistinct(msg.sender, seller, arbiter)
        );
        require(_amount > 0, ZeroAmount());
        require(_deliveryPeriod > 0, InvalidDeliveryPeriod());
        require(_reviewPeriod > 0, InvalidReviewPeriod());
        require(_arbitrationPeriod > 0, InvalidArbitrationPeriod());

        token = IERC20(_token);
        buyer = msg.sender;
        seller = _seller;
        arbiter = _arbiter;
        amount = _amount;
        deliveryPeriod = _deliveryPeriod;
        reviewPeriod = _reviewPeriod;
        arbitrationPeriod = _arbitrationPeriod;

        emit EscrowCreated(_token, msg.sender, _seller, _arbiter, _amount);
    }

    receive() external payable {
        revert DirectPaymentNotAllowed();
    }

    fallback() external payable {
        revert DirectPaymentNotAllowed();
    }

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
    error IncorrectAmountReceived(uint256 expected, uint256 received);
    error DirectPaymentNotAllowed();
}
