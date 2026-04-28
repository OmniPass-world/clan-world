// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @notice Constant-product AMM pool for one resource/gold pair.
///         Reserves are tracked internally; ClanWorld calls the math
///         functions to compute exchange rates, then mints/credits balances
///         directly via the internal accounting model.
///         No real ERC20 transfers occur here — the pool is the math oracle.
contract StubPool {
    address public immutable TOKEN_A;  // resource token
    address public immutable TOKEN_B;  // gold token
    address public immutable ENGINE;   // ClanWorld address

    uint256 public reserveA;          // resource reserve
    uint256 public reserveB;          // gold reserve

    bool private _seeded;

    modifier onlyEngine() {
        require(msg.sender == ENGINE, "StubPool: only engine");
        _;
    }

    constructor(address tokenA_, address tokenB_, address engine_) {
        TOKEN_A = tokenA_;
        TOKEN_B = tokenB_;
        ENGINE = engine_;
    }

    /// @notice Called by ClanWorld at seedPools time to set initial reserves.
    ///         Can only be called once.
    function seed(uint256 amountA, uint256 amountB) external onlyEngine {
        require(!_seeded, "StubPool: already seeded");
        require(amountA > 0 && amountB > 0, "StubPool: zero seed");
        reserveA = amountA;
        reserveB = amountB;
        _seeded = true;
    }

    /// @notice Exact-input sell: clan sells amountIn of resource, gets goldOut.
    ///         Constant-product: goldOut = reserveB * amountIn / (reserveA + amountIn).
    ///         Updates reserves. Called by ClanWorld; no token transfers.
    function sellResource(uint256 amountIn) external onlyEngine returns (uint256 goldOut) {
        require(amountIn > 0, "StubPool: zero amount");
        require(reserveA > 0 && reserveB > 0, "StubPool: not seeded");
        goldOut = (reserveB * amountIn) / (reserveA + amountIn);
        require(goldOut > 0, "StubPool: zero output");
        reserveA += amountIn;
        reserveB -= goldOut;
    }

    /// @notice Quote a buy without updating reserves (view).
    ///         goldIn = ceil(reserveB * amountOut / (reserveA - amountOut)).
    function quoteBuy(uint256 amountOut) external view returns (uint256 goldIn) {
        require(amountOut > 0, "StubPool: zero amount");
        require(amountOut < reserveA, "StubPool: insufficient resource reserve");
        uint256 num = reserveB * amountOut;
        uint256 denom_ = reserveA - amountOut;
        goldIn = num / denom_ + (num % denom_ == 0 ? 0 : 1);
    }

    /// @notice Exact-output buy: clan buys amountOut of resource, pays goldIn.
    ///         Returns actual goldIn charged (ceiling arithmetic).
    ///         Updates reserves. Called by ClanWorld; no token transfers.
    function buyResource(uint256 amountOut) external onlyEngine returns (uint256 goldIn) {
        require(amountOut > 0, "StubPool: zero amount");
        require(amountOut < reserveA, "StubPool: insufficient resource reserve");
        require(reserveB > 0, "StubPool: not seeded");
        uint256 num = reserveB * amountOut;
        uint256 denom_ = reserveA - amountOut;
        goldIn = num / denom_ + (num % denom_ == 0 ? 0 : 1);
        reserveA -= amountOut;
        reserveB += goldIn;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }
}
