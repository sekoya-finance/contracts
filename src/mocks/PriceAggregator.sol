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

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, latestAnswer, block.timestamp, block.timestamp, 0);
    }
}
