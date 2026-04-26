// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal stub LP pool. Stores token pair addresses only.
contract StubPool {
    address public immutable tokenA;
    address public immutable tokenB;

    constructor(address tokenA_, address tokenB_) {
        tokenA = tokenA_;
        tokenB = tokenB_;
    }
}
