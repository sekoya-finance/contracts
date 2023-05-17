//SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";

interface IBentoBox {
    function transfer(ERC20 token, address from, address to, uint256 share) external;

    function withdraw(ERC20 token_, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);

    function balanceOf(ERC20 token, address account) external returns (uint256);

    function toAmount(ERC20 token, uint256 share, bool roundUp) external returns (uint256);

    function toShare(ERC20 token, uint256 amount, bool roundUp) external returns (uint256);
}
