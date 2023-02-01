//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {IAggregatorInterface} from "./interfaces/IAggregator.sol";
import {Clone} from "clones-with-immutable-args/Clone.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "lib/solmate/src/utils/SafeTransferLib.sol";

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
    event TurnOff();

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

    uint256 private constant PRECISION = 1e24;

    ///@notice Address of the vault owner
    function owner() public pure returns (address _owner) {
        return _getArgAddress(0);
    }

    ///@notice Address of the token to sell
    function sellToken() public pure returns (ERC20 _sellToken) {
        return ERC20(_getArgAddress(20));
    }

    ///@notice Address of the token to buy
    function buyToken() public pure returns (ERC20 _buyToken) {
        return ERC20(_getArgAddress(40));
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
        returns (
            IAggregatorInterface _sellTokenPriceFeed,
            IAggregatorInterface _buyTokenPriceFeed,
            uint64 _epochDuration,
            uint256 _sellAmount,
            uint256 _sellTokenDecimalsFactor,
            uint256 _buyTokenDecimalsFactor
        )
    {
        return (
            IAggregatorInterface(_getArgAddress(60)),
            IAggregatorInterface(_getArgAddress(80)),
            _getArgUint64(100),
            _getArgUint256(108),
            _getArgUint256(140),
            _getArgUint256(172)
        );
    }

    /// -----------------------------------------------------------------------
    /// Mutable variables
    /// -----------------------------------------------------------------------

    ///@notice Store last buy timestamp
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
            //Because user can submit invalid sellTokenDecimalsFactor & buyTokenDecimalsFactor,
            //bots should double check offchain as could end up in evm panicking and loss of gas
            let ratio := div(mul(sellTokenPriceUSD, PRECISION), buyTokenPriceUSD)
            minAmount := mul(ratio, sellAmount) // /!\ sellAmount could be 0
            minAmount := div(minAmount, sellTokenDecimalsFactor) // /!\ sellTokenDecimalsFactor could be 0
            minAmount := mul(minAmount, buyTokenDecimalsFactor) // /!\ sellTokenDecimalsFactor could be 0
            minAmount := mul(minAmount, 995)
            minAmount := div(minAmount, 1000)
            minAmount := div(minAmount, PRECISION)
        }

        //send tokens to worker contract and call job
        SafeTransferLib.safeTransfer(sellToken(), worker, sellAmount);
        (bool success,) = worker.call(job);
        if (!success) {
            revert WorkerError(); //This is here only to help bots to save gas on a job/swap error
        }

        //transfer minAmount minus fee to the owner.
        //will revert if worker didn't send back minAmount.
        SafeTransferLib.safeTransfer(buyToken(), owner(), minAmount);

        //transfer fee + remaining to executor/msg.sender
        SafeTransferLib.safeTransfer(buyToken(), msg.sender, buyToken().balanceOf(address(this)));

        emit ExecuteDCA(minAmount);
    }

    ///@notice Allow the owner to withdraw its token from the vault
    function withdraw(uint256 amount) external onlyOwner {
        sellToken().transfer(owner(), amount);
        emit Withdraw(amount);
    }

    ///@notice Allow the owner to withdraw total balance and emit a turnOff event so UI can stop indexing the contract
    ///@notice Doesn't use selfdestruct in case owner keep sending tokens to this address
    function turnOff() external onlyOwner {
        sellToken().transfer(owner(), sellToken().balanceOf(address(this)));
        emit TurnOff();
    }
}
