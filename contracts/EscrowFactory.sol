// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FreelanceEscrow} from "./FreelanceEscrow.sol";

/// @title Freelance Escrow Factory
/// @notice Creates one independently funded ETH escrow per order.
/// @dev Orders are discovered from events; the Factory intentionally stores
/// no growing on-chain order list.
contract EscrowFactory {
    event EscrowCreated(
        address indexed escrow,
        address indexed buyer,
        address indexed seller,
        address arbiter,
        uint256 amount,
        uint256 deliveryDeadline,
        uint256 reviewPeriod,
        uint256 arbitrationPeriod
    );

    function createEscrow(
        address seller,
        address arbiter,
        uint256 deliveryDeadline,
        uint256 reviewPeriod,
        uint256 arbitrationPeriod
    ) external payable returns (address escrowAddress) {
        FreelanceEscrow escrow = new FreelanceEscrow{value: msg.value}(
            msg.sender,
            seller,
            arbiter,
            deliveryDeadline,
            reviewPeriod,
            arbitrationPeriod
        );
        escrowAddress = address(escrow);

        emit EscrowCreated(
            escrowAddress,
            msg.sender,
            seller,
            arbiter,
            msg.value,
            deliveryDeadline,
            reviewPeriod,
            arbitrationPeriod
        );
    }
}
