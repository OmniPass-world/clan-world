// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {INttToken} from "./interfaces/INttToken.sol";

/// @title GoldBridgeTokenV2
/// @notice Upgrade target for Base GOLD after emergency recovery is no longer needed.
/// @dev Storage layout intentionally preserves V1 state while removing the recovery API from the
/// public ABI. Upgrade authority remains with the proxy admin timelock unless separately revoked.
contract GoldBridgeTokenV2 is Initializable, ERC20Upgradeable, OwnableUpgradeable, INttToken {
    uint8 public constant GOLD_DECIMALS = 9;

    address public minter;
    bool private recoveryDisabledV1;
    mapping(address source => bool allowed) private recoveryAllowedV1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function decimals() public pure override returns (uint8) {
        return GOLD_DECIMALS;
    }

    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert InvalidMinterZeroAddress();
        address previousMinter = minter;
        minter = newMinter;
        emit NewMinter(previousMinter, newMinter);
    }

    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert CallerNotMinter(msg.sender);
        _;
    }

    uint256[47] private __gap;
}
