// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test, stdError} from "forge-std/Test.sol";
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
    uint16 feeRatio = 995;

    function setUp() public {
        //set timestamp to 01/01/2023
        vm.warp(1672527600);
        //deploy contracts
        vault = new Vault();
        factory = new Factory(vault, feeRatio);
        worker = new Worker();
        dai = new Token("DAI", "DAI", 18, 1000 * 1e18);
        weth = new Token("WETH", "WETH", 18, 1000* 1e18);

        //set Oracles
        daiOracle = new PriceAggregator(8);
        daiOracle.setLatestAnswer(1 * 1e8);
        wethOracle = new PriceAggregator(8);
        wethOracle.setLatestAnswer(500 * 1e8);

        //Give a bunch of WETH to worker to execute orders
        weth.transfer(address(worker), 500 * 1e18);
    }

    ///@notice Function to easily deploy a dai to weth vault
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

    ///@notice Function to easily execute a dca
    function executeDaiToWethDca(Vault dca, uint256 amount, address executor) public returns (uint256 wethAmount) {
        //determine price & send weth to worker to emulate a swap with just executing a transfer back to the vault
        uint256 daiTokenPrice = uint256(daiOracle.latestAnswer());
        uint256 wethTokenPrice = uint256(wethOracle.latestAnswer());
        uint256 ratio = (daiTokenPrice * 1e24) / wethTokenPrice;
        wethAmount = (ratio * amount) / 1e24;

        vm.prank(executor);
        dca.executeDCA(
            address(worker),
            abi.encodeCall(
                worker.executeJob, abi.encode(address(weth), abi.encodeCall(weth.transfer, (address(dca), wethAmount)))
            )
        );
    }

    function testDeployDAItoWETHVault() public {
        //setup
        uint64 time = 1 days;
        uint256 amount = 10 * 1e18;

        //exec
        Vault dca = deployDaiToWethVault(time, amount);

        //assert
        assertEq(dca.owner(), address(this));
        assertEq(address(dca.sellToken()), address(dai));
        assertEq(address(dca.buyToken()), address(weth));
        (
            IAggregatorInterface sellTokenOracle,
            IAggregatorInterface buyTokenOracle,
            uint64 epochDuration,
            uint8 decimalsDiff,
            uint16 _feeRatio,
            uint256 _amount
        ) = dca.dcaData();
        assertEq(address(sellTokenOracle), address(daiOracle));
        assertEq(address(buyTokenOracle), address(wethOracle));
        assertEq(epochDuration, time);
        assertEq(decimalsDiff, 0);
        assertEq(_feeRatio, feeRatio);
        assertEq(_amount, amount);
    }

    function testExecuteDca() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount * 2); //send enough dai to execute 2 orders
        //execute dca once as lastBuy is 0
        executeDaiToWethDca(dca, amount, address(1111));

        vm.warp(block.timestamp + time); //Add 1 day time so we can execute the dca

        //save balances
        uint256 oldOwnerBalance = weth.balanceOf(address(this));
        uint256 oldExecutorBalance = weth.balanceOf(address(1111));

        //exec
        uint256 wethAmount = executeDaiToWethDca(dca, amount, address(1111));

        //assert
        assertEq(weth.balanceOf(address(this)), oldOwnerBalance + (wethAmount * feeRatio / 1000));
        assertEq(weth.balanceOf(address(1111)), oldExecutorBalance + (wethAmount * (1000 - feeRatio) / 1000));
    }

    function testExecuteDca_fail_tooClose() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount * 2); //send enough dai to execute 2 orders
        //execute dca once as lastBuy is 0
        uint256 wethAmount = executeDaiToWethDca(dca, amount, address(1111));

        //exec & assert
        vm.prank(address(1111));
        vm.expectRevert(Vault.TooClose.selector); //assert that it will revert with TooClose error
        dca.executeDCA(
            address(worker),
            abi.encodeCall(
                worker.executeJob, abi.encode(address(weth), abi.encodeCall(weth.transfer, (address(dca), wethAmount)))
            )
        );
    }

    function testExecuteDca_fail_notEnoughTokenReturned() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount * 2); //send enough dai to execute 2 orders
        //execute dca once as lastBuy is 0
        executeDaiToWethDca(dca, amount, address(1111));

        vm.warp(block.timestamp + time); //Add 1 day time so we can execute the dca

        //exec & assert
        vm.prank(address(1111));
        vm.expectRevert(stdError.arithmeticError); //assert that it will revert with arithmeticError
        dca.executeDCA(
            address(worker),
            abi.encodeCall(
                worker.executeJob, abi.encode(address(weth), abi.encodeCall(weth.transfer, (address(dca), 0)))
            )
        );
    }

    function testWithdraw() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount);

        uint256 oldVaultBalance = dai.balanceOf(address(dca));
        uint256 oldOwnerBalance = dai.balanceOf(address(this));

        //exec
        dca.withdraw(amount);

        //assert
        assertEq(dai.balanceOf(address(dca)), oldVaultBalance - amount);
        assertEq(dai.balanceOf(address(this)), oldOwnerBalance + amount);
    }

    function testWithdraw_fail_ownerOnly() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount);

        //exec & assert
        vm.prank(address(8888));
        vm.expectRevert(Vault.OwnerOnly.selector);
        dca.withdraw(amount);
    }

    function testTurnOff() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount);

        uint256 oldVaultBalance = dai.balanceOf(address(dca));
        uint256 oldOwnerBalance = dai.balanceOf(address(this));

        //exec
        dca.turnOff();

        //assert
        assertEq(dai.balanceOf(address(dca)), 0);
        assertEq(dai.balanceOf(address(this)), oldOwnerBalance + oldVaultBalance);
    }

    function testTurnOff_fail_ownerOnly() public {
        //setup
        uint256 amount = 10 * 1e18;
        uint64 time = 1 days;
        Vault dca = deployDaiToWethVault(time, amount);
        dai.transfer((address(dca)), amount);

        //exec & assert
        vm.prank(address(8888));
        vm.expectRevert(Vault.OwnerOnly.selector);
        dca.turnOff();
    }
}
