// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ClanWorldConstants} from "../IClanWorld.sol";
import {LibStorage} from "./lib/LibStorage.sol";

contract ClanWorldDiamondInit {
    error ClanWorldDiamondAlreadyInitialized();

    function init() external {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        if (s.initialized) {
            revert ClanWorldDiamondAlreadyInitialized();
        }

        s.initialized = true;
        s.reentrancyStatus = LibStorage.NOT_ENTERED;
        s.world.currentTick = 0;
        s.world.nextHeartbeatAtTs = uint64(block.timestamp);
        s.world.seasonStartTick = 0;
        s.world.seasonEndTick = ClanWorldConstants.SEASON_DURATION_TICKS;
        s.world.seasonFinalized = false;
        s.world.currentSeasonNumber = 1;
        s.world.nextHeartbeatAtTick = 1;
        s.treasury.treasuryOwner = msg.sender;
        s.nextClanId = 1;
        s.nextClansmanId = 1;
        s.nextBanditId = 1;
    }
}
