// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ActionType} from "../src/IClanWorld.sol";

contract ActionTypeEnumStabilityTest is Test {
    function test_actionTypeNumericValuesAreStable() public pure {
        assertEq(uint8(ActionType.None), 0, "None");
        assertEq(uint8(ActionType.ChopWood), 1, "ChopWood");
        assertEq(uint8(ActionType.MineIron), 2, "MineIron");
        assertEq(uint8(ActionType.FishDocks), 3, "FishDocks");
        assertEq(uint8(ActionType.FishDeepSea), 4, "FishDeepSea");
        assertEq(uint8(ActionType.HarvestWheat), 5, "HarvestWheat");
        assertEq(uint8(ActionType.DepositResources), 6, "DepositResources");
        assertEq(uint8(ActionType.BuildWall), 7, "BuildWall");
        assertEq(uint8(ActionType.UpgradeBase), 8, "UpgradeBase");
        assertEq(uint8(ActionType.UpgradeMonument), 9, "UpgradeMonument");
        assertEq(uint8(ActionType.DefendBase), 10, "DefendBase");
        assertEq(uint8(ActionType.MarketBuy), 11, "MarketBuy");
        assertEq(uint8(ActionType.MarketSell), 12, "MarketSell");
        assertEq(uint8(ActionType.Wait), 13, "Wait");
        assertEq(uint8(ActionType.WithdrawResources), 14, "WithdrawResources");
    }
}
