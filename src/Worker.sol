//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

/// @title Worker
/// @author HHK-ETH
/// @notice Very simple swap executor for Dca vaults
contract Worker {
    /// @notice PreApprove a token to execute swaps
    /// @notice /!\ because anyone can preApprove this contract should never be holding tokens.
    /// @param router Address of the dex/aggregator to approve
    /// @param token Address of the token to approve
    function preApprove(address router, address token) external {
        ERC20(token).approve(router, type(uint256).max);
    }

    /// @notice Execute the swap on a given agg/dex
    /// @param job Calldata to execute on the router
    function executeJob(bytes calldata job) external {
        (address router, bytes memory data) = abi.decode(job, (address, bytes));

        router.call(data);
    }

    /// @notice Execute the swap on a given agg/dex and send back tokens in case agg/dex didn't send back token to vault
    /// @param job Calldata to execute on the router & token out to send back to vault
    function executeJobAndSendBack(bytes calldata job) external {
        (address router, bytes memory data, address token) = abi.decode(job, (address, bytes, address));

        router.call(data);

        ERC20(token).transfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }
}
