//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {IAggregatorInterface} from "./interfaces/IAggregator.sol";
import {CloneExtended} from "./CloneExtended.sol";
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @title DCA vault implementation
/// @author HHK-ETH
/// @notice Sustainable and gas efficient DCA vault
contract Vault is CloneExtended {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OwnerOnly();
    error TooClose();
    error WorkerError();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event ExecuteDCA(uint256 received);
    event Withdraw(uint256 amount);
    event TurnOff();

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

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
    ///@return _decimalsDiff buyToken decimals - sellToken decimals
    ///@return _feeRatio Fee for the executor up to 1000 (no fee), 995 -> 0.5% fee
    ///@return _sellAmount Amount of token to sell
    function dcaData()
        public
        pure
        returns (
            IAggregatorInterface _sellTokenPriceFeed,
            IAggregatorInterface _buyTokenPriceFeed,
            uint64 _epochDuration,
            uint8 _decimalsDiff,
            uint16 _feeRatio,
            uint256 _sellAmount
        )
    {
        return (
            IAggregatorInterface(_getArgAddress(60)),
            IAggregatorInterface(_getArgAddress(80)),
            _getArgUint64(100),
            _getArgUint8(108),
            _getArgUint16(109),
            _getArgUint256(111)
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
            uint8 decimalsDiff,
            uint16 feeRatio,
            uint256 sellAmount
        ) = dcaData();

        if (lastBuy + epochDuration > block.timestamp) {
            revert TooClose();
        }
        lastBuy = block.timestamp;

        //query oracles and determine minAmount, both priceFeed must have same decimals.
        uint256 sellTokenPrice = uint256(sellTokenPriceFeed.latestAnswer());
        uint256 buyTokenPrice = uint256(buyTokenPriceFeed.latestAnswer());

        uint256 minAmount;
        unchecked {
            uint256 ratio = (sellTokenPrice * 1e24) / buyTokenPrice;
            minAmount = (((ratio * sellAmount) * (10 ** decimalsDiff)) * feeRatio) / 1000 / 1e24;
        }

        //send tokens to worker contract and call job
        sellToken().transfer(worker, sellAmount);
        (bool success,) = worker.call(job);
        if (!success) {
            revert WorkerError(); //This is here only to help bots to save gas on a job/swap error
        }

        //transfer minAmount minus 0.5% fee to the owner.
        //will revert if worker didn't send back minAmount.
        buyToken().transfer(owner(), minAmount);

        //transfer 0.5% + remaining to executor/msg.sender
        buyToken().transfer(msg.sender, buyToken().balanceOf(address(this)));

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
