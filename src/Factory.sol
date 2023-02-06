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
    ///@param params ABI encode packed of params
    ///@return newVault Vault address
    ///@param waitEpochPeriod false so first execDca can be called or true to wait for epochPeriod before first exec
    function createDCA(bytes calldata params, bool waitEpochPeriod) external returns (Vault newVault) {
        //address bentobox address
        //address owner Address of the owner of the vault
        //address sellToken Address of the token to sell
        //address buyToken Address of the token to buy
        //address sellTokenPriceFeed Address of the priceFeed to use to determine sell token price
        //address buyTokenPriceFeed Address of the priceFeed to use to determine buy token price
        //uint64 epochDuration Minimum time between each buy
        //uint256 amount Amount to use on each buy
        //uint256 sellTokenDecimalsFactor 10 ** ERC20(sellToken).decimals();
        //uint256 buyTokenDecimalsFactor 10 ** ERC20(buyToken).decimals();

        newVault = Vault(address(implementation).clone(params));
        newVault.setLastBuy(waitEpochPeriod);
        emit CreateDCA(newVault);
    }
}
