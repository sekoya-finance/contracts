//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {IAggregatorInterface} from "./interfaces/IAggregator.sol";
import {IBentoBox} from "./interfaces/IBentoBox.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";
import {IMulticall3} from "./interfaces/IMulticall3.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @title DCA vault implementation
/// @author HHK-ETH
/// @notice Sustainable and gas efficient DCA vault
contract Vault is Clone {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OwnerOnly();
    error TooClose();
    error NotEnough();
    error OracleError();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event ExecuteDCA(uint256 received);
    event Withdraw(ERC20 token, uint256 amount);
    event Cancel();

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

    uint256 private constant PRECISION = 1e24;

    ///@notice Address of the BentoBox
    function bento() public pure returns (IBentoBox) {
        return IBentoBox(payable(_getArgAddress(0)));
    }

    ///@notice Address of the vault owner
    function owner() public pure returns (address) {
        return _getArgAddress(20);
    }

    ///@notice Address of the token to sell
    function sellToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(40));
    }

    ///@notice Address of the token to buy
    function buyToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(60));
    }

    ///@notice Infos about the DCA
    ///@return _sellTokenPriceFeed Address of the priceFeed
    ///@return _buyTokenPriceFeed Address of the priceFeed
    ///@return _epochDuration Minimum time between each buy
    ///@return _sellAmount Amount of token to sell
    ///@return _sellTokenDecimalsFactor 10 ** sellToken.decimals()
    ///@return _buyTokenDecimalsFactor 10 ** buyToken.decimals()
    function dcaData()
        public
        pure
        returns (IAggregatorInterface, IAggregatorInterface, uint64, uint256, uint256, uint256)
    {
        return (
            IAggregatorInterface(_getArgAddress(80)),
            IAggregatorInterface(_getArgAddress(100)),
            _getArgUint64(120),
            _getArgUint256(128),
            _getArgUint256(160),
            _getArgUint256(192)
        );
    }

    /// -----------------------------------------------------------------------
    /// Mutable variables
    /// -----------------------------------------------------------------------

    ///@notice Store last buy timestamp, init as block.timestamp
    uint256 public lastBuy;

    /// -----------------------------------------------------------------------
    /// Modifier
    /// -----------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner()) {
            revert OwnerOnly();
        }
        _;
    }

    /// -----------------------------------------------------------------------
    /// State change functions
    /// -----------------------------------------------------------------------

    ///@notice Execute the DCA buy
    ///@param multicall Multicall contract
    ///@param calls Actions to execute on the multicall
    function executeDCA(IMulticall3 multicall, IMulticall3.Call[] calldata calls) external {
        (
            IAggregatorInterface sellTokenPriceFeed,
            IAggregatorInterface buyTokenPriceFeed,
            uint64 epochDuration,
            uint256 sellAmount,
            uint256 sellTokenDecimalsFactor,
            uint256 buyTokenDecimalsFactor
        ) = dcaData();

        if (lastBuy + epochDuration > block.timestamp) {
            revert TooClose();
        }
        lastBuy = block.timestamp;

        uint256 minAmount;
        //Put minAmount calculation in a block to avoid stack too deep
        {
            //query oracles and determine minAmount, both priceFeed must have same decimals.
            uint256 sellTokenPriceUSD = getPrice(sellTokenPriceFeed);
            uint256 buyTokenPriceUSD = getPrice(buyTokenPriceFeed);

            assembly {
                let ratio := div(mul(sellTokenPriceUSD, PRECISION), buyTokenPriceUSD)
                minAmount := mul(ratio, sellAmount)
                minAmount := div(minAmount, sellTokenDecimalsFactor)
                minAmount := mul(minAmount, buyTokenDecimalsFactor)
                minAmount := mul(minAmount, 995)
                minAmount := div(minAmount, 1000)
                minAmount := div(minAmount, PRECISION)
            }
        }

        //save current balance
        uint256 previousBalance = bento().balanceOf(buyToken(), address(this));
        //send tokens to worker contract and call job
        bento().transfer(sellToken(), address(this), address(multicall), sellAmount);
        multicall.aggregate(calls);

        //Check if received enough
        uint256 minAmountToShare = bento().toShare(buyToken(), minAmount, false);
        uint256 received = bento().balanceOf(buyToken(), address(this)) - previousBalance;
        if (received < minAmountToShare) {
            revert NotEnough();
        }

        emit ExecuteDCA(received);
    }

    ///@notice Allow the owner to withdraw its token from the vault
    function withdraw(ERC20 token, uint256 amount) external onlyOwner {
        bento().withdraw(token, address(this), owner(), amount, 0);
        emit Withdraw(token, amount);
    }

    ///@notice Allow the owner to withdraw total balance and emit a Cancel event so UI stop showing the contract
    ///@notice Doesn't use selfdestruct as it is deprecated
    function cancel() external onlyOwner {
        bento().withdraw(sellToken(), address(this), owner(), 0, bento().balanceOf(sellToken(), address(this)));
        bento().withdraw(buyToken(), address(this), owner(), 0, bento().balanceOf(buyToken(), address(this)));
        emit Cancel();
    }

    ///@notice function to set last buy on vault creation
    ///@param waitEpochPeriod false to set to 1 so first execDca can be called or true to wait for epochPeriod before first exec
    function setLastBuy(bool waitEpochPeriod) external {
        if (lastBuy == 0) {
            if (waitEpochPeriod) {
                lastBuy = block.timestamp;
            } else {
                lastBuy = 1;
            }
        }
    }

    function getPrice(IAggregatorInterface sellTokenPriceFeed) internal view returns (uint256) {
        (, int256 integerPrice,,,) = sellTokenPriceFeed.latestRoundData();
        if (integerPrice <= 0) {
            revert OracleError();
        }
        return uint256(integerPrice);
    }
}
