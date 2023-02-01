//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import "./Vault.sol";

/// @title Vault factory
/// @author HHK-ETH
/// @notice Factory to create DCA vaults
contract Factory {
    using ClonesWithImmutableArgs for address;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    event CreateDCA(Vault newVault);

    /// -----------------------------------------------------------------------
    /// Immutable variables and constructor
    /// -----------------------------------------------------------------------
    Vault public immutable implementation;

    constructor(Vault _implementation) {
        implementation = _implementation;
    }

    /// -----------------------------------------------------------------------
    /// State change functions
    /// -----------------------------------------------------------------------

    ///@notice Deploy a new DCA vault
    ///@param owner Address of the owner of the vault
    ///@param sellToken Address of the token to sell
    ///@param buyToken Address of the token to buy
    ///@param sellTokenPriceFeed Address of the priceFeed to use to determine sell token price
    ///@param buyTokenPriceFeed Address of the priceFeed to use to determine buy token price
    ///@param epochDuration Minimum time between each buy
    ///@param amount Amount to use on each buy
    ///@param sellTokenDecimalsFactor 10 ** sellToken.decimals()
    ///@param buyTokenDecimalsFactor 10 ** buyToken.decimals()
    ///@return newVault Vault address
    function createDCA(
        address owner,
        address sellToken,
        address buyToken,
        address sellTokenPriceFeed,
        address buyTokenPriceFeed,
        uint64 epochDuration,
        uint256 amount,
        uint256 sellTokenDecimalsFactor,
        uint256 buyTokenDecimalsFactor
    ) external returns (Vault newVault) {
        bytes memory data = abi.encodePacked(
            owner,
            sellToken,
            buyToken,
            sellTokenPriceFeed,
            buyTokenPriceFeed,
            epochDuration,
            amount,
            sellTokenDecimalsFactor,
            buyTokenDecimalsFactor
        );
        newVault = Vault(address(implementation).clone(data));
        emit CreateDCA(newVault);
    }
}
