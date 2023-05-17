pragma solidity ^0.8.17;
// SPDX-License-Identifier: MIT
interface IMulticall3 {
    struct Call {
        address target;
        bytes callData;
    }
    
    function aggregate(Call[] calldata calls) external payable returns (uint256 blockNumber, bytes[] memory returnData);
}