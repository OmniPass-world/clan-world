// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {INttToken} from "./interfaces/INttToken.sol";

/// @title GoldBridgeToken
/// @notice ERC-20 representation token for GOLD on Base, designed for Wormhole NTT burning mode.
/// @dev Dependency-free on purpose. Compile with Solidity 0.8.34.
contract GoldBridgeToken is INttToken {
    string public name;
    string public symbol;
    uint256 public totalSupply;
    address public owner;
    address public minter;
    uint8 public constant GOLD_DECIMALS = 9;

    mapping(address account => uint256 balance) private balances;
    mapping(address account => mapping(address spender => uint256 allowanceAmount)) private
        allowances;

    error CallerNotOwner(address caller);
    error InvalidOwnerZeroAddress();
    error InvalidSenderZeroAddress();
    error InvalidRecipientZeroAddress();
    error AllowanceExceeded(uint256 allowanceAmount, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert CallerNotOwner(msg.sender);
        _;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert CallerNotMinter(msg.sender);
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address initialMinter_,
        address owner_
    ) {
        if (initialMinter_ == address(0)) revert InvalidMinterZeroAddress();
        if (owner_ == address(0)) revert InvalidOwnerZeroAddress();

        name = name_;
        symbol = symbol_;
        minter = initialMinter_;
        owner = owner_;

        emit NewMinter(address(0), initialMinter_);
        emit OwnershipTransferred(address(0), owner_);
    }

    function decimals() external pure returns (uint8) {
        return GOLD_DECIMALS;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function allowance(address account, address spender) external view returns (uint256) {
        return allowances[account][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert InvalidRecipientZeroAddress();
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert AllowanceExceeded(currentAllowance, amount);
            unchecked {
                allowances[from][msg.sender] = currentAllowance - amount;
            }
            emit Approval(from, msg.sender, allowances[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    function setMinter(address newMinter) external onlyOwner {
        if (newMinter == address(0)) revert InvalidMinterZeroAddress();
        address previousMinter = minter;
        minter = newMinter;
        emit NewMinter(previousMinter, newMinter);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwnerZeroAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function mint(address account, uint256 amount) external onlyMinter {
        if (account == address(0)) revert InvalidRecipientZeroAddress();
        totalSupply += amount;
        unchecked {
            balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert InvalidSenderZeroAddress();
        if (to == address(0)) revert InvalidRecipientZeroAddress();

        uint256 balance = balances[from];
        if (balance < amount) revert InsufficientBalance(balance, amount);
        unchecked {
            balances[from] = balance - amount;
            balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _burn(address account, uint256 amount) internal {
        if (account == address(0)) revert InvalidSenderZeroAddress();

        uint256 balance = balances[account];
        if (balance < amount) revert InsufficientBalance(balance, amount);
        unchecked {
            balances[account] = balance - amount;
            totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }
}
