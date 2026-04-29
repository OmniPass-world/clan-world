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

    function defenseRoll(bytes32 tickSeed, uint32 banditId, uint32 clansmanId) external pure returns (uint32) {
        return _clansmanDefenseDamageRoll(tickSeed, banditId, clansmanId);
    }
}

contract BanditAttackResolutionTest is Test {
    BanditAttackHarness world;
    address elder = address(0xA1);

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
        orders = new ClanOrder[](count);
        for (uint256 i = 0; i < count; i++) {
            orders[i] = ClanOrder({
                clansmanId: _csId(clanId, i),
                gotoRegion: clan.baseRegion,
                action: ActionType.DefendBase,
                targetClanId: 0,
                marketToken: address(0),
                marketAmount: 0,
                maxGoldIn: 0
            });
        }
    }

    function _submitDefenders(uint32 clanId, uint256 count) internal {
        ClanOrder[] memory orders = _defendOrders(clanId, count);
        vm.prank(elder);
        OrderResult[] memory results = world.submitClanOrders(clanId, orders);
        for (uint256 i = 0; i < count; i++) {
            assertEq(uint8(results[i].status), uint8(StatusCode.OK), "defender order status");
        }
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _forceAttack(uint32 clanId, uint32 strength) internal returns (uint32 banditId) {
        Clan memory clan = world.getClan(clanId);
        return world.forceAttackingBandit(clan.baseRegion, strength, clanId);
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
