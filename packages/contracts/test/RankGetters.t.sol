// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {ClanWorldConstants, Clan, ClanOrder, OrderResult, StatusCode, ActionType} from "../src/IClanWorld.sol";

contract RankGetterHarness is ClanWorld {
    function setVault(uint32 clanId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }

    function setWallLevel(uint32 clanId, uint8 wallLevel) external {
        _clans[clanId].wallLevel = wallLevel;
    }
}

contract RankGettersTest is Test {
    RankGetterHarness world;
    address elderA = address(0xA1);
    address elderB = address(0xA2);
    address elderC = address(0xA3);

    function setUp() public {
        world = new RankGetterHarness();
    }

    function _mintClan(address owner) internal returns (uint32 clanId) {
        vm.prank(owner);
        (clanId,) = world.mintClan(owner);
    }

    function _csAt(uint32 clanId, uint256 index) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[index].clansman.clansman.clansmanId;
    }

    function _submitUpgradeBatch(address owner, uint32 clanId, uint256 count) internal returns (OrderResult[] memory) {
        Clan memory clan = world.getClan(clanId);
        ClanOrder[] memory orders = new ClanOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = ClanOrder({
                clansmanId: _csAt(clanId, i),
                gotoRegion: clan.baseRegion,
                action: ActionType.UpgradeMonument,
                targetClanId: 0,
                marketToken: address(0),
                marketAmount: 0,
                maxGoldIn: 0
            });
        }

        vm.prank(owner);
        return world.submitClanOrders(clanId, orders);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _advanceTicks(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            _advanceTick();
        }
    }

    function _assertAllOk(OrderResult[] memory results) internal pure {
        for (uint256 i = 0; i < results.length; i++) {
            assertEq(uint8(results[i].status), uint8(StatusCode.OK), "upgrade queued");
        }
    }

    function _expectedScore(uint8 level, uint64 reachedAtTick, uint256 lootValue) internal pure returns (uint256) {
        return _expectedScore(level, reachedAtTick, lootValue, 0);
    }

    function _expectedScore(uint8 level, uint64 reachedAtTick, uint256 lootValue, uint8 wallLevel)
        internal
        pure
        returns (uint256)
    {
        uint256 maxLootComponent = (uint256(1) << 176) - 1;
        if (lootValue > maxLootComponent) {
            lootValue = maxLootComponent;
        }

        uint256 timeComponent;
        if (level > 0) {
            timeComponent = uint256(type(uint64).max) - uint256(reachedAtTick);
        }

        return (uint256(level) << 248) | (timeComponent << 184) | (lootValue << 8) | wallLevel;
    }

    function test_getClanScoreAndRankings_sortByLevelThenEarliestReachTick() public {
        uint32 clanA = _mintClan(elderA);
        uint32 clanB = _mintClan(elderB);
        uint32 clanC = _mintClan(elderC);

        world.setVault(clanA, 300e18, 100e18, 300e18, 0);
        world.setVault(clanB, 300e18, 100e18, 300e18, 0);
        world.setVault(clanC, 300e18, 100e18, 300e18, 0);

        _assertAllOk(_submitUpgradeBatch(elderA, clanA, 2));
        _assertAllOk(_submitUpgradeBatch(elderB, clanB, 1));

        _advanceTick();
        _assertAllOk(_submitUpgradeBatch(elderC, clanC, 1));
        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 1);

        (uint256 scoreA, uint64 reachedA, uint8 levelA) = world.getClanScore(clanA);
        (uint256 scoreB, uint64 reachedB, uint8 levelB) = world.getClanScore(clanB);
        (uint256 scoreC, uint64 reachedC, uint8 levelC) = world.getClanScore(clanC);

        assertEq(levelA, 2, "A level");
        assertEq(levelB, 1, "B level");
        assertEq(levelC, 1, "C level");
        assertEq(reachedA, 4, "A reached level 2");
        assertEq(reachedB, 4, "B reached level 1");
        assertEq(reachedC, 5, "C reached level 1");
        assertEq(scoreA, _expectedScore(levelA, reachedA, world.quoteLootValueRaw(clanA)), "A score");
        assertEq(scoreB, _expectedScore(levelB, reachedB, world.quoteLootValueRaw(clanB)), "B score");
        assertEq(scoreC, _expectedScore(levelC, reachedC, world.quoteLootValueRaw(clanC)), "C score");
        assertGt(scoreA, scoreB, "higher monument level wins");
        assertGt(scoreB, scoreC, "earlier reach tick wins");

        (uint32[] memory ranked, uint256[] memory scores) = world.getRankings();
        assertEq(ranked.length, 3, "ranked count");
        assertEq(scores.length, 3, "score count");
        assertEq(ranked[0], clanA, "rank 1");
        assertEq(ranked[1], clanB, "rank 2");
        assertEq(ranked[2], clanC, "rank 3");
        assertEq(scores[0], scoreA, "rank 1 score");
        assertEq(scores[1], scoreB, "rank 2 score");
        assertEq(scores[2], scoreC, "rank 3 score");
    }

    function test_getRankings_breaksExactScoreTiesByClanId() public {
        uint32 clanA = _mintClan(elderA);
        uint32 clanB = _mintClan(elderB);
        uint32 clanC = _mintClan(elderC);

        world.setVault(clanA, 100e18, 0, 100e18, 0);
        world.setVault(clanB, 100e18, 0, 100e18, 0);
        world.setVault(clanC, 100e18, 0, 100e18, 0);

        _assertAllOk(_submitUpgradeBatch(elderA, clanA, 1));
        _assertAllOk(_submitUpgradeBatch(elderB, clanB, 1));
        _assertAllOk(_submitUpgradeBatch(elderC, clanC, 1));
        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 1);

        (uint256 scoreA,,) = world.getClanScore(clanA);
        (uint256 scoreB,,) = world.getClanScore(clanB);
        (uint256 scoreC,,) = world.getClanScore(clanC);
        assertEq(scoreA, scoreB, "A/B exact tie");
        assertEq(scoreB, scoreC, "B/C exact tie");

        (uint32[] memory ranked, uint256[] memory scores) = world.getRankings();
        assertEq(ranked.length, 3, "ranked count");
        assertEq(ranked[0], clanA, "lowest clanId first");
        assertEq(ranked[1], clanB, "middle clanId second");
        assertEq(ranked[2], clanC, "highest clanId third");
        assertEq(scores[0], scoreA, "A score");
        assertEq(scores[1], scoreB, "B score");
        assertEq(scores[2], scoreC, "C score");
    }

    function test_getRankings_usesWallLevelAfterLootBeforeClanId() public {
        uint32 clanA = _mintClan(elderA);
        uint32 clanB = _mintClan(elderB);
        uint32 clanC = _mintClan(elderC);

        world.setVault(clanA, 100e18, 0, 100e18, 0);
        world.setVault(clanB, 100e18, 0, 100e18, 0);
        world.setVault(clanC, 100e18, 0, 100e18, 0);
        world.setWallLevel(clanA, 1);
        world.setWallLevel(clanB, 2);

        _assertAllOk(_submitUpgradeBatch(elderA, clanA, 1));
        _assertAllOk(_submitUpgradeBatch(elderB, clanB, 1));
        _assertAllOk(_submitUpgradeBatch(elderC, clanC, 1));
        _advanceTicks(world.getActionDuration(ActionType.UpgradeMonument) + 1);

        (uint256 scoreA, uint64 reachedA, uint8 levelA) = world.getClanScore(clanA);
        (uint256 scoreB, uint64 reachedB, uint8 levelB) = world.getClanScore(clanB);
        (uint256 scoreC, uint64 reachedC, uint8 levelC) = world.getClanScore(clanC);
        assertEq(scoreA, _expectedScore(levelA, reachedA, world.quoteLootValueRaw(clanA), 1), "A score");
        assertEq(scoreB, _expectedScore(levelB, reachedB, world.quoteLootValueRaw(clanB), 2), "B score");
        assertEq(scoreC, _expectedScore(levelC, reachedC, world.quoteLootValueRaw(clanC), 0), "C score");

        (uint32[] memory ranked,) = world.getRankings();
        assertEq(ranked[0], clanB, "highest wall wins after loot");
        assertEq(ranked[1], clanA, "next wall second");
        assertEq(ranked[2], clanC, "zero wall third");
    }
}
