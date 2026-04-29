// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @notice Minimal ERC20 boundary token. No external deps.
contract MinimalERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    address public immutable DEPLOYER;
    bool public treasurySeeded;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        DEPLOYER = msg.sender;
    }

    /// @dev Wrapped per forge-lint unwrapped-modifier-logic — keeps modifier
    /// body slim so the require isn't duplicated at every call site.
    function _onlyDeployer() internal view {
        require(msg.sender == DEPLOYER, "MinimalERC20: not deployer");
    }

    modifier onlyDeployer() {
        _onlyDeployer();
        _;
    }

    function seedTreasury(address treasury, uint256 amount) external onlyDeployer {
        require(!treasurySeeded, "MinimalERC20: treasury seeded");
        require(treasury != address(0), "MinimalERC20: zero treasury");

        treasurySeeded = true;
        _mint(treasury, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}
