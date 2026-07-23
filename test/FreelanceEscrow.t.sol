// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {FreelanceEscrow} from "../contracts/FreelanceEscrow.sol";

contract ReentrantSeller {
    FreelanceEscrow private escrow;

    uint256 public receiveCalls;
    bool public reentrySucceeded;

    function markDelivered(FreelanceEscrow escrow_) external {
        escrow_.markDelivered();
    }

    function withdraw(FreelanceEscrow escrow_) external {
        escrow = escrow_;
        escrow_.withdraw();
    }

    receive() external payable {
        receiveCalls++;
        (reentrySucceeded, ) = address(escrow).call(
            abi.encodeWithSelector(FreelanceEscrow.withdraw.selector)
        );
    }
}

contract RejectingSeller {
    function markDelivered(FreelanceEscrow escrow) external {
        escrow.markDelivered();
    }

    function withdraw(FreelanceEscrow escrow) external {
        escrow.withdraw();
    }

    receive() external payable {
        revert();
    }
}

contract ForceSend {
    constructor() payable {}

    function force(address payable target) external {
        selfdestruct(target);
    }
}

contract FreelanceEscrowSecurityTest is Test {
    uint256 private constant DEPOSIT = 1 ether;
    address private constant SELLER = address(0xBEEF);
    address private constant ARBITER = address(0xCAFE);

    function setUp() public {
        vm.deal(address(this), 100 ether);
        vm.deal(SELLER, 0);
        vm.deal(ARBITER, 0);
    }

    function test_ReentrantSellerCannotWithdrawTwice() public {
        ReentrantSeller attacker = new ReentrantSeller();
        FreelanceEscrow escrow = _deploy(address(attacker));

        attacker.markDelivered(escrow);
        escrow.approveDelivery();
        attacker.withdraw(escrow);

        assertEq(address(attacker).balance, DEPOSIT);
        assertEq(address(escrow).balance, 0);
        assertEq(escrow.pendingWithdrawals(address(attacker)), 0);
        assertEq(attacker.receiveCalls(), 1);
        assertFalse(attacker.reentrySucceeded());
    }

    function test_RejectingSellerKeepsCreditAfterFailedWithdrawal() public {
        RejectingSeller rejectingSeller = new RejectingSeller();
        FreelanceEscrow escrow = _deploy(address(rejectingSeller));

        rejectingSeller.markDelivered(escrow);
        escrow.approveDelivery();

        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.TransferFailed.selector,
                address(rejectingSeller),
                DEPOSIT
            )
        );
        rejectingSeller.withdraw(escrow);

        assertEq(
            escrow.pendingWithdrawals(address(rejectingSeller)),
            DEPOSIT
        );
        assertEq(address(escrow).balance, DEPOSIT);
        assertEq(address(rejectingSeller).balance, 0);
    }

    function test_ForcedEtherDoesNotChangeOrderAccounting() public {
        FreelanceEscrow escrow = _deploy(SELLER);
        uint256 forcedAmount = 0.25 ether;
        ForceSend forceSend = new ForceSend{value: forcedAmount}();

        forceSend.force(payable(address(escrow)));

        assertEq(escrow.depositAmount(), DEPOSIT);
        assertEq(address(escrow).balance, DEPOSIT + forcedAmount);

        vm.prank(SELLER);
        escrow.markDelivered();
        escrow.approveDelivery();
        vm.prank(SELLER);
        escrow.withdraw();

        assertEq(SELLER.balance, DEPOSIT);
        assertEq(address(escrow).balance, forcedAmount);
        assertEq(escrow.depositAmount(), DEPOSIT);
    }

    function testFuzz_PermissionMatrix(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller != address(this));
        vm.assume(caller != SELLER);
        vm.assume(caller != ARBITER);

        FreelanceEscrow funded = _deploy(SELLER);
        _assertUnauthorized(
            funded,
            caller,
            abi.encodeWithSelector(FreelanceEscrow.markDelivered.selector)
        );
        _assertUnauthorized(
            funded,
            caller,
            abi.encodeWithSelector(FreelanceEscrow.cancelBySeller.selector)
        );

        FreelanceEscrow delivered = _deploy(SELLER);
        vm.prank(SELLER);
        delivered.markDelivered();
        _assertUnauthorized(
            delivered,
            caller,
            abi.encodeWithSelector(FreelanceEscrow.approveDelivery.selector)
        );
        _assertUnauthorized(
            delivered,
            caller,
            abi.encodeWithSelector(FreelanceEscrow.openDispute.selector)
        );

        FreelanceEscrow disputed = _deploy(SELLER);
        vm.prank(SELLER);
        disputed.markDelivered();
        disputed.openDispute();
        _assertUnauthorized(
            disputed,
            caller,
            abi.encodeWithSelector(
                FreelanceEscrow.resolveDispute.selector,
                true
            )
        );
    }

    function test_InvalidStateTransitionMatrix() public {
        for (uint8 rawState = 0; rawState <= 5; rawState++) {
            FreelanceEscrow.State current = FreelanceEscrow.State(rawState);
            FreelanceEscrow escrow = _escrowInState(current);
            _assertInvalidTransitions(escrow, current);
        }
    }

    function _deploy(
        address seller
    ) private returns (FreelanceEscrow escrow) {
        escrow = new FreelanceEscrow{value: DEPOSIT}(
            seller,
            ARBITER,
            block.timestamp + 7 days,
            3 days,
            5 days
        );
    }

    function _escrowInState(
        FreelanceEscrow.State target
    ) private returns (FreelanceEscrow escrow) {
        escrow = _deploy(SELLER);

        if (target == FreelanceEscrow.State.Funded) return escrow;
        if (target == FreelanceEscrow.State.Cancelled) {
            vm.prank(SELLER);
            escrow.cancelBySeller();
            return escrow;
        }
        if (target == FreelanceEscrow.State.Refunded) {
            vm.warp(escrow.deliveryDeadline());
            escrow.refundAfterDeliveryTimeout();
            return escrow;
        }

        vm.prank(SELLER);
        escrow.markDelivered();
        if (target == FreelanceEscrow.State.Delivered) return escrow;
        if (target == FreelanceEscrow.State.Completed) {
            escrow.approveDelivery();
            return escrow;
        }

        escrow.openDispute();
    }

    function _assertUnauthorized(
        FreelanceEscrow escrow,
        address caller,
        bytes memory callData
    ) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = address(escrow).call(callData);

        assertFalse(success);
        assertEq(
            returnData,
            abi.encodeWithSelector(
                FreelanceEscrow.Unauthorized.selector,
                caller
            )
        );
    }

    function _assertInvalidTransitions(
        FreelanceEscrow escrow,
        FreelanceEscrow.State current
    ) private {
        if (current != FreelanceEscrow.State.Funded) {
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Funded,
                SELLER,
                abi.encodeWithSelector(FreelanceEscrow.markDelivered.selector)
            );
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Funded,
                SELLER,
                abi.encodeWithSelector(FreelanceEscrow.cancelBySeller.selector)
            );
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Funded,
                address(this),
                abi.encodeWithSelector(
                    FreelanceEscrow.refundAfterDeliveryTimeout.selector
                )
            );
        }

        if (current != FreelanceEscrow.State.Delivered) {
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Delivered,
                address(this),
                abi.encodeWithSelector(
                    FreelanceEscrow.approveDelivery.selector
                )
            );
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Delivered,
                address(this),
                abi.encodeWithSelector(FreelanceEscrow.openDispute.selector)
            );
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Delivered,
                address(this),
                abi.encodeWithSelector(
                    FreelanceEscrow.claimAfterReviewTimeout.selector
                )
            );
        }

        if (current != FreelanceEscrow.State.Disputed) {
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Disputed,
                ARBITER,
                abi.encodeWithSelector(
                    FreelanceEscrow.resolveDispute.selector,
                    true
                )
            );
            _assertInvalidState(
                escrow,
                current,
                FreelanceEscrow.State.Disputed,
                address(this),
                abi.encodeWithSelector(
                    FreelanceEscrow.refundAfterArbitrationTimeout.selector
                )
            );
        }
    }

    function _assertInvalidState(
        FreelanceEscrow escrow,
        FreelanceEscrow.State current,
        FreelanceEscrow.State expected,
        address caller,
        bytes memory callData
    ) private {
        if (caller != address(this)) vm.prank(caller);
        (bool success, bytes memory returnData) = address(escrow).call(callData);

        assertFalse(success);
        assertEq(
            returnData,
            abi.encodeWithSelector(
                FreelanceEscrow.InvalidState.selector,
                current,
                expected
            )
        );
    }
}

contract EscrowHandler is Test {
    FreelanceEscrow public immutable escrow;
    address public immutable seller;
    address public immutable arbiter;

    bool public terminalSeen;
    bool public terminalChanged;
    FreelanceEscrow.State public firstTerminalState;

    constructor(address seller_, address arbiter_) payable {
        seller = seller_;
        arbiter = arbiter_;
        escrow = new FreelanceEscrow{value: msg.value}(
            seller_,
            arbiter_,
            block.timestamp + 7 days,
            3 days,
            5 days
        );
    }

    receive() external payable {}

    function markDelivered() external {
        _call(
            seller,
            abi.encodeWithSelector(FreelanceEscrow.markDelivered.selector)
        );
    }

    function cancelBySeller() external {
        _call(
            seller,
            abi.encodeWithSelector(FreelanceEscrow.cancelBySeller.selector)
        );
    }

    function approveDelivery() external {
        _call(
            address(this),
            abi.encodeWithSelector(FreelanceEscrow.approveDelivery.selector)
        );
    }

    function openDispute() external {
        _call(
            address(this),
            abi.encodeWithSelector(FreelanceEscrow.openDispute.selector)
        );
    }

    function resolveDispute(bool releaseToSeller) external {
        _call(
            arbiter,
            abi.encodeWithSelector(
                FreelanceEscrow.resolveDispute.selector,
                releaseToSeller
            )
        );
    }

    function refundAfterDeliveryTimeout() external {
        _call(
            address(this),
            abi.encodeWithSelector(
                FreelanceEscrow.refundAfterDeliveryTimeout.selector
            )
        );
    }

    function claimAfterReviewTimeout() external {
        _call(
            address(this),
            abi.encodeWithSelector(
                FreelanceEscrow.claimAfterReviewTimeout.selector
            )
        );
    }

    function refundAfterArbitrationTimeout() external {
        _call(
            address(this),
            abi.encodeWithSelector(
                FreelanceEscrow.refundAfterArbitrationTimeout.selector
            )
        );
    }

    function withdrawBuyer() external {
        _call(
            address(this),
            abi.encodeWithSelector(FreelanceEscrow.withdraw.selector)
        );
    }

    function withdrawSeller() external {
        _call(
            seller,
            abi.encodeWithSelector(FreelanceEscrow.withdraw.selector)
        );
    }

    function advanceTime(uint32 secondsForward) external {
        vm.warp(block.timestamp + uint256(secondsForward % 30 days));
        _recordState();
    }

    function _call(address caller, bytes memory callData) private {
        if (caller != address(this)) vm.prank(caller);
        (bool success, ) = address(escrow).call(callData);
        if (success) _recordState();
    }

    function _recordState() private {
        FreelanceEscrow.State current = escrow.state();
        bool terminal = uint8(current) >=
            uint8(FreelanceEscrow.State.Completed);

        if (!terminalSeen && terminal) {
            terminalSeen = true;
            firstTerminalState = current;
        } else if (terminalSeen && current != firstTerminalState) {
            terminalChanged = true;
        }
    }
}

contract FreelanceEscrowInvariantTest is StdInvariant, Test {
    uint256 private constant DEPOSIT = 1 ether;
    address private constant SELLER = address(0xBEEF);
    address private constant ARBITER = address(0xCAFE);

    EscrowHandler private handler;

    function setUp() public {
        vm.deal(address(this), 10 ether);
        vm.deal(SELLER, 0);
        vm.deal(ARBITER, 0);

        handler = new EscrowHandler{value: DEPOSIT}(SELLER, ARBITER);
        targetContract(address(handler));
    }

    function invariant_AllocationNeverExceedsDeposit() public view {
        FreelanceEscrow escrow = handler.escrow();
        uint256 allocated = escrow.pendingWithdrawals(address(handler)) +
            escrow.pendingWithdrawals(SELLER) +
            address(handler).balance +
            SELLER.balance;

        assertLe(allocated, DEPOSIT);
        if (
            uint8(escrow.state()) >=
            uint8(FreelanceEscrow.State.Completed)
        ) {
            assertEq(allocated, DEPOSIT);
        }
    }

    function invariant_TerminalOutcomeNeverChanges() public view {
        assertFalse(handler.terminalChanged());
    }

    function invariant_ArbiterNeverReceivesOrderFunds() public view {
        FreelanceEscrow escrow = handler.escrow();

        assertEq(escrow.pendingWithdrawals(ARBITER), 0);
        assertEq(ARBITER.balance, 0);
    }
}
