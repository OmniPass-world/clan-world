// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {StatusCode} from "../src/IClanWorld.sol";

contract StatusCodeEnumStabilityTest is Test {
    function test_statusCodeNumericValuesAreStable() public pure {
        assertEq(uint8(StatusCode.OK), 0, "OK");
        assertEq(uint8(StatusCode.ERR_CLAN_DEAD), 1, "ERR_CLAN_DEAD");
        assertEq(uint8(StatusCode.ERR_CLAN_NOT_OWNED), 2, "ERR_CLAN_NOT_OWNED");
        assertEq(uint8(StatusCode.ERR_CLANSMAN_DEAD), 3, "ERR_CLANSMAN_DEAD");
        assertEq(uint8(StatusCode.ERR_INVALID_CLANSMAN), 4, "ERR_INVALID_CLANSMAN");
        assertEq(uint8(StatusCode.ERR_INVALID_REGION), 5, "ERR_INVALID_REGION");
        assertEq(uint8(StatusCode.ERR_INVALID_ACTION), 6, "ERR_INVALID_ACTION");
        assertEq(uint8(StatusCode.ERR_INVALID_TARGET), 7, "ERR_INVALID_TARGET");
        assertEq(uint8(StatusCode.ERR_COOLDOWN_ACTIVE), 8, "ERR_COOLDOWN_ACTIVE");
        assertEq(uint8(StatusCode.ERR_NOT_WAITING), 9, "ERR_NOT_WAITING");
        assertEq(uint8(StatusCode.ERR_NOT_IN_UNICORN_TOWN), 10, "ERR_NOT_IN_UNICORN_TOWN");
        assertEq(uint8(StatusCode.ERR_NOT_AT_HOMEBASE), 11, "ERR_NOT_AT_HOMEBASE");
        assertEq(uint8(StatusCode.ERR_NOT_AT_TARGET_BASE), 12, "ERR_NOT_AT_TARGET_BASE");
        assertEq(uint8(StatusCode.ERR_NOT_DEFENDABLE), 13, "ERR_NOT_DEFENDABLE");
        assertEq(uint8(StatusCode.ERR_MISSING_RESOURCES), 14, "ERR_MISSING_RESOURCES");
        assertEq(uint8(StatusCode.ERR_EMPTY_CARGO), 15, "ERR_EMPTY_CARGO");
        assertEq(uint8(StatusCode.ERR_PLOT_NOT_READY), 16, "ERR_PLOT_NOT_READY");
        assertEq(uint8(StatusCode.ERR_PLOT_EMPTY), 17, "ERR_PLOT_EMPTY");
        assertEq(uint8(StatusCode.ERR_MARKET_ZERO_AMOUNT), 18, "ERR_MARKET_ZERO_AMOUNT");
        assertEq(uint8(StatusCode.ERR_MARKET_UNSUPPORTED_TOKEN), 19, "ERR_MARKET_UNSUPPORTED_TOKEN");
        assertEq(uint8(StatusCode.ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE), 20, "ERR_IMMEDIATE_MARKET_NOT_ELIGIBLE");
        assertEq(uint8(StatusCode.ERR_MARKET_BUY_OVER_CAPACITY), 21, "ERR_MARKET_BUY_OVER_CAPACITY");
        assertEq(uint8(StatusCode.ERR_MAX_GOLD_IN_EXCEEDED), 22, "ERR_MAX_GOLD_IN_EXCEEDED");
        assertEq(uint8(StatusCode.ERR_WORLD_TICK_MISMATCH), 23, "ERR_WORLD_TICK_MISMATCH");
        assertEq(uint8(StatusCode.ERR_NO_ACTIVE_BANDIT), 24, "ERR_NO_ACTIVE_BANDIT");
        assertEq(uint8(StatusCode.ERR_SEASON_ENDED), 25, "ERR_SEASON_ENDED");
        assertEq(uint8(StatusCode.ERR_NOT_ENOUGH_GOLD), 26, "ERR_NOT_ENOUGH_GOLD");
        assertEq(uint8(StatusCode.ERR_CARRY_FULL), 27, "ERR_CARRY_FULL");
        assertEq(uint8(StatusCode.ERR_WINTER_LOCKED), 28, "ERR_WINTER_LOCKED");
        assertEq(uint8(StatusCode.ERR_MUST_SETTLE_FIRST), 29, "ERR_MUST_SETTLE_FIRST");
        assertEq(uint8(StatusCode.ERR_LIQUIDITY_INSUFFICIENT), 30, "ERR_LIQUIDITY_INSUFFICIENT");
        assertEq(uint8(StatusCode.ERR_SLIPPAGE_REQUIRED), 31, "ERR_SLIPPAGE_REQUIRED");
    }
}
