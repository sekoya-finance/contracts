// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 amount)
        ERC20(_name, _symbol, _decimals)
    {
        _mint(msg.sender, amount);
    }
}
