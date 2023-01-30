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
            address(this),
            address(dai),
            address(weth),
            address(daiOracle),
            address(wethOracle),
            epochDuration,
            0,
            amount
        );
    }

    function testDeployDAItoWETHVault() public {
        Vault dca = deployDaiToWethVault(1 days, 10 * 1e18);

        assertEq(dca.owner(), address(this));
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

    function testExecuteDca() public {
        uint256 amount = 10 * 1e18;
        Vault dca = deployDaiToWethVault(1 days, amount);
        dai.transfer((address(dca)), amount);
        vm.warp(block.timestamp + 1 days); //Add 1 day time so we can execute the dca

        //determine price & send weth to worker to emulate a swap with just executing a transfer back to the vault
        uint256 daiTokenPrice = uint256(daiOracle.latestAnswer());
        uint256 wethTokenPrice = uint256(wethOracle.latestAnswer());
        uint256 ratio = (daiTokenPrice * 1e24) / wethTokenPrice;
        uint256 wethAmount = (ratio * amount) / 1e24;
        weth.transfer(address(dca), wethAmount);

        //save balances
        uint256 oldOwnerBalance = weth.balanceOf(address(this));
        uint256 oldExecutorBalance = weth.balanceOf(address(1111)); //use a new address as executor so we can check the 0.5% fees

        //prank & execute
        vm.prank(address(1111));
        dca.executeDCA(
            address(worker), abi.encode(address(weth), abi.encodeCall(weth.transfer, (address(this), wethAmount)))
        );

        //assert
        assertEq(weth.balanceOf(address(this)), oldOwnerBalance + (wethAmount * 995 / 1000));
        assertEq(weth.balanceOf(address(1111)), oldExecutorBalance + (wethAmount * 5 / 1000));
    }
}
