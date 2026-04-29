// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {Clan, ClanState} from "../src/IClanWorld.sol";

contract DeadClanOtcHarness is ClanWorld {
    function setClanState(uint32 clanId, ClanState state) external {
        _clans[clanId].clanState = state;
    }

    function setVault(uint32 clanId, uint256 wood, uint256 wheat, uint256 fish, uint256 iron) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
        _clans[clanId].vaultIron = iron;
    }

    function setBlueprintBalance(uint32 clanId, uint256 amount) external {
        _clans[clanId].blueprintBalance = amount;
    }
}

contract DeadClanOtcTest is Test {
    DeadClanOtcHarness world;
    address elderA = address(0xA1);
    address elderB = address(0xA2);
    address elderC = address(0xA3);

    function setUp() public {
        world = new DeadClanOtcHarness();
    }

    function test_aliveClansCanProposeAndAcceptAllOtcTypes() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        _fundOtcBalances(clanA);

        uint256 goldProposal = _proposeGold(elderA, clanA, clanB, 1e18);
        uint256 vaultProposal = _proposeVault(elderA, clanA, clanB, 1e18);
        uint256 blueprintProposal = _proposeBlueprint(elderA, clanA, clanB, 1e18);
        uint256 bundledProposal = _proposeBundled(elderA, clanA, clanB, 1e18);

        vm.prank(elderB);
        world.acceptGoldTransfer(goldProposal);
        vm.prank(elderB);
        world.acceptVaultTransfer(vaultProposal);
        vm.prank(elderB);
        world.acceptBlueprintTransfer(blueprintProposal);
        vm.prank(elderB);
        world.acceptBundledTransfer(bundledProposal);

        Clan memory fromAfter = world.getClan(clanA);
        Clan memory toAfter = world.getClan(clanB);
        assertEq(fromAfter.goldBalance, 1e18, "from gold debited");
        assertEq(toAfter.goldBalance, 5e18, "to gold credited");
        assertEq(fromAfter.vaultWood, 8e18, "from wood debited");
        assertEq(toAfter.vaultWood, 22e18, "to wood credited");
        assertEq(fromAfter.blueprintBalance, 0, "from blueprint debited");
        assertEq(toAfter.blueprintBalance, 2e18, "to blueprint credited");
    }

    function test_deadProposerCannotProposeAnyOtcType() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        _fundOtcBalances(clanA);
        world.setClanState(clanA, ClanState.DEAD);

        vm.expectRevert("ERR_CLAN_DEAD");
        _proposeGold(elderA, clanA, clanB, 1e18);
        vm.expectRevert("ERR_CLAN_DEAD");
        _proposeVault(elderA, clanA, clanB, 1e18);
        vm.expectRevert("ERR_CLAN_DEAD");
        _proposeBlueprint(elderA, clanA, clanB, 1e18);
        vm.expectRevert("ERR_CLAN_DEAD");
        _proposeBundled(elderA, clanA, clanB, 1e18);
    }

    function test_deadProposerAfterProposeCannotBeAccepted() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        _fundOtcBalances(clanA);
        uint256 goldProposal = _proposeGold(elderA, clanA, clanB, 1e18);
        uint256 vaultProposal = _proposeVault(elderA, clanA, clanB, 1e18);
        uint256 blueprintProposal = _proposeBlueprint(elderA, clanA, clanB, 1e18);
        uint256 bundledProposal = _proposeBundled(elderA, clanA, clanB, 1e18);

        world.setClanState(clanA, ClanState.DEAD);

        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptGoldTransfer(goldProposal);
        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptVaultTransfer(vaultProposal);
        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptBlueprintTransfer(blueprintProposal);
        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptBundledTransfer(bundledProposal);
    }

    function test_deadTargetCannotAcceptAnyOtcType() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        _fundOtcBalances(clanA);
        uint256 goldProposal = _proposeGold(elderA, clanA, clanB, 1e18);
        uint256 vaultProposal = _proposeVault(elderA, clanA, clanB, 1e18);
        uint256 blueprintProposal = _proposeBlueprint(elderA, clanA, clanB, 1e18);
        uint256 bundledProposal = _proposeBundled(elderA, clanA, clanB, 1e18);

        world.setClanState(clanB, ClanState.DEAD);

        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptGoldTransfer(goldProposal);
        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptVaultTransfer(vaultProposal);
        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptBlueprintTransfer(blueprintProposal);
        vm.expectRevert("ERR_CLAN_DEAD");
        vm.prank(elderB);
        world.acceptBundledTransfer(bundledProposal);
    }

    function test_deadProposerCanCancelExistingProposals() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        _fundOtcBalances(clanA);
        uint256 goldProposal = _proposeGold(elderA, clanA, clanB, 1e18);
        uint256 vaultProposal = _proposeVault(elderA, clanA, clanB, 1e18);
        uint256 blueprintProposal = _proposeBlueprint(elderA, clanA, clanB, 1e18);
        uint256 bundledProposal = _proposeBundled(elderA, clanA, clanB, 1e18);

        world.setClanState(clanA, ClanState.DEAD);

        vm.prank(elderA);
        world.cancelGoldTransfer(goldProposal);
        vm.prank(elderA);
        world.cancelVaultTransfer(vaultProposal);
        vm.prank(elderA);
        world.cancelBlueprintTransfer(blueprintProposal);
        vm.prank(elderA);
        world.cancelBundledTransfer(bundledProposal);

        assertTrue(world.getOtcGoldProposal(goldProposal).cancelled, "gold cancelled");
        assertTrue(world.getOtcVaultTransferProposal(vaultProposal).cancelled, "vault cancelled");
        assertTrue(world.getOtcBlueprintTransferProposal(blueprintProposal).cancelled, "blueprint cancelled");
        assertTrue(world.getOtcBundledTransferProposal(bundledProposal).cancelled, "bundled cancelled");
    }

    function test_unrelatedClanDeathDoesNotBlockOtherClanOtc() public {
        (uint32 clanA, uint32 clanB, uint32 clanC) = _mintThreeClans();
        world.setClanState(clanA, ClanState.DEAD);

        uint256 clanCBefore = world.getClan(clanC).goldBalance;
        uint256 proposalId = _proposeGold(elderB, clanB, clanC, 1e18);

        vm.prank(elderC);
        world.acceptGoldTransfer(proposalId);

        assertEq(world.getClan(clanC).goldBalance, clanCBefore + 1e18, "alive clans trade");
    }

    function _mintThreeClans() internal returns (uint32 clanA, uint32 clanB, uint32 clanC) {
        vm.prank(elderA);
        (clanA,) = world.mintClan(elderA);
        vm.prank(elderB);
        (clanB,) = world.mintClan(elderB);
        vm.prank(elderC);
        (clanC,) = world.mintClan(elderC);
    }

    function _fundOtcBalances(uint32 clanId) internal {
        world.setVault(clanId, 10e18, 10e18, 10e18, 10e18);
        world.setBlueprintBalance(clanId, 2e18);
    }

    function _proposeGold(address elder, uint32 fromClanId, uint32 toClanId, uint256 amount)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(elder);
        proposalId = world.proposeGoldTransfer(fromClanId, toClanId, amount, 10);
    }

    function _proposeVault(address elder, uint32 fromClanId, uint32 toClanId, uint256 amount)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(elder);
        proposalId = world.proposeVaultTransfer(fromClanId, toClanId, amount, amount, amount, amount, 10);
    }

    function _proposeBlueprint(address elder, uint32 fromClanId, uint32 toClanId, uint256 amount)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(elder);
        proposalId = world.proposeBlueprintTransfer(fromClanId, toClanId, amount, 10);
    }

    function _proposeBundled(address elder, uint32 fromClanId, uint32 toClanId, uint256 amount)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(elder);
        proposalId =
            world.proposeBundledTransfer(fromClanId, toClanId, amount, amount, amount, amount, amount, amount, 10);
    }
}
