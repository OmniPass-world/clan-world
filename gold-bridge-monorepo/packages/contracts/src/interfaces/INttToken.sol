// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.34;

interface INttToken {
    error CallerNotMinter(address caller);
    error InvalidMinterZeroAddress();
    error InsufficientBalance(uint256 balance, uint256 amount);

    event NewMinter(address previousMinter, address newMinter);

    function mint(address account, uint256 amount) external;
    function setMinter(address newMinter) external;
    function burn(uint256 amount) external;
}
