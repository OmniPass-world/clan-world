// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Constant-product AMM pool for one resource/gold pair.
///         TOKEN_A is the resource token and TOKEN_B is gold. ClanWorld owns
///         the swap surface because clans use the engine's internal accounting,
///         while the treasury seeds real ERC20 balances into the pool once.
contract StubPool {
    address public immutable TOKEN_A; // resource token
    address public immutable TOKEN_B; // gold token
    address public immutable ENGINE; // ClanWorld address

    uint256 public reserveA; // resource reserve
    uint256 public reserveB; // gold reserve

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
        require(IERC20Balance(TOKEN_A).balanceOf(address(this)) >= amountA, "StubPool: missing token A");
        require(IERC20Balance(TOKEN_B).balanceOf(address(this)) >= amountB, "StubPool: missing token B");
        reserveA = amountA;
        reserveB = amountB;
        _seeded = true;
    }

    function getAmountOutForExactIn(uint256 amountIn) public view returns (uint256 amountOut) {
        require(amountIn > 0, "StubPool: zero amount");
        require(reserveA > 0 && reserveB > 0, "StubPool: not seeded");
        amountOut = (reserveB * amountIn) / (reserveA + amountIn);
    }

    function getAmountInForExactOut(uint256 amountOut) public view returns (uint256 amountIn) {
        require(amountOut > 0, "StubPool: zero amount");
        require(amountOut < reserveA, "StubPool: insufficient resource reserve");
        require(reserveB > 0, "StubPool: not seeded");

        uint256 numerator = reserveB * amountOut;
        uint256 denominator = reserveA - amountOut;
        amountIn = numerator / denominator + (numerator % denominator == 0 ? 0 : 1);
    }

    /// @notice Exact-input sell: resource in, gold out.
    function swapExactInForOut(uint256 amountIn, uint256 minOut) external onlyEngine returns (uint256 amountOut) {
        return _swapExactInForOut(amountIn, minOut);
    }

    function _swapExactInForOut(uint256 amountIn, uint256 minOut) internal returns (uint256 amountOut) {
        uint256 priorK = reserveA * reserveB;
        amountOut = getAmountOutForExactIn(amountIn);
        require(amountOut >= minOut, "StubPool: insufficient output");

        reserveA += amountIn;
        reserveB -= amountOut;

        require(reserveA * reserveB >= priorK, "StubPool: k invariant");
    }

    /// @notice Exact-output buy: gold in, exact resource out.
    function swapExactOutForInWithMaxIn(uint256 amountOut, uint256 maxIn)
        external
        onlyEngine
        returns (uint256 amountIn)
    {
        return _swapExactOutForInWithMaxIn(amountOut, maxIn);
    }

    function _swapExactOutForInWithMaxIn(uint256 amountOut, uint256 maxIn) internal returns (uint256 amountIn) {
        uint256 priorK = reserveA * reserveB;
        amountIn = getAmountInForExactOut(amountOut);
        require(amountIn <= maxIn, "StubPool: max input exceeded");

        reserveA -= amountOut;
        reserveB += amountIn;

        require(reserveA * reserveB >= priorK, "StubPool: k invariant");
    }

    /// @notice Exact-input sell: clan sells amountIn of resource, gets goldOut.
    ///         Legacy alias for Phase 6.1 scheduled-market code.
    function sellResource(uint256 amountIn) external onlyEngine returns (uint256 goldOut) {
        goldOut = _swapExactInForOut(amountIn, 1);
    }

    /// @notice Legacy quote alias for exact-output resource buys.
    function quoteBuy(uint256 amountOut) external view returns (uint256 goldIn) {
        goldIn = getAmountInForExactOut(amountOut);
    }

    /// @notice Exact-output buy: clan buys amountOut of resource, pays goldIn.
    ///         Legacy alias for Phase 6.1 scheduled-market code.
    function buyResource(uint256 amountOut) external onlyEngine returns (uint256 goldIn) {
        goldIn = _swapExactOutForInWithMaxIn(amountOut, type(uint256).max);
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }
}
