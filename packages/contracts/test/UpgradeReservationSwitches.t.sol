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

    function _assertCanSwitch(ActionType first, ActionType second, uint256 wood, uint256 wheat) internal {
        uint32 clanId = _mintClan();
        uint32 csId = _firstCs(clanId);
        world.setVault(clanId, wood, 0, wheat, 100e18);

        OrderResult[] memory initial = _submit(clanId, csId, first);
        assertEq(uint8(initial[0].status), uint8(StatusCode.OK), "initial upgrade accepted");

        vm.warp(block.timestamp + ClanWorldConstants.CLANSMAN_COOLDOWN_SECONDS + 1);
        OrderResult[] memory replacement = _submit(clanId, csId, second);
        assertEq(uint8(replacement[0].status), uint8(StatusCode.OK), "cross-type replacement accepted");
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
