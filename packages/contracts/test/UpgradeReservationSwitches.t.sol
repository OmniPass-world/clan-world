// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {ClanWorldConstants, Clan, ClanOrder, OrderResult, StatusCode, ActionType} from "../src/IClanWorld.sol";

contract UpgradeReservationSwitchHarness is ClanWorld {
    function setVault(uint32 clanId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }

    function getWallReservation(uint32 csId) external view returns (bool active, uint8 fromLevel) {
        WallUpgradeReservation storage r = _wallUpgradeReservations[csId];
        return (r.active, r.fromLevel);
    }

    function getBaseReservation(uint32 csId) external view returns (bool active, uint8 fromLevel) {
        BaseUpgradeReservation storage r = _baseUpgradeReservations[csId];
        return (r.active, r.fromLevel);
    }

    function getMonumentReservation(uint32 csId) external view returns (bool active, uint8 fromLevel) {
        MonumentUpgradeReservation storage r = _monumentUpgradeReservations[csId];
        return (r.active, r.fromLevel);
    }
}

contract UpgradeReservationSwitchesTest is Test {
    UpgradeReservationSwitchHarness world;
    address elder = address(0xA1);

    function setUp() public {
        world = new UpgradeReservationSwitchHarness();
    }

    function _mintClan() internal returns (uint32 clanId) {
        vm.prank(elder);
        (clanId,) = world.mintClan(elder);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    function _submit(uint32 clanId, uint32 csId, ActionType action) internal returns (OrderResult[] memory) {
        Clan memory clan = world.getClan(clanId);
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: csId,
            gotoRegion: clan.baseRegion,
            action: action,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0
        });

        vm.prank(elder);
        return world.submitClanOrders(clanId, orders);
    }

    /// @dev Returns (active, fromLevel) for the reservation corresponding to `action`.
    function _getReservation(uint32 csId, ActionType action) internal view returns (bool active, uint8 fromLevel) {
        if (action == ActionType.UpgradeWall) return world.getWallReservation(csId);
        if (action == ActionType.UpgradeBase) return world.getBaseReservation(csId);
        if (action == ActionType.UpgradeMonument) return world.getMonumentReservation(csId);
        revert("unknown action");
    }

    /// @dev Returns the expected fromLevel for a fresh clan (level at queue time).
    ///      wallLevel starts at 0, baseLevel starts at 1, monumentLevel starts at 0.
    function _initialFromLevel(ActionType action) internal pure returns (uint8) {
        if (action == ActionType.UpgradeWall) return 0;
        if (action == ActionType.UpgradeBase) return 1;
        if (action == ActionType.UpgradeMonument) return 0;
        revert("unknown action");
    }

    function _assertCanSwitch(ActionType first, ActionType second, uint256 wood, uint256 wheat) internal {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, wood, 0, wheat, 100e18);

        // Submit first reservation
        OrderResult[] memory initial = _submit(clanId, csId, first);
        assertEq(uint8(initial[0].status), uint8(StatusCode.OK), "initial upgrade accepted");

        // Assert first reservation is active with correct fromLevel
        (bool firstActive, uint8 firstFromLevel) = _getReservation(csId, first);
        assertTrue(firstActive, "first reservation active after initial submit");
        assertEq(firstFromLevel, _initialFromLevel(first), "first reservation fromLevel");

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);

        // Submit cross-type replacement
        OrderResult[] memory replacement = _submit(clanId, csId, second);
        assertEq(uint8(replacement[0].status), uint8(StatusCode.OK), "cross-type replacement accepted");

        // Old reservation must be cleared
        (bool oldActive,) = _getReservation(csId, first);
        assertFalse(oldActive, "old reservation cleared after switch");

        // New reservation must be active
        (bool newActive, uint8 newFromLevel) = _getReservation(csId, second);
        assertTrue(newActive, "new reservation active after switch");
        assertEq(newFromLevel, _initialFromLevel(second), "new reservation fromLevel");
    }

    function test_upgradeWallCanSwitchToBaseWithTightResources() public {
        _assertCanSwitch(ActionType.UpgradeWall, ActionType.UpgradeBase, 40e18, 20e18);
    }

    function test_upgradeWallCanSwitchToMonumentWithTightResources() public {
        _assertCanSwitch(ActionType.UpgradeWall, ActionType.UpgradeMonument, 30e18, 20e18);
    }

    function test_upgradeBaseCanSwitchToWallWithTightResources() public {
        _assertCanSwitch(ActionType.UpgradeBase, ActionType.UpgradeWall, 40e18, 20e18);
    }

    function test_upgradeBaseCanSwitchToMonumentWithTightResources() public {
        _assertCanSwitch(ActionType.UpgradeBase, ActionType.UpgradeMonument, 40e18, 20e18);
    }

    function test_upgradeMonumentCanSwitchToWallWithTightResources() public {
        _assertCanSwitch(ActionType.UpgradeMonument, ActionType.UpgradeWall, 30e18, 20e18);
    }

    function test_upgradeMonumentCanSwitchToBaseWithTightResources() public {
        _assertCanSwitch(ActionType.UpgradeMonument, ActionType.UpgradeBase, 40e18, 20e18);
    }
}
