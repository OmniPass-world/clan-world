// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {
    ClanWorldConstants,
    ClanState,
    ClansmanState,
    ResourceType,
    ActionType,
    StatusCode,
    ClanOrder,
    WithdrawResourcesData,
    OrderResult
} from "../src/IClanWorld.sol";

/// @dev Harness that exposes storage manipulation for tests.
contract DirectTransferHarness is ClanWorld {
    function setGoldBalance(uint32 clanId, uint256 amount) external {
        _clans[clanId].goldBalance = amount;
    }

    function setBlueprintBalance(uint32 clanId, uint256 amount) external {
        _clans[clanId].blueprintBalance = amount;
    }

    function setVaultBalances(uint32 clanId, uint256 wood, uint256 iron, uint256 wheat, uint256 fish) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
    }

    function setWallLevel(uint32 clanId, uint8 wallLevel) external {
        _clans[clanId].wallLevel = wallLevel;
    }

    function setMonumentLevel(uint32 clanId, uint8 monumentLevel) external {
        _clans[clanId].monumentLevel = monumentLevel;
    }

    function killClan(uint32 clanId) external {
        _clans[clanId].clanState = ClanState.DEAD;
    }

    /// @dev Set when starvation started (for settlement death scenario).
    function setClanStarvationStartsAtTick(uint32 clanId, uint64 starvedAtTick) external {
        _clans[clanId].starvationStartsAtTick = starvedAtTick;
    }

    /// @dev Set when clan was last settled (so _settleClan re-processes unsettled ticks).
    function setClanLastSettledTick(uint32 clanId, uint64 tick) external {
        _clans[clanId].lastSettledTick = tick;
    }

    /// @dev Kill a clansman by ID (for reducing living count to 1).
    function killClansman(uint32 clansmanId) external {
        if (_clansmen[clansmanId].state != ClansmanState.DEAD) {
            _clansmen[clansmanId].state = ClansmanState.DEAD;
            uint32 clanId = _clansmen[clansmanId].clanId;
            if (_clans[clanId].livingClansmen > 0) {
                _clans[clanId].livingClansmen--;
            }
        }
    }
}

contract DirectTransfersTest is Test {
    DirectTransferHarness world;

    address owner1 = address(0xA1);
    address owner2 = address(0xA2);
    address stranger = address(0xBB);

    uint32 clan1;
    uint32 clan2;

    function setUp() public {
        world = new DirectTransferHarness();

        vm.prank(owner1);
        (clan1,) = world.mintClan(owner1);

        vm.prank(owner2);
        (clan2,) = world.mintClan(owner2);
    }

    function _firstCs(uint32 clanId) internal view returns (uint32) {
        return world.getClanFullView(clanId).clansmen[0].clansman.clansman.clansmanId;
    }

    function _queueUpgrade(ActionType action) internal returns (OrderResult[] memory) {
        ClanOrder[] memory orders = new ClanOrder[](1);
        orders[0] = ClanOrder({
            clansmanId: _firstCs(clan1),
            gotoRegion: world.getClan(clan1).baseRegion,
            action: action,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        vm.prank(owner1);
        return world.submitClanOrders(clan1, orders);
    }

    // =========================================================================
    // transferGold
    // =========================================================================

    function test_transferGold_happy_path() public {
        uint256 amount = 1e18;
        uint256 from0 = world.getClan(clan1).goldBalance;
        uint256 to0 = world.getClan(clan2).goldBalance;

        vm.expectEmit(true, true, false, true);
        emit GoldTransferred(clan1, clan2, amount, world.getWorldState().currentTick);

        vm.prank(owner1);
        world.transferGold(clan1, clan2, amount);

        assertEq(world.getClan(clan1).goldBalance, from0 - amount, "from deducted");
        assertEq(world.getClan(clan2).goldBalance, to0 + amount, "to credited");
    }

    function test_transferGold_wrong_caller_reverts() public {
        vm.prank(stranger);
        vm.expectRevert("ClanWorld: not clan owner");
        world.transferGold(clan1, clan2, 1e18);
    }

    function test_transferGold_same_clan_reverts() public {
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: same clan");
        world.transferGold(clan1, clan1, 1e18);
    }

    function test_transferGold_zero_amount_reverts() public {
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: zero amount");
        world.transferGold(clan1, clan2, 0);
    }

    function test_transferGold_insufficient_balance_reverts() public {
        world.setGoldBalance(clan1, 1e17);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient gold");
        world.transferGold(clan1, clan2, 1e18);
    }

    function test_transferGold_dead_sender_reverts() public {
        world.killClan(clan1);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferGold(clan1, clan2, 1e18);
    }

    function test_transferGold_dead_recipient_allowed() public {
        uint256 amount = 1e18;
        uint256 to0 = world.getClan(clan2).goldBalance;
        world.killClan(clan2);
        vm.prank(owner1);
        world.transferGold(clan1, clan2, amount);
        assertEq(world.getClan(clan2).goldBalance, to0 + amount, "dead recipient receives gold");
    }

    function test_transferGold_after_ownership_transfer_old_owner_blocked() public {
        vm.prank(owner1);
        world.transferClanOwnership(clan1, owner2);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: not clan owner");
        world.transferGold(clan1, clan2, 1e18);
    }

    function test_transferGold_ignoresVaultReservations() public {
        world.setVaultBalances(clan1, 20e18, 0, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        uint256 from0 = world.getClan(clan1).goldBalance;
        uint256 to0 = world.getClan(clan2).goldBalance;

        vm.prank(owner1);
        world.transferGold(clan1, clan2, 1e18);

        assertEq(world.getClan(clan1).goldBalance, from0 - 1e18, "gold debited");
        assertEq(world.getClan(clan2).goldBalance, to0 + 1e18, "gold credited");
    }

    // =========================================================================
    // transferVaultResource
    // =========================================================================

    function test_transferVaultResource_wood_happy_path() public {
        uint256 amount = 5e18;
        uint256 from0 = world.getClan(clan1).vaultWood;
        uint256 to0 = world.getClan(clan2).vaultWood;
        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, amount);
        assertEq(world.getClan(clan1).vaultWood, from0 - amount);
        assertEq(world.getClan(clan2).vaultWood, to0 + amount);
    }

    function test_transferVaultResource_iron_happy_path() public {
        world.setVaultBalances(clan1, 0, 50e18, 0, 0);
        uint256 amount = 25e18;
        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Iron, amount);
        // iron starts at 0 for clan2, so absolute check is fine
        assertEq(world.getClan(clan1).vaultIron, 25e18);
        assertEq(world.getClan(clan2).vaultIron, 25e18);
    }

    function test_transferVaultResource_wheat_happy_path() public {
        uint256 amount = 5e18;
        uint256 from0 = world.getClan(clan1).vaultWheat;
        uint256 to0 = world.getClan(clan2).vaultWheat;
        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Wheat, amount);
        assertEq(world.getClan(clan1).vaultWheat, from0 - amount);
        assertEq(world.getClan(clan2).vaultWheat, to0 + amount);
    }

    function test_transferVaultResource_fish_happy_path() public {
        uint256 amount = 1e18;
        uint256 from0 = world.getClan(clan1).vaultFish;
        uint256 to0 = world.getClan(clan2).vaultFish;
        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Fish, amount);
        assertEq(world.getClan(clan1).vaultFish, from0 - amount);
        assertEq(world.getClan(clan2).vaultFish, to0 + amount);
    }

    function test_transferVaultResource_wrong_caller_reverts() public {
        vm.prank(stranger);
        vm.expectRevert("ClanWorld: not clan owner");
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, 1e18);
    }

    function test_transferVaultResource_insufficient_reverts() public {
        world.setVaultBalances(clan1, 1e17, 0, 0, 0);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient wood");
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, 1e18);
    }

    function test_transferVaultResource_dead_sender_reverts() public {
        world.killClan(clan1);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, 1e18);
    }

    function test_transferVaultResource_dead_recipient_allowed() public {
        uint256 amount = 5e18;
        uint256 to0 = world.getClan(clan2).vaultWood;
        world.killClan(clan2);
        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, amount);
        assertEq(world.getClan(clan2).vaultWood, to0 + amount);
    }

    function test_transferVaultResource_invalid_resource_reverts() public {
        vm.prank(owner1);
        (bool ok,) = address(world)
            .call(abi.encodeWithSelector(world.transferVaultResource.selector, clan1, clan2, uint8(99), uint256(1e18)));
        assertFalse(ok, "invalid enum value must revert");
    }

    function test_transferVaultResource_woodReservedByUpgrade_reverts() public {
        world.setVaultBalances(clan1, 20e18, 0, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient wood");
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, 1e18);
    }

    function test_transferVaultResource_ironReservedByUpgrade_reverts() public {
        world.setWallLevel(clan1, 2);
        world.setVaultBalances(clan1, 30e18, 5e18, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient iron");
        world.transferVaultResource(clan1, clan2, ResourceType.Iron, 1e18);
    }

    function test_transferVaultResource_wheatReservedByUpgrade_reverts() public {
        world.setVaultBalances(clan1, 40e18, 0, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeBase);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient wheat");
        world.transferVaultResource(clan1, clan2, ResourceType.Wheat, 1e18);
    }

    function test_transferVaultResource_fishIgnoresUpgradeReservations() public {
        world.setVaultBalances(clan1, 20e18, 0, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Fish, 1e18);

        assertEq(world.getClan(clan1).vaultFish, 1e18, "fish debited");
        assertEq(world.getClan(clan2).vaultFish, 3e18, "fish credited");
    }

    function test_transferVaultResource_reservedWoodAllowsSurplusTransfer() public {
        world.setVaultBalances(clan1, 50e18, 0, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, 25e18);

        assertEq(world.getClan(clan1).vaultWood, 25e18, "surplus wood transferred");
        assertEq(world.getClan(clan2).vaultWood, 45e18, "recipient credited");
    }

    // =========================================================================
    // transferBlueprint
    // =========================================================================

    function test_transferBlueprint_happy_path() public {
        world.setBlueprintBalance(clan1, 10e18);
        vm.expectEmit(true, true, false, true);
        emit BlueprintTransferred(clan1, clan2, 5e18, world.getWorldState().currentTick);
        vm.prank(owner1);
        world.transferBlueprint(clan1, clan2, 5e18);
        assertEq(world.getClan(clan1).blueprintBalance, 5e18);
        assertEq(world.getClan(clan2).blueprintBalance, 5e18);
    }

    function test_transferBlueprint_zero_amount_reverts() public {
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: zero amount");
        world.transferBlueprint(clan1, clan2, 0);
    }

    function test_transferBlueprint_wrong_caller_reverts() public {
        world.setBlueprintBalance(clan1, 10e18);
        vm.prank(stranger);
        vm.expectRevert("ClanWorld: not clan owner");
        world.transferBlueprint(clan1, clan2, 5e18);
    }

    function test_transferBlueprint_insufficient_reverts() public {
        world.setBlueprintBalance(clan1, 2e18);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient blueprints");
        world.transferBlueprint(clan1, clan2, 5e18);
    }

    function test_transferBlueprint_dead_sender_reverts() public {
        world.setBlueprintBalance(clan1, 10e18);
        world.killClan(clan1);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferBlueprint(clan1, clan2, 5e18);
    }

    function test_transferBlueprint_reservedByUpgrade_reverts() public {
        world.setMonumentLevel(clan1, 6);
        world.setVaultBalances(clan1, 200e18, 25e18, 100e18, 2e18);
        world.setBlueprintBalance(clan1, 1e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeMonument);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient blueprints");
        world.transferBlueprint(clan1, clan2, 1e18);
    }

    function test_transferBlueprint_reservedByUpgradeAllowsSurplusTransfer() public {
        world.setMonumentLevel(clan1, 6);
        world.setVaultBalances(clan1, 200e18, 25e18, 100e18, 2e18);
        world.setBlueprintBalance(clan1, 3e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeMonument);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        world.transferBlueprint(clan1, clan2, 2e18);

        assertEq(world.getClan(clan1).blueprintBalance, 1e18, "surplus blueprints transferred");
        assertEq(world.getClan(clan2).blueprintBalance, 2e18, "recipient credited");
    }

    // =========================================================================
    // transferBundle
    // =========================================================================

    function test_transferBundle_happy_path_multi_component() public {
        world.setBlueprintBalance(clan1, 10e18);
        // Use known starting values (from mintClan: gold=3e18, wood=20e18, wheat=20e18, fish=2e18, iron=0, bp=0)
        // After setBlueprintBalance clan1 has bp=10e18
        // Transfer: gold=1e18, bp=2e18, wood=5e18, iron=0, wheat=5e18, fish=1e18
        uint256 g0_1 = world.getClan(clan1).goldBalance;
        uint256 w0_1 = world.getClan(clan1).vaultWood;
        uint256 wh0_1 = world.getClan(clan1).vaultWheat;
        uint256 f0_1 = world.getClan(clan1).vaultFish;
        uint256 g0_2 = world.getClan(clan2).goldBalance;
        uint256 w0_2 = world.getClan(clan2).vaultWood;

        vm.prank(owner1);
        world.transferBundle(clan1, clan2, 1e18, 2e18, 5e18, 0, 5e18, 1e18);

        assertEq(world.getClan(clan1).goldBalance, g0_1 - 1e18);
        assertEq(world.getClan(clan1).blueprintBalance, 8e18);
        assertEq(world.getClan(clan1).vaultWood, w0_1 - 5e18);
        assertEq(world.getClan(clan1).vaultWheat, wh0_1 - 5e18);
        assertEq(world.getClan(clan1).vaultFish, f0_1 - 1e18);

        assertEq(world.getClan(clan2).goldBalance, g0_2 + 1e18);
        assertEq(world.getClan(clan2).blueprintBalance, 2e18);
        assertEq(world.getClan(clan2).vaultWood, w0_2 + 5e18);
    }

    function test_transferBundle_empty_reverts() public {
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: empty bundle");
        world.transferBundle(clan1, clan2, 0, 0, 0, 0, 0, 0);
    }

    function test_transferBundle_insufficient_one_component_entire_call_reverts() public {
        // Set clan1 iron = 0 explicitly (iron starts at 0 from mintClan)
        // Bundle asks for iron=50e18 which clan1 doesn't have, plus gold=1e18 which it does
        uint256 fromGold0 = world.getClan(clan1).goldBalance;
        uint256 toGold0 = world.getClan(clan2).goldBalance;
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient iron");
        world.transferBundle(clan1, clan2, 1e18, 0, 0, 50e18, 0, 0);
        // gold unchanged (atomic)
        assertEq(world.getClan(clan1).goldBalance, fromGold0);
        assertEq(world.getClan(clan2).goldBalance, toGold0);
    }

    function test_transferBundle_dead_sender_reverts() public {
        world.killClan(clan1);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferBundle(clan1, clan2, 1e18, 0, 0, 0, 0, 0);
    }

    function test_transferBundle_dead_recipient_allowed() public {
        uint256 amount = 1e18;
        uint256 to0 = world.getClan(clan2).goldBalance;
        world.killClan(clan2);
        vm.prank(owner1);
        world.transferBundle(clan1, clan2, amount, 0, 0, 0, 0, 0);
        assertEq(world.getClan(clan2).goldBalance, to0 + amount);
    }

    function test_transferBundle_reservedWoodFailsAtomically() public {
        world.setVaultBalances(clan1, 20e18, 0, 20e18, 2e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeWall);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        uint256 fromGold0 = world.getClan(clan1).goldBalance;
        uint256 toGold0 = world.getClan(clan2).goldBalance;

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient wood");
        world.transferBundle(clan1, clan2, 1e18, 0, 1e18, 0, 0, 0);

        assertEq(world.getClan(clan1).goldBalance, fromGold0, "sender gold unchanged");
        assertEq(world.getClan(clan2).goldBalance, toGold0, "recipient gold unchanged");
    }

    function test_transferBundle_reservedBlueprintFailsAtomically() public {
        world.setMonumentLevel(clan1, 6);
        world.setVaultBalances(clan1, 200e18, 25e18, 100e18, 2e18);
        world.setBlueprintBalance(clan1, 1e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeMonument);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        uint256 fromGold0 = world.getClan(clan1).goldBalance;
        uint256 toGold0 = world.getClan(clan2).goldBalance;

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: insufficient blueprints");
        world.transferBundle(clan1, clan2, 1e18, 1e18, 0, 0, 0, 0);

        assertEq(world.getClan(clan1).goldBalance, fromGold0, "sender gold unchanged");
        assertEq(world.getClan(clan2).goldBalance, toGold0, "recipient gold unchanged");
    }

    function test_transferBundle_reservedResourcesAllowSurplusTransfer() public {
        world.setMonumentLevel(clan1, 6);
        world.setVaultBalances(clan1, 250e18, 40e18, 125e18, 2e18);
        world.setBlueprintBalance(clan1, 3e18);
        OrderResult[] memory result = _queueUpgrade(ActionType.UpgradeMonument);
        assertEq(uint8(result[0].status), uint8(StatusCode.OK), "upgrade queued");

        vm.prank(owner1);
        world.transferBundle(clan1, clan2, 1e18, 2e18, 25e18, 10e18, 20e18, 1e18);

        assertEq(world.getClan(clan1).goldBalance, 2e18, "gold debited");
        assertEq(world.getClan(clan1).blueprintBalance, 1e18, "blueprint surplus debited");
        assertEq(world.getClan(clan1).vaultWood, 225e18, "wood surplus debited");
        assertEq(world.getClan(clan1).vaultIron, 30e18, "iron surplus debited");
        assertEq(world.getClan(clan1).vaultWheat, 105e18, "wheat surplus debited");
        assertEq(world.getClan(clan1).vaultFish, 1e18, "fish debited");
        assertEq(world.getClan(clan2).blueprintBalance, 2e18, "blueprint credited");
        assertEq(world.getClan(clan2).vaultIron, 10e18, "iron credited");
    }

    function test_transferGold_sender_must_be_fully_settled() public {
        _advanceToTick(201);
        world.setVaultBalances(clan1, 1000e18, 0, 1000e18, 1000e18);
        world.setVaultBalances(clan2, 1000e18, 0, 1000e18, 1000e18);
        world.setClanLastSettledTick(clan1, 0);
        world.setClanLastSettledTick(clan2, world.getWorldState().currentTick);

        vm.prank(owner1);
        vm.expectRevert("ERR_MUST_SETTLE_FIRST");
        world.transferGold(clan1, clan2, 1e18);
    }

    // =========================================================================
    // DeadClanTransfer — dies-during-settle scenario (spec §M)
    // =========================================================================

    /// @dev Advance the world clock to `targetTick` by calling heartbeat() repeatedly.
    function _advanceToTick(uint64 targetTick) internal {
        // Ensure we start past the genesis timestamp to avoid underflow edge cases
        if (block.timestamp == 0) vm.warp(1);
        while (world.getWorldState().currentTick < targetTick) {
            vm.warp(world.getWorldState().nextHeartbeatAtTs + 1);
            world.heartbeat();
        }
    }

    /// @dev Put clan into a state where _settleClan will mark it DEAD on the next call.
    ///
    ///      Setup:
    ///      1. Advance world to tick 115 (inside winter window 110-119).
    ///      2. Set last-settled tick back to 110 so _settleClan must process ticks 110-114.
    ///      3. Zero food so starvation starts at tick 110 and kills one clansman per later winter tick.
    ///
    ///      During ticks 111-114 settlement: winter=true, starving=true,
    ///      effectiveStarvationStartsAtTick=110 < tick → kills all 4 clansmen → _markClanDead.
    ///
    ///      The clan is ALIVE before the transfer call (not yet settled to 115),
    ///      but DEAD after _settleClan runs inside the transfer function.
    function _setupDiesDuringSettle() internal {
        _advanceToTick(ClanWorldConstants.WINTER_START_TICK + 5);

        // Rewind lastSettledTick so _settleClan processes the first 5 winter ticks.
        world.setClanLastSettledTick(clan1, ClanWorldConstants.WINTER_START_TICK);
        world.setClanStarvationStartsAtTick(clan1, 0);
        // Zero food so upkeep is failing
        world.setVaultBalances(clan1, 100e18, 0, 0, 0);
        // Also ensure goldBalance is non-zero for the transfer tests
        world.setGoldBalance(clan1, 10e18);
        world.setBlueprintBalance(clan1, 10e18);
    }

    function test_transferGold_dies_during_settle_reverts() public {
        _setupDiesDuringSettle();
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferGold(clan1, clan2, 1e18);
    }

    function test_transferVaultResource_dies_during_settle_reverts() public {
        _setupDiesDuringSettle();
        // Also set some iron so the wood=100e18 doesn't confuse things; the clan dies on settle
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferVaultResource(clan1, clan2, ResourceType.Wood, 1e18);
    }

    function test_transferBlueprint_dies_during_settle_reverts() public {
        _setupDiesDuringSettle();
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferBlueprint(clan1, clan2, 5e18);
    }

    function test_transferBundle_dies_during_settle_reverts() public {
        _setupDiesDuringSettle();
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferBundle(clan1, clan2, 1e18, 0, 0, 0, 0, 0);
    }

    // =========================================================================
    // transferClanOwnership
    // =========================================================================

    function test_transferClanOwnership_happy_path() public {
        assertEq(world.getClan(clan1).ownerNonce, 0);
        vm.expectEmit(true, true, true, true);
        emit ClanOwnershipTransferred(clan1, owner1, stranger, 1);
        vm.prank(owner1);
        world.transferClanOwnership(clan1, stranger);
        assertEq(world.getClan(clan1).owner, stranger);
        assertEq(world.getClan(clan1).ownerNonce, 1);
    }

    function test_transferClanOwnership_nonce_increments_each_transfer() public {
        vm.prank(owner1);
        world.transferClanOwnership(clan1, owner2);
        assertEq(world.getClan(clan1).ownerNonce, 1);
        vm.prank(owner2);
        world.transferClanOwnership(clan1, stranger);
        assertEq(world.getClan(clan1).ownerNonce, 2);
    }

    function test_transferClanOwnership_non_owner_reverts() public {
        vm.prank(stranger);
        vm.expectRevert("ClanWorld: not clan owner");
        world.transferClanOwnership(clan1, stranger);
    }

    function test_transferClanOwnership_zero_address_reverts() public {
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: zero address");
        world.transferClanOwnership(clan1, address(0));
    }

    function test_transferClanOwnership_same_owner_reverts() public {
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: same owner");
        world.transferClanOwnership(clan1, owner1);
    }

    function test_transferClanOwnership_dead_clan_reverts() public {
        world.killClan(clan1);

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferClanOwnership(clan1, stranger);
    }

    function test_transferClanOwnership_dies_during_settle_reverts() public {
        _setupDiesDuringSettle();

        vm.prank(owner1);
        vm.expectRevert("ClanWorld: clan dead");
        world.transferClanOwnership(clan1, stranger);
    }

    function test_old_owner_cannot_transferGold_after_ownership_transfer() public {
        vm.prank(owner1);
        world.transferClanOwnership(clan1, owner2);
        vm.prank(owner1);
        vm.expectRevert("ClanWorld: not clan owner");
        world.transferGold(clan1, clan2, 1e18);
        // New owner can
        uint256 g0_1 = world.getClan(clan1).goldBalance;
        uint256 g0_2 = world.getClan(clan2).goldBalance;
        vm.prank(owner2);
        world.transferGold(clan1, clan2, 1e18);
        assertEq(world.getClan(clan1).goldBalance, g0_1 - 1e18);
        assertEq(world.getClan(clan2).goldBalance, g0_2 + 1e18);
    }

    // =========================================================================
    // Events (used in expectEmit)
    // =========================================================================
    event GoldTransferred(uint32 indexed fromClanId, uint32 indexed toClanId, uint256 amount, uint64 atTick);
    event BlueprintTransferred(uint32 indexed fromClanId, uint32 indexed toClanId, uint256 amount, uint64 atTick);
    event VaultResourceTransferred(
        uint32 indexed fromClanId, uint32 indexed toClanId, ResourceType resource, uint256 amount, uint64 atTick
    );
    event ClanOwnershipTransferred(
        uint32 indexed clanId, address indexed oldOwner, address indexed newOwner, uint64 newOwnerNonce
    );
}
