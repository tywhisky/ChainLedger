// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {ERC20FreelanceEscrow} from "../contracts/ERC20FreelanceEscrow.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function slash(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

contract NoReturnToken {
    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount))
        public allowance;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 approved = allowance[from][msg.sender];
        require(approved >= amount);
        allowance[from][msg.sender] = approved - amount;
        _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract FalseReturnToken is ERC20 {
    constructor() ERC20("False Return Token", "FALSE") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        return false;
    }
}

contract FeeOnTransferToken is ERC20 {
    uint256 private constant FEE_DIVISOR = 10;

    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        uint256 fee = amount / FEE_DIVISOR;
        super._update(from, to, amount - fee);
        super._update(from, address(0), fee);
    }
}

interface ITokenReceiver {
    function onTokenTransfer() external;
}

contract CallbackToken is ERC20 {
    address public callbackSource;

    constructor() ERC20("Callback Token", "CALL") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setCallbackSource(address account) external {
        callbackSource = account;
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._update(from, to, amount);

        if (from == callbackSource && to.code.length != 0) {
            try ITokenReceiver(to).onTokenTransfer() {} catch {}
        }
    }
}

contract ReentrantTokenSeller is ITokenReceiver {
    ERC20FreelanceEscrow private escrow;

    uint256 public callbackCount;
    bool public reentrySucceeded;

    function markDelivered(ERC20FreelanceEscrow escrow_) external {
        escrow_.markDelivered();
    }

    function withdraw(ERC20FreelanceEscrow escrow_) external {
        escrow = escrow_;
        escrow_.withdraw();
    }

    function onTokenTransfer() external {
        callbackCount++;
        (reentrySucceeded, ) = address(escrow).call(
            abi.encodeWithSelector(ERC20FreelanceEscrow.withdraw.selector)
        );
    }
}

contract ERC20FreelanceEscrowTest is Test {
    uint256 private constant DEPOSIT = 1_000 ether;
    uint256 private constant EXTRA = 25 ether;
    address private constant SELLER = address(0xBEEF);
    address private constant ARBITER = address(0xCAFE);
    address private constant OUTSIDER = address(0xDEAD);

    function test_FundsAndCompletesWithStandardToken() public {
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _deploy(IERC20(address(token)), SELLER);
        token.mint(address(this), DEPOSIT);

        token.approve(address(escrow), DEPOSIT);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit ERC20FreelanceEscrow.EscrowFunded(address(this), DEPOSIT);
        escrow.fund();

        assertEq(
            uint256(escrow.state()),
            uint256(ERC20FreelanceEscrow.State.Funded)
        );
        assertEq(token.balanceOf(address(escrow)), DEPOSIT);

        vm.prank(SELLER);
        escrow.markDelivered();
        escrow.approveDelivery();
        assertEq(escrow.pendingWithdrawals(SELLER), DEPOSIT);

        vm.prank(SELLER);
        escrow.withdraw();
        assertEq(token.balanceOf(SELLER), DEPOSIT);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.pendingWithdrawals(SELLER), 0);
    }

    function test_SupportsTokenThatReturnsNoValue() public {
        NoReturnToken token = new NoReturnToken();
        ERC20FreelanceEscrow escrow = _deploy(
            IERC20(address(token)),
            SELLER
        );
        token.mint(address(this), DEPOSIT);
        token.approve(address(escrow), DEPOSIT);

        escrow.fund();
        vm.prank(SELLER);
        escrow.markDelivered();
        escrow.approveDelivery();
        vm.prank(SELLER);
        escrow.withdraw();

        assertEq(token.balanceOf(SELLER), DEPOSIT);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_RejectsTokenThatReturnsFalse() public {
        FalseReturnToken token = new FalseReturnToken();
        ERC20FreelanceEscrow escrow = _deploy(
            IERC20(address(token)),
            SELLER
        );
        token.mint(address(this), DEPOSIT);
        token.approve(address(escrow), DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20.SafeERC20FailedOperation.selector,
                address(token)
            )
        );
        escrow.fund();

        assertEq(
            uint256(escrow.state()),
            uint256(ERC20FreelanceEscrow.State.AwaitingFunding)
        );
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_RejectsFeeOnTransferTokenWithoutLosingFunds() public {
        FeeOnTransferToken token = new FeeOnTransferToken();
        ERC20FreelanceEscrow escrow = _deploy(
            IERC20(address(token)),
            SELLER
        );
        token.mint(address(this), DEPOSIT);
        token.approve(address(escrow), DEPOSIT);
        uint256 received = DEPOSIT - DEPOSIT / 10;

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20FreelanceEscrow.UnsupportedTokenTransfer.selector,
                DEPOSIT,
                received
            )
        );
        escrow.fund();

        assertEq(token.balanceOf(address(this)), DEPOSIT);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(token.allowance(address(this), address(escrow)), DEPOSIT);
    }

    function test_RejectsInsufficientBalance() public {
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _deploy(IERC20(address(token)), SELLER);
        token.approve(address(escrow), DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                0,
                DEPOSIT
            )
        );
        escrow.fund();
    }

    function test_RejectsInsufficientAllowance() public {
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _deploy(IERC20(address(token)), SELLER);
        token.mint(address(this), DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(escrow),
                0,
                DEPOSIT
            )
        );
        escrow.fund();
    }

    function test_DonatedTokensDoNotChangeOrderAccounting() public {
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _deploy(IERC20(address(token)), SELLER);
        token.mint(address(this), DEPOSIT + EXTRA);
        token.transfer(address(escrow), EXTRA);
        token.approve(address(escrow), DEPOSIT);

        escrow.fund();
        vm.prank(SELLER);
        escrow.cancelBySeller();
        escrow.withdraw();

        assertEq(token.balanceOf(address(this)), DEPOSIT);
        assertEq(token.balanceOf(address(escrow)), EXTRA);
        assertEq(escrow.depositAmount(), DEPOSIT);
    }

    function test_UndercollateralizedWithdrawalKeepsCredit() public {
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _fund(token, SELLER);
        vm.prank(SELLER);
        escrow.markDelivered();
        escrow.approveDelivery();
        token.slash(address(escrow), 1);

        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20FreelanceEscrow.InsufficientEscrowBalance.selector,
                DEPOSIT,
                DEPOSIT - 1
            )
        );
        escrow.withdraw();

        assertEq(escrow.pendingWithdrawals(SELLER), DEPOSIT);
        assertEq(token.balanceOf(address(escrow)), DEPOSIT - 1);
    }

    function test_ReentrantTokenCallbackCannotWithdrawTwice() public {
        CallbackToken token = new CallbackToken();
        ReentrantTokenSeller seller = new ReentrantTokenSeller();
        ERC20FreelanceEscrow escrow = _deploy(
            IERC20(address(token)),
            address(seller)
        );
        token.mint(address(this), DEPOSIT);
        token.approve(address(escrow), DEPOSIT);
        escrow.fund();
        token.setCallbackSource(address(escrow));

        seller.markDelivered(escrow);
        escrow.approveDelivery();
        seller.withdraw(escrow);

        assertEq(token.balanceOf(address(seller)), DEPOSIT);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertEq(escrow.pendingWithdrawals(address(seller)), 0);
        assertEq(seller.callbackCount(), 1);
        assertFalse(seller.reentrySucceeded());
    }

    function test_PreservesRoleAndStateChecks() public {
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _fund(token, SELLER);

        vm.prank(OUTSIDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20FreelanceEscrow.Unauthorized.selector,
                OUTSIDER
            )
        );
        escrow.markDelivered();

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20FreelanceEscrow.InvalidState.selector,
                ERC20FreelanceEscrow.State.Funded,
                ERC20FreelanceEscrow.State.Delivered
            )
        );
        escrow.approveDelivery();
    }

    function testFuzz_EverySettlementPathPreservesAccounting(
        uint8 rawPath
    ) public {
        uint8 path = rawPath % 7;
        TestToken token = new TestToken();
        ERC20FreelanceEscrow escrow = _fund(token, SELLER);

        if (path == 0) {
            vm.prank(SELLER);
            escrow.cancelBySeller();
        } else if (path == 1) {
            vm.warp(escrow.deliveryDeadline());
            escrow.refundAfterDeliveryTimeout();
        } else {
            vm.prank(SELLER);
            escrow.markDelivered();

            if (path == 2) {
                escrow.approveDelivery();
            } else if (path == 3) {
                vm.warp(escrow.reviewDeadline());
                escrow.claimAfterReviewTimeout();
            } else {
                escrow.openDispute();

                if (path == 4 || path == 5) {
                    vm.prank(ARBITER);
                    escrow.resolveDispute(path == 4);
                } else {
                    vm.warp(escrow.arbitrationDeadline());
                    escrow.refundAfterArbitrationTimeout();
                }
            }
        }

        ERC20FreelanceEscrow.State terminalState = escrow.state();
        uint256 buyerCredit = escrow.pendingWithdrawals(address(this));
        uint256 sellerCredit = escrow.pendingWithdrawals(SELLER);

        assertEq(buyerCredit + sellerCredit, DEPOSIT);
        assertEq(escrow.pendingWithdrawals(ARBITER), 0);
        assertEq(token.balanceOf(ARBITER), 0);
        assertEq(token.balanceOf(address(escrow)), DEPOSIT);

        vm.prank(SELLER);
        (bool success, ) = address(escrow).call(
            abi.encodeWithSelector(ERC20FreelanceEscrow.markDelivered.selector)
        );
        assertFalse(success);
        assertEq(uint256(escrow.state()), uint256(terminalState));
        assertEq(
            escrow.pendingWithdrawals(address(this)) +
                escrow.pendingWithdrawals(SELLER),
            DEPOSIT
        );
    }

    function _fund(
        TestToken token,
        address seller
    ) private returns (ERC20FreelanceEscrow escrow) {
        escrow = _deploy(IERC20(address(token)), seller);
        token.mint(address(this), DEPOSIT);
        token.approve(address(escrow), DEPOSIT);
        escrow.fund();
    }

    function _deploy(
        IERC20 token,
        address seller
    ) private returns (ERC20FreelanceEscrow escrow) {
        escrow = new ERC20FreelanceEscrow(
            address(token),
            seller,
            ARBITER,
            DEPOSIT,
            block.timestamp + 7 days,
            3 days,
            5 days
        );
    }
}
