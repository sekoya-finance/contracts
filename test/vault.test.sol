// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test, stdError} from "forge-std/Test.sol";
import {Factory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {Token} from "../src/mocks/Token.sol";
import {PriceAggregator, IAggregatorInterface} from "../src/mocks/PriceAggregator.sol";
import {BentoBoxV1 as BentoBox, IERC20} from "../src/flat/BentoBox.sol";
import {Multicall3} from "../src/flat/Multicall3.sol";

contract VaultTest is Test {
    Factory factory;
    Vault vault;
    Multicall3 multicall;
    Token dai;
    Token weth;
    PriceAggregator daiOracle;
    PriceAggregator wethOracle;
    BentoBox bento;

    uint256 SELL_AMOUNT;
    uint256 constant EPOCH_DURATION = 10 minutes;
    address constant EXECUTOR = address(1111);

    function setUp() public {
        //set timestamp to 01/01/2023
        vm.warp(1672527600);
        //deploy contracts
        vault = new Vault();
        factory = new Factory(vault);
        multicall = new Multicall3();
        dai = new Token("DAI", "DAI", 18, 1000 * 1e18);
        SELL_AMOUNT = 10 * 10 ** dai.decimals();
        weth = new Token("WETH", "WETH", 18, 1000* 1e18);
        bento = new BentoBox(IERC20(address(weth)));

        //set Oracles
        daiOracle = new PriceAggregator(8);
        daiOracle.setLatestAnswer(1 * 1e8);
        wethOracle = new PriceAggregator(8);
        wethOracle.setLatestAnswer(500 * 1e8);

        //Give a bunch of WETH to multicall & preApprove bento to execute orders
        //This is to simplify tests, in production real router & swap data will be sent to multicall
        weth.transfer(address(multicall), 500 * 1e18);
        Multicall3.Call[] memory calls = new Multicall3.Call[](1);
        calls[0] = Multicall3.Call(address(weth), abi.encodeCall(weth.approve, (address(bento), UINT256_MAX)));
        multicall.aggregate(calls);

        //Pre Approve DAI & WETH on bentobox & preDeposit
        dai.approve(address(bento), UINT256_MAX);
        bento.deposit(IERC20(address(dai)), address(this), address(1), 1 * 10 ** dai.decimals(), 0);
        weth.approve(address(bento), UINT256_MAX);
        bento.deposit(IERC20(address(weth)), address(this), address(1), 1 * 10 ** weth.decimals(), 0);
    }

    ///@notice Function to easily deploy a dai to weth vault
    function deployDaiToWethVault() public returns (Vault) {
        bytes memory params = abi.encodePacked(
            address(bento),
            address(this),
            address(dai),
            address(weth),
            address(daiOracle),
            address(wethOracle),
            uint64(10 minutes),
            SELL_AMOUNT,
            10 ** dai.decimals(),
            10 ** weth.decimals()
        );

        return factory.createDCA(params, true);
    }

    ///@notice Function to easily execute a dca
    function executeDaiToWethDca(Vault dca, uint256 amount, address executor) public returns (uint256 wethAmount) {
        //determine price & send weth to multicall to emulate a swap with just executing a transfer back to the vault
        uint256 daiTokenPrice = uint256(daiOracle.latestAnswer());
        uint256 wethTokenPrice = uint256(wethOracle.latestAnswer());
        uint256 ratio = (daiTokenPrice * 1e24) / wethTokenPrice;
        wethAmount = (ratio * amount) / 1e24;

        Multicall3.Call[] memory calls = new Multicall3.Call[](1);
        bytes memory jobCallData =
            abi.encodeCall(bento.deposit, (IERC20(address(weth)), address(multicall), address(dca), wethAmount, 0));
        calls[0] = Multicall3.Call(address(bento), jobCallData);

        vm.prank(executor);
        dca.executeDCA(address(multicall), abi.encodeCall(multicall.aggregate, (calls)));
    }

    function testDeployDAItoWETHVault() public {
        //exec
        Vault dca = deployDaiToWethVault();

        //assert
        assertEq(dca.lastBuy(), block.timestamp);
        assertEq(address(dca.bento()), address(bento));
        assertEq(dca.owner(), address(this));
        assertEq(address(dca.sellToken()), address(dai));
        assertEq(address(dca.buyToken()), address(weth));
        (
            IAggregatorInterface sellTokenOracle,
            IAggregatorInterface buyTokenOracle,
            uint64 epochDuration,
            uint256 _amount,
            uint256 _sellTokenDecimalsFactor,
            uint256 _buyTokenDecimalsFactor
        ) = dca.dcaData();
        assertEq(address(sellTokenOracle), address(daiOracle));
        assertEq(address(buyTokenOracle), address(wethOracle));
        assertEq(epochDuration, EPOCH_DURATION);
        assertEq(_amount, SELL_AMOUNT);
        assertEq(_sellTokenDecimalsFactor, 10 ** dai.decimals());
        assertEq(_buyTokenDecimalsFactor, 10 ** weth.decimals());
    }

    function testExecuteDca() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);

        vm.warp(block.timestamp + EPOCH_DURATION); //Add 10 min time so we can execute the dca

        //save balances
        uint256 oldOwnerBalance = bento.balanceOf(IERC20(address(weth)), address(this));
        uint256 oldExecutorBalance = bento.balanceOf(IERC20(address(weth)), EXECUTOR);

        //exec
        uint256 wethAmount = executeDaiToWethDca(dca, SELL_AMOUNT, EXECUTOR);

        //assert
        assertEq(bento.balanceOf(IERC20(address(weth)), address(this)), oldOwnerBalance + (wethAmount * 995 / 1000));
        assertEq(
            bento.balanceOf(IERC20(address(weth)), EXECUTOR), oldExecutorBalance + (wethAmount * (1000 - 995) / 1000)
        );
    }

    function testExecuteDca_fail_tooClose() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);

        //exec & assert
        vm.prank(EXECUTOR);
        vm.expectRevert(Vault.TooClose.selector); //assert that it will revert with TooClose error
        dca.executeDCA(address(multicall), "");
    }

    function testExecuteDca_fail_oracleError() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);
        daiOracle.setLatestAnswer(0); //set oracle to 0
        vm.warp(block.timestamp + EPOCH_DURATION); //Add 10 min time so we can execute the dca

        //exec & assert
        vm.prank(EXECUTOR);
        vm.expectRevert(Vault.OracleError.selector); //assert that it will revert with TooClose error
        dca.executeDCA(address(multicall), "");
    }

    function testExecuteDca_fail_notEnoughTokenReturned() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);
        vm.warp(block.timestamp + EPOCH_DURATION); //Add 10 min time so we can execute the dca
        Multicall3.Call[] memory calls = new Multicall3.Call[](0);

        //exec & assert
        vm.prank(EXECUTOR);
        vm.expectRevert(stdError.arithmeticError); //assert that it will revert with "TRANSFER_FAILED"
        dca.executeDCA(address(multicall), abi.encodeCall(multicall.aggregate, (calls)));
    }

    function testWithdraw() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);

        uint256 oldVaultBalance = bento.balanceOf(IERC20(address(dai)), address(dca));
        uint256 oldOwnerBalance = dai.balanceOf(address(this));

        //exec
        dca.withdraw(SELL_AMOUNT);

        //assert
        assertEq(bento.balanceOf(IERC20(address(dai)), address(dca)), oldVaultBalance - SELL_AMOUNT);
        assertEq(dai.balanceOf(address(this)), oldOwnerBalance + SELL_AMOUNT);
    }

    function testWithdraw_fail_ownerOnly() public {
        //setup
        Vault dca = deployDaiToWethVault();
        dai.transfer((address(dca)), SELL_AMOUNT);

        //exec & assert
        vm.prank(address(8888));
        vm.expectRevert(Vault.OwnerOnly.selector);
        dca.withdraw(SELL_AMOUNT);
    }

    function testCancel() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);

        uint256 oldVaultBalance = bento.balanceOf(IERC20(address(dai)), address(dca));
        uint256 oldOwnerBalance = dai.balanceOf(address(this));

        //exec
        dca.cancel();

        //assert
        assertEq(dai.balanceOf(address(dca)), 0);
        assertEq(dai.balanceOf(address(this)), oldOwnerBalance + oldVaultBalance);
    }

    function testCancel_fail_ownerOnly() public {
        //setup
        Vault dca = deployDaiToWethVault();
        bento.deposit(IERC20(address(dai)), address(this), address(dca), SELL_AMOUNT, 0);

        //exec & assert
        vm.prank(address(8888));
        vm.expectRevert(Vault.OwnerOnly.selector);
        dca.cancel();
    }
}
