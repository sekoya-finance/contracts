// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {Factory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {Worker} from "../src/Worker.sol";
import {Token} from "../src/mocks/Token.sol";
import {PriceAggregator, IAggregatorInterface} from "../src/mocks/PriceAggregator.sol";

contract VaultTest is Test {
    Factory factory;
    Vault vault;
    Worker worker;
    Token dai;
    Token weth;
    PriceAggregator daiOracle;
    PriceAggregator wethOracle;

    function setUp() public {
        //deploy contracts
        vault = new Vault();
        factory = new Factory(vault);
        worker = new Worker();
        dai = new Token("DAI", "DAI", 18, 1000 * 1e18);
        weth = new Token("WETH", "WETH", 18, 1000* 1e18);

        //set Oracles
        daiOracle = new PriceAggregator(8);
        daiOracle.setLatestAnswer(1 * 1e8);
        wethOracle = new PriceAggregator(8);
        wethOracle.setLatestAnswer(500 * 1e8);
    }

    function deployDaiToWethVault(uint64 epochDuration, uint256 amount) public returns (Vault dca) {
        return factory.createDCA(
            msg.sender, address(dai), address(weth), address(daiOracle), address(wethOracle), epochDuration, 0, amount
        );
    }

    function testDeployDAItoWETHVault() public {
        Vault dca = deployDaiToWethVault(1 days, 10 * 1e18);

        assertEq(dca.owner(), msg.sender);
        assertEq(address(dca.sellToken()), address(dai));
        assertEq(address(dca.buyToken()), address(weth));
        (
            IAggregatorInterface sellTokenOracle,
            IAggregatorInterface buyTokenOracle,
            uint64 epochDuration,
            uint8 decimalsDiff,
            uint256 amount
        ) = dca.dcaData();
        assertEq(address(sellTokenOracle), address(daiOracle));
        assertEq(address(buyTokenOracle), address(wethOracle));
        assertEq(epochDuration, 1 days);
        assertEq(decimalsDiff, 0);
        assertEq(amount, 10 * 1e18);
    }
}
