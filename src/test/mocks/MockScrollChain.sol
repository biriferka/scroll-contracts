// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {ScrollChain} from "../../L1/rollup/ScrollChain.sol";

contract MockScrollChain is ScrollChain {
    constructor(address _messageQueue, address _verifier) ScrollChain(0, _messageQueue, _verifier, address(0)) {}

    function setLastFinalizedBatchIndex(uint256 _lastFinalizedBatchIndex) external {
        lastFinalizedBatchIndex = _lastFinalizedBatchIndex;
    }
}
