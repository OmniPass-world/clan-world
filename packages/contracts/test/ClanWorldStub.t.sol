// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorldStub} from "../src/ClanWorldStub.sol";
import {ClanWorldConstants, WorldState} from "../src/IClanWorld.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";

contract ClanWorldStubTest is Test {
    ClanWorldStub stub;

    function setUp() public {
        // Deploy mock tokens
        address[6] memory tokens;
        for (uint256 i = 0; i < 6; i++) {
            tokens[i] = address(new MinimalERC20("T", "T"));
        }
        // Deploy mock pools (Phase 2: engine arg is address(0) for stub tests)
        address[4] memory pools;
        for (uint256 i = 0; i < 4; i++) {
            pools[i] = address(new StubPool(tokens[i], tokens[4], address(0)));
        }
        stub = new ClanWorldStub(tokens, pools);
    }

    function test_heartbeat_increments_tick() public {
        assertEq(stub.getWorldState().currentTick, 1);
        stub.heartbeat();
        assertEq(stub.getWorldState().currentTick, 2);
    }

    function test_getWorldSnapshot_returns_current_tick() public {
        stub.heartbeat();
        assertEq(stub.getWorldSnapshot().currentTick, 2);
    }

    function test_initial_timer_fields_match_ClanWorld() public {
        WorldState memory ws = stub.getWorldState();

        assertEq(ws.currentSeasonNumber, 1, "season starts at 1");
        assertEq(ws.seasonStartTick, 0);
        assertEq(ws.seasonEndTick, ClanWorldConstants.SEASON_DURATION_TICKS);
        assertEq(ws.nextHeartbeatAtTick, ws.currentTick + 1, "next heartbeat opens currentTick + 1");
        assertEq(ws.winterStartsAtTick, ClanWorldConstants.WINTER_START_TICK);
        assertEq(ws.winterEndsAtTick, ClanWorldConstants.WINTER_START_TICK + ClanWorldConstants.WINTER_DURATION_TICKS);
        assertFalse(ws.winterActive);
        assertFalse(stub.isWinter());
    }
}
