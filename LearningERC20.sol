// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LearningERC20 is ERC20 {
    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply
    ) ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, initialSupply);
    }
}
