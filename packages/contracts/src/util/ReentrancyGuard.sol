// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus;

    constructor() {
        _reentrancyStatus = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "ClanWorld: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }
}
