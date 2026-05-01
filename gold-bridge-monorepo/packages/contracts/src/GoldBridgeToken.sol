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

/// @title GoldBridgeToken
/// @notice Upgradeable 9-decimal Base representation of Solana-canonical GOLD.
/// @dev This token is designed for Wormhole NTT burning mode. The NTT manager is expected to
/// become `minter` after deployment, allowing it to mint inbound GOLD and burn outbound GOLD.
///
/// Upgrade and recovery trust model:
/// - The proxy admin and token owner should both be a public timelock controlled by governance.
/// - `recoverFromAllowedSource` is an emergency migration hook, not a general admin transfer.
/// - Recovery can only move tokens out of addresses explicitly allowlisted by timelocked governance.
/// - The intended allowlist is ClanWorld or treasury/pool contracts that may temporarily custody GOLD.
/// - User wallets should not be allowlisted.
/// - Governance can permanently disable recovery with `disableRecoveryForever`.
contract GoldBridgeToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, INttToken {
    uint8 public constant GOLD_DECIMALS = 9;

    address public minter;
    bool public recoveryDisabled;
    mapping(address source => bool allowed) public recoveryAllowed;

    error InvalidRecoverySourceZeroAddress();
    error InvalidRecoveryRecipientZeroAddress();
    error RecoveryDisabled();
    error RecoverySourceNotAllowed(address source);

    event RecoveryAllowedSet(address indexed source, bool allowed);
    event RecoveryDisabledForever();
    event RecoveredFromAllowedSource(
        address indexed source, address indexed recipient, uint256 amount
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the proxy-backed token once.
    /// @param name_ ERC20 name.
    /// @param symbol_ ERC20 symbol.
    /// @param initialMinter_ Temporary minter, usually the deployer until NTT manager handoff.
    /// @param owner_ Timelock or governance address that controls minter and recovery settings.
    function initialize(
        string memory name_,
        string memory symbol_,
        address initialMinter_,
        address owner_
    )
        external
        initializer
    {
        if (initialMinter_ == address(0)) revert InvalidMinterZeroAddress();

        __ERC20_init(name_, symbol_);
        __Ownable_init(owner_);

        minter = initialMinter_;
        emit NewMinter(address(0), initialMinter_);
    }

    /// @notice Returns 9 decimals to match Solana GOLD accounting.
    function decimals() public pure override returns (uint8) {
        return GOLD_DECIMALS;
    }

    /// @notice Updates the NTT minter address.
    /// @dev Should be called through the owner timelock after the Base NTT manager is deployed.
    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert InvalidMinterZeroAddress();
        address previousMinter = minter;
        minter = newMinter;
        emit NewMinter(previousMinter, newMinter);
    }

    /// @notice Allows or removes one source address for emergency recovery.
    /// @dev This should be controlled by timelocked governance. Adding EOAs is possible but should
    /// be avoided in production unless there is a clearly documented migration reason.
    function setRecoveryAllowed(address source, bool allowed) external onlyOwner {
        if (recoveryDisabled) revert RecoveryDisabled();
        if (source == address(0)) revert InvalidRecoverySourceZeroAddress();
        recoveryAllowed[source] = allowed;
        emit RecoveryAllowedSet(source, allowed);
    }

    /// @notice Permanently disables all future recovery and allowlist changes.
    /// @dev This is irreversible. Upgrades controlled by the proxy admin timelock remain possible
    /// unless that separate upgrade authority is later revoked.
    function disableRecoveryForever() external onlyOwner {
        if (recoveryDisabled) revert RecoveryDisabled();
        recoveryDisabled = true;
        emit RecoveryDisabledForever();
    }

    /// @notice Moves GOLD from an explicitly allowlisted source to a recipient during migration.
    /// @dev This is a timelocked safety valve for contract-held liquidity only. It is intentionally
    /// narrower than a generic owner transfer: the `source` must have been allowlisted in advance,
    /// every allowlist change is on-chain, and governance can disable the function forever.
    function recoverFromAllowedSource(
        address source,
        address recipient,
        uint256 amount
    )
        external
        onlyOwner
    {
        if (recoveryDisabled) revert RecoveryDisabled();
        if (!recoveryAllowed[source]) revert RecoverySourceNotAllowed(source);
        if (recipient == address(0)) revert InvalidRecoveryRecipientZeroAddress();

        _transfer(source, recipient, amount);
        emit RecoveredFromAllowedSource(source, recipient, amount);
    }

    /// @notice Mints GOLD. Intended caller is the Base Wormhole NTT manager.
    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    /// @notice Burns the caller's GOLD. Used by Wormhole NTT for outbound Base to Solana transfers.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert CallerNotMinter(msg.sender);
        _;
    }

    uint256[47] private __gap;
}
