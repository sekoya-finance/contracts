// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IAggregatorInterface} from "../interfaces/IAggregator.sol";

contract PriceAggregator is IAggregatorInterface {
    uint256 public decimals;
    int256 public latestAnswer;

    constructor(uint256 _decimals) {
        decimals = _decimals;
    }

    function setLatestAnswer(int256 answer) public {
        latestAnswer = answer;
    }
}
