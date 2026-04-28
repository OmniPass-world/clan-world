// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @notice Minimal stub LP pool. Stores token pair addresses only.
contract StubPool {
    address public immutable TOKEN_A;
    address public immutable TOKEN_B;

    constructor(address tokenA_, address tokenB_) {
        TOKEN_A = tokenA_;
        TOKEN_B = tokenB_;
    }
}
