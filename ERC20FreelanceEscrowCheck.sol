// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./ERC20FreelanceEscrow.sol";
import "./LearningERC20.sol";

contract ERC20FreelanceEscrowCheck {
    function checkFunding() external returns (bool) {
        LearningERC20 checkToken = new LearningERC20("Check Token", "CHK", 100);
        ERC20FreelanceEscrow escrow = new ERC20FreelanceEscrow(
            address(checkToken),
            address(1),
            address(2),
            100,
            1 days,
            1 days,
            1 days
        );

        checkToken.approve(address(escrow), 100);
        escrow.fund();

        assert(
            escrow.state() == ERC20FreelanceEscrow.State.Funded &&
                checkToken.balanceOf(address(escrow)) == 100 &&
                checkToken.balanceOf(address(this)) == 0 &&
                checkToken.allowance(address(this), address(escrow)) == 0 &&
                checkToken.totalSupply() == 100 &&
                escrow.deliveryDeadline() > block.timestamp
        );
        return true;
    }
}
