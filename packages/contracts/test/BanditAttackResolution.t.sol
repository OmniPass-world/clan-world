// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    ClanWorldConstants,
    ClanState,
    ClansmanState,
    BanditState,
    ActionType,
    StatusCode,
    Clan,
    Mission,
    ClanOrder,
    OrderResult
} from "../src/IClanWorld.sol";

contract BanditAttackHarness is ClanWorld {
    function forceAttackingBandit(uint8 region, uint32 strength, uint32 targetClanId) external returns (uint32 id) {
        id = _spawnBandit(region, strength);
        _bandits[id].state = BanditState.Attacking;
        _bandits[id].targetClanId = targetClanId;
    }

    function setWallLevel(uint32 clanId, uint8 wallLevel) external {
        _clans[clanId].wallLevel = wallLevel;
    }

    function setStarvationStartsAt(uint32 clanId, uint64 tick) external {
        _clans[clanId].starvationStartsAtTick = tick;
    }

    function setBanditStrength(uint32 banditId, uint32 strength) external {
        _bandits[banditId].strength = strength;
    }

    function setBanditCarry(uint32 banditId, uint256 wood, uint256 wheat, uint256 fish, uint256 iron, uint256 gold)
        external
    {
        _bandits[banditId].carryWood = wood;
        _bandits[banditId].carryWheat = wheat;
        _bandits[banditId].carryFish = fish;
        _bandits[banditId].carryIron = iron;
        _bandits[banditId].carryGold = gold;
    }

    function defenseRoll(bytes32 tickSeed, uint32 banditId, uint32 clansmanId) external pure returns (uint32) {
        return _clansmanDefenseDamageRoll(tickSeed, banditId, clansmanId);
    }
}

contract BanditAttackResolutionTest is Test {
    BanditAttackHarness world;
    address elder = address(0xA1);

    event BanditAttackResolved(
        uint32 indexed banditId,
        uint32 indexed targetClanId,
        bool defended,
        uint16 attackPower,
        uint16 totalDefense,
        uint16 wallLevelAfter,
        uint256 stolenWood,
        uint256 stolenIron,
        uint256 stolenWheat,
        uint256 stolenFish,
        uint64 atTick
    );
    event BanditDefeated(uint32 indexed banditId, uint32 indexed targetClanId, uint64 atTick);
    event BlueprintEarned(uint32 indexed clanId, uint32 indexed banditId, uint64 tick);
    event LootDistributed(
        uint32 indexed banditId,
        uint32[] clanIdsRewarded,
        uint256 perClanWood,
        uint256 perClanWheat,
        uint256 perClanFish,
        uint256 perClanIron,
        uint256 perClanGold,
        uint256 burnedWood,
        uint256 burnedWheat,
        uint256 burnedFish,
        uint256 burnedIron,
        uint256 burnedGold
    );

    function setUp() public {
        world = new BanditAttackHarness();
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
    }

    function _csId(uint32 clanId, uint256 index) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[index].clansman.clansman.clansmanId;
    }

    function _defendOrders(uint32 clanId, uint256 count) internal view returns (ClanOrder[] memory orders) {
        Clan memory clan = world.getClan(clanId);
        return _defendTargetOrders(clanId, clanId, clan.baseRegion, count);
    }

    function _defendTargetOrders(uint32 clanId, uint32 targetClanId, uint8 targetRegion, uint256 count)
        internal
        view
        returns (ClanOrder[] memory orders)
    {
        orders = new ClanOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = ClanOrder({
                clansmanId: _csId(clanId, i),
                gotoRegion: targetRegion,
                action: ActionType.DefendBase,
                targetClanId: targetClanId,
                marketToken: address(0),
                marketAmount: 0,
                maxGoldIn: 0
            });
        }
    }

    function _submitDefenders(uint32 clanId, uint256 count) internal {
        _submitTargetDefenders(clanId, clanId, count);
    }

    function _submitTargetDefenders(uint32 defenderClanId, uint32 targetClanId, uint256 count)
        internal
        returns (uint64 maxExecutesAtTick)
    {
        Clan memory targetClan = world.getClan(targetClanId);
        ClanOrder[] memory orders = _defendTargetOrders(defenderClanId, targetClanId, targetClan.baseRegion, count);
        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(defenderClanId, orders);
        for (uint256 i = 0; i < count; i++) {
            assertEq(uint8(results[i].status), uint8(StatusCode.OK), "defender order status");
            Mission memory mission = world.getActiveMission(orders[i].clansmanId);
            if (mission.executesAtTick > maxExecutesAtTick) {
                maxExecutesAtTick = mission.executesAtTick;
            }
        }
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _advanceUntilAfter(uint64 tick) internal {
        while (world.getWorldState().currentTick <= tick) {
            _advanceTick();
        }
    }

    function _activateTargetDefenders(uint32 targetClanId, uint32[] memory defenderClanIds, uint256 countEach)
        internal
    {
        uint64 maxExecutesAtTick;
        for (uint256 i = 0; i < defenderClanIds.length; i++) {
            uint64 executesAtTick = _submitTargetDefenders(defenderClanIds[i], targetClanId, countEach);
            if (executesAtTick > maxExecutesAtTick) {
                maxExecutesAtTick = executesAtTick;
            }
        }

        _advanceUntilAfter(maxExecutesAtTick);
        for (uint256 i = 0; i < defenderClanIds.length; i++) {
            world.settleClan(defenderClanIds[i]);
        }
    }

    function _forceAttack(uint32 clanId, uint32 strength) internal returns (uint32 banditId) {
        Clan memory clan = world.getClan(clanId);
        return world.forceAttackingBandit(clan.baseRegion, strength, clanId);
    }

    function _mintClans(uint256 count) internal returns (uint32[] memory clanIds) {
        clanIds = new uint32[](count);
        for (uint256 i = 0; i < count; i++) {
            clanIds[i] = _mintClan();
        }
    }

    function test_defeatedBanditLootSingleDefendingClanGetsFullCarry() public {
        uint32 clanId = _mintClan();
        uint32[] memory defenders = new uint32[](1);
        defenders[0] = clanId;
        _activateTargetDefenders(clanId, defenders, 4);

        Clan memory beforeClan = world.getClan(clanId);
        uint32 banditId = _forceAttack(clanId, 1);
        world.setBanditCarry(banditId, 7e18, 11e18, 13e18, 17e18, 19e18);
        world.setBanditStrength(banditId, 0);

        _advanceTick();

        Clan memory afterClan = world.getClan(clanId);
        assertEq(afterClan.vaultWood, beforeClan.vaultWood + 7e18, "wood full carry");
        assertEq(afterClan.vaultWheat, beforeClan.vaultWheat + 11e18, "wheat full carry");
        assertEq(afterClan.vaultFish, beforeClan.vaultFish + 13e18, "fish full carry");
        assertEq(afterClan.vaultIron, beforeClan.vaultIron + 17e18, "iron full carry");
        assertEq(afterClan.goldBalance, beforeClan.goldBalance + 19e18, "gold full carry");
        assertEq(world.getBandit(banditId).id, 0, "defeated bandit deleted");
    }

    function test_defeatedBanditAwardsBlueprintToTargetClan() public {
        uint32 clanId = _mintClan();
        uint32[] memory defenders = new uint32[](1);
        defenders[0] = clanId;
        _activateTargetDefenders(clanId, defenders, 4);

        uint256 blueprintBefore = world.getClan(clanId).blueprintBalance;
        uint32 banditId = _forceAttack(clanId, 1);
        world.setBanditStrength(banditId, 0);

        vm.expectEmit(true, true, false, true, address(world));
        emit BlueprintEarned(clanId, banditId, world.getWorldState().currentTick);

        _advanceTick();

        assertEq(world.getClan(clanId).blueprintBalance, blueprintBefore + 1, "target blueprint awarded");
    }

    function test_defeatedBanditLootSplitsEquallyAcrossFourDefendingClans() public {
        uint32[] memory clanIds = _mintClans(4);
        _activateTargetDefenders(clanIds[0], clanIds, 1);

        uint256[4] memory woodBefore;
        uint256[4] memory wheatBefore;
        uint256[4] memory fishBefore;
        uint256[4] memory ironBefore;
        uint256[4] memory goldBefore;
        for (uint256 i = 0; i < clanIds.length; i++) {
            Clan memory clan = world.getClan(clanIds[i]);
            woodBefore[i] = clan.vaultWood;
            wheatBefore[i] = clan.vaultWheat;
            fishBefore[i] = clan.vaultFish;
            ironBefore[i] = clan.vaultIron;
            goldBefore[i] = clan.goldBalance;
        }

        uint32 banditId = _forceAttack(clanIds[0], 1);
        world.setBanditCarry(banditId, 100e18, 100e18, 100e18, 100e18, 100e18);
        world.setBanditStrength(banditId, 0);

        _advanceTick();

        for (uint256 i = 0; i < clanIds.length; i++) {
            Clan memory clan = world.getClan(clanIds[i]);
            assertEq(clan.vaultWood, woodBefore[i] + 25e18, "wood share");
            assertEq(clan.vaultWheat, wheatBefore[i] + 25e18, "wheat share");
            assertEq(clan.vaultFish, fishBefore[i] + 25e18, "fish share");
            assertEq(clan.vaultIron, ironBefore[i] + 25e18, "iron share");
            assertEq(clan.goldBalance, goldBefore[i] + 25e18, "gold share");
        }
    }

    function test_mixedClanDefenseAwardsBlueprintOnlyToBaseOwner() public {
        uint32[] memory clanIds = _mintClans(4);
        _activateTargetDefenders(clanIds[0], clanIds, 1);

        uint256[4] memory blueprintBefore;
        for (uint256 i = 0; i < clanIds.length; i++) {
            blueprintBefore[i] = world.getClan(clanIds[i]).blueprintBalance;
        }

        uint32 banditId = _forceAttack(clanIds[0], 1);
        world.setBanditStrength(banditId, 0);

        _advanceTick();

        assertEq(world.getClan(clanIds[0]).blueprintBalance, blueprintBefore[0] + 1, "base owner blueprint");
        for (uint256 i = 1; i < clanIds.length; i++) {
            assertEq(world.getClan(clanIds[i]).blueprintBalance, blueprintBefore[i], "helper clan no blueprint");
        }
    }

    function test_multipleDefeatedBanditsEachAwardBlueprint() public {
        uint32 clanId = _mintClan();
        uint32[] memory defenders = new uint32[](1);
        defenders[0] = clanId;
        _activateTargetDefenders(clanId, defenders, 4);

        uint256 blueprintBefore = world.getClan(clanId).blueprintBalance;
        uint32 firstBanditId = _forceAttack(clanId, 1);
        uint32 secondBanditId = _forceAttack(clanId, 1);
        world.setBanditStrength(firstBanditId, 0);
        world.setBanditStrength(secondBanditId, 0);

        _advanceTick();

        assertEq(world.getClan(clanId).blueprintBalance, blueprintBefore + 2, "one blueprint per defeated bandit");
    }

    function test_defeatedBanditLootBurnsWholeTokenOverflowAcrossThreeDefendingClans() public {
        uint32[] memory clanIds = _mintClans(3);
        _activateTargetDefenders(clanIds[0], clanIds, 1);

        uint256 woodBeforeTotal;
        uint256 goldBeforeTotal;
        for (uint256 i = 0; i < clanIds.length; i++) {
            Clan memory clan = world.getClan(clanIds[i]);
            woodBeforeTotal += clan.vaultWood;
            goldBeforeTotal += clan.goldBalance;
        }

        uint32 banditId = _forceAttack(clanIds[0], 1);
        world.setBanditCarry(banditId, 100e18, 100e18, 100e18, 100e18, 100e18);
        world.setBanditStrength(banditId, 0);

        vm.expectEmit(true, true, false, false, address(world));
        emit BanditAttackResolved(banditId, clanIds[0], true, 0, 0, 0, 0, 0, 0, 0, world.getWorldState().currentTick);
        vm.expectEmit(true, true, false, true, address(world));
        emit BanditDefeated(banditId, clanIds[0], world.getWorldState().currentTick);
        vm.expectEmit(true, false, false, true, address(world));
        emit LootDistributed(banditId, clanIds, 33e18, 33e18, 33e18, 33e18, 33e18, 1e18, 1e18, 1e18, 1e18, 1e18);

        _advanceTick();

        uint256 woodAfterTotal;
        uint256 goldAfterTotal;
        for (uint256 i = 0; i < clanIds.length; i++) {
            Clan memory clan = world.getClan(clanIds[i]);
            assertEq(clan.vaultWood, 20e18 + 33e18, "wood share");
            assertEq(clan.goldBalance, 3e18 + 33e18, "gold share");
            woodAfterTotal += clan.vaultWood;
            goldAfterTotal += clan.goldBalance;
        }
        assertEq(woodAfterTotal - woodBeforeTotal, 99e18, "wood overflow burned");
        assertEq(goldAfterTotal - goldBeforeTotal, 99e18, "gold overflow burned");
    }

    function test_multipleDefendersFromSameClanStillReceiveOneClanShare() public {
        uint32[] memory clanIds = _mintClans(2);
        uint64 firstExecutesAtTick = _submitTargetDefenders(clanIds[0], clanIds[0], 3);
        uint64 secondExecutesAtTick = _submitTargetDefenders(clanIds[1], clanIds[0], 1);
        _advanceUntilAfter(firstExecutesAtTick > secondExecutesAtTick ? firstExecutesAtTick : secondExecutesAtTick);
        world.settleClan(clanIds[0]);
        world.settleClan(clanIds[1]);

        uint256 targetWoodBefore = world.getClan(clanIds[0]).vaultWood;
        uint256 helperWoodBefore = world.getClan(clanIds[1]).vaultWood;
        uint32 banditId = _forceAttack(clanIds[0], 1);
        world.setBanditCarry(banditId, 100e18, 100e18, 100e18, 100e18, 100e18);
        world.setBanditStrength(banditId, 0);

        _advanceTick();

        assertEq(world.getClan(clanIds[0]).vaultWood, targetWoodBefore + 50e18, "target clan one share");
        assertEq(world.getClan(clanIds[1]).vaultWood, helperWoodBefore + 50e18, "helper clan one share");
    }

    function test_escapedBanditDoesNotDistributeCarry() public {
        uint32 clanId = _mintClan();
        Clan memory beforeClan = world.getClan(clanId);
        uint32 banditId = _forceAttack(clanId, 100);
        world.setBanditCarry(banditId, 100e18, 100e18, 100e18, 100e18, 100e18);

        _advanceTick();

        Clan memory afterClan = world.getClan(clanId);
        assertEq(afterClan.vaultWood, beforeClan.vaultWood, "wood unchanged");
        assertEq(afterClan.vaultWheat, beforeClan.vaultWheat, "wheat unchanged");
        assertEq(afterClan.vaultFish, beforeClan.vaultFish, "fish unchanged");
        assertEq(afterClan.vaultIron, beforeClan.vaultIron, "iron unchanged");
        assertEq(afterClan.goldBalance, beforeClan.goldBalance, "gold unchanged");
        assertEq(uint8(world.getBandit(banditId).state), uint8(BanditState.Escaped), "bandit escaped");
    }

    function test_escapedBanditDoesNotAwardBlueprint() public {
        uint32 clanId = _mintClan();
        uint256 blueprintBefore = world.getClan(clanId).blueprintBalance;
        uint32 banditId = _forceAttack(clanId, 100);

        _advanceTick();

        assertEq(world.getClan(clanId).blueprintBalance, blueprintBefore, "blueprint unchanged");
        assertEq(uint8(world.getBandit(banditId).state), uint8(BanditState.Escaped), "bandit escaped");
    }

    function test_twoAliveDefendersWithSufficientDefenseDefeatBanditWithoutWallChip() public {
        uint32 clanId = _mintClan();
        _submitDefenders(clanId, 2);
        world.setWallLevel(clanId, 1);

        uint32 banditId = _forceAttack(clanId, 1);
        bytes32 tickSeed = world.getWorldState().currentTickSeed;
        uint32 defense = world.defenseRoll(tickSeed, banditId, _csId(clanId, 0))
            + world.defenseRoll(tickSeed, banditId, _csId(clanId, 1));
        uint32 strength = defense / 2;
        if (strength == 0) strength = 1;
        world.setBanditStrength(banditId, strength);
        _advanceTick();

        assertEq(uint8(world.getBandit(banditId).state), uint8(BanditState.None), "defeated bandit deleted");
        assertEq(world.getClan(clanId).wallLevel, 1, "wall was not chipped");
        assertEq(world.getClan(clanId).livingClansmen, 4, "no casualties");
    }

    function test_weakDefenseChipsWallOneLevel() public {
        uint32 clanId = _mintClan();
        world.setWallLevel(clanId, 1);
        uint32 banditId = _forceAttack(clanId, 100);

        _advanceTick();

        assertEq(world.getClan(clanId).wallLevel, 0, "wall level decreased");
        assertEq(world.getClan(clanId).livingClansmen, 4, "wall absorbed full hit");
        assertEq(uint8(world.getBandit(banditId).state), uint8(BanditState.Escaped), "bandit escaped");
    }

    function test_wallZeroWeakDefenseKillsClansmanDeterministically() public {
        uint32 clanId = _mintClan();
        uint32 banditId = _forceAttack(clanId, 100);

        _advanceTick();

        assertEq(world.getClan(clanId).livingClansmen, 3, "one clansman died");
        assertEq(uint8(world.getBandit(banditId).state), uint8(BanditState.Escaped), "bandit escaped");
    }

    function test_allClansmenDeadLeavesClanActiveButVulnerable() public {
        uint32 clanId = _mintClan();
        _forceAttack(clanId, 425);

        _advanceTick();

        Clan memory clan = world.getClan(clanId);
        assertEq(clan.livingClansmen, 0, "all clansmen dead");
        assertEq(uint8(clan.clanState), uint8(ClanState.ACTIVE), "phase 10.5 handles elimination");
    }

    function test_starvingDefenderContributesZeroDefense() public {
        uint32 clanId = _mintClan();
        _submitDefenders(clanId, 1);
        _advanceTick();
        world.settleClan(clanId);
        world.setWallLevel(clanId, 1);
        world.setStarvationStartsAt(clanId, 1);

        uint32 banditId = _forceAttack(clanId, 100);
        uint32 nonStarvingRoll =
            world.defenseRoll(world.getWorldState().currentTickSeed, banditId, _csId(clanId, 0));
        assertGt(nonStarvingRoll, 0, "test setup needs nonzero roll");

        _advanceTick();

        assertEq(world.getClan(clanId).wallLevel, 0, "starving defender did not reduce incoming wall hit");
        assertEq(world.getClan(clanId).livingClansmen, 4, "wall absorbed full hit");
    }

    function test_twoAttacksSameTickDeterminismAcrossReplay() public {
        BanditAttackHarness a = new BanditAttackHarness();
        BanditAttackHarness b = new BanditAttackHarness();

        uint32 aFirst;
        uint32 aSecond;
        uint32 bFirst;
        uint32 bSecond;
        (aFirst, aSecond) = _setupTwoAttackWorld(a);
        (bFirst, bSecond) = _setupTwoAttackWorld(b);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        a.heartbeat();
        b.heartbeat();

        assertEq(a.getClan(aFirst).livingClansmen, b.getClan(bFirst).livingClansmen, "first target deterministic");
        assertEq(a.getClan(aSecond).livingClansmen, b.getClan(bSecond).livingClansmen, "second target deterministic");
        assertEq(uint8(a.getBandit(1).state), uint8(b.getBandit(1).state), "first bandit state deterministic");
        assertEq(uint8(a.getBandit(2).state), uint8(b.getBandit(2).state), "second bandit state deterministic");
    }

    function _setupTwoAttackWorld(BanditAttackHarness target) internal returns (uint32 firstClanId, uint32 secondClanId) {
        vm.prank(elder);
        (firstClanId,) = target.mintClan(elder);
        vm.prank(elder);
        (secondClanId,) = target.mintClan(elder);

        target.forceAttackingBandit(target.getClan(firstClanId).baseRegion, 100, firstClanId);
        target.forceAttackingBandit(target.getClan(secondClanId).baseRegion, 100, secondClanId);
    }
}
