//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {IAggregatorInterface} from "./interfaces/IAggregator.sol";
import {BentoBoxV1 as BentoBox, IERC20} from "./flat/BentoBox.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";

/// @title DCA vault implementation
/// @author HHK-ETH
/// @notice Sustainable and gas efficient DCA vault
contract Vault is Clone {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OwnerOnly();
    error TooClose();
    error WorkerError();
    error OracleError();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event ExecuteDCA(uint256 received);
    event Withdraw(uint256 amount);
    event Cancel();

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

    uint256 private constant PRECISION = 1e24;

    ///@notice Address of the BentoBox
    function bento() public pure returns (BentoBox) {
        return BentoBox(payable(_getArgAddress(0)));
    }

    ///@notice Address of the vault owner
    function owner() public pure returns (address) {
        return _getArgAddress(20);
    }

    ///@notice Address of the token to sell
    function sellToken() public pure returns (IERC20) {
        return IERC20(_getArgAddress(40));
    }

    ///@notice Address of the token to buy
    function buyToken() public pure returns (IERC20) {
        return IERC20(_getArgAddress(60));
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
    ///@param worker Contract that will execute the swap
    ///@param job calldata to execute on the contract
    function executeDCA(address worker, bytes calldata job) external {
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

        //query oracles and determine minAmount, both priceFeed must have same decimals.
        uint256 sellTokenPriceUSD = uint256(sellTokenPriceFeed.latestAnswer());
        uint256 buyTokenPriceUSD = uint256(buyTokenPriceFeed.latestAnswer());

        if (sellTokenPriceUSD == 0 || buyTokenPriceUSD == 0) {
            revert OracleError();
        }

        uint256 minAmount;
        assembly {
            let ratio := div(mul(sellTokenPriceUSD, PRECISION), buyTokenPriceUSD)
            minAmount := mul(ratio, sellAmount)
            minAmount := div(minAmount, sellTokenDecimalsFactor)
            minAmount := mul(minAmount, buyTokenDecimalsFactor)
            minAmount := mul(minAmount, 995)
            minAmount := div(minAmount, 1000)
            minAmount := div(minAmount, PRECISION)
        }

        //send tokens to worker contract and call job
        bento().transfer(sellToken(), address(this), worker, sellAmount);
        (bool success,) = worker.call(job);
        if (!success) {
            revert WorkerError(); //This is here only to help bots to save gas on a job/swap error
        }

        //transfer minAmount minus fee to the owner.
        //will revert if worker didn't send back minAmount.
        bento().transfer(buyToken(), address(this), owner(), minAmount);

        //transfer fee + remaining to executor/msg.sender
        bento().transfer(buyToken(), address(this), msg.sender, bento().balanceOf(buyToken(), address(this)));

        emit ExecuteDCA(minAmount);
    }

    ///@notice Allow the owner to withdraw its token from the vault
    function withdraw(uint256 amount) external onlyOwner {
        bento().withdraw(sellToken(), address(this), owner(), amount, 0);
        emit Withdraw(amount);
    }

    ///@notice Allow the owner to withdraw total balance and emit a Cancel event so UI stop showing the contract
    ///@notice Doesn't use selfdestruct as it is deprecated
    function cancel() external onlyOwner {
        bento().withdraw(sellToken(), address(this), owner(), 0, bento().balanceOf(sellToken(), address(this)));
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
}
