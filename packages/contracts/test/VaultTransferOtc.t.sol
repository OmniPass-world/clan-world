// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {ClanWorldConstants, Clan, ClanState, VaultTransferProposal} from "../src/IClanWorld.sol";

contract VaultTransferHarness is ClanWorld {
    function setVault(uint32 clanId, uint256 wood, uint256 wheat, uint256 fish, uint256 iron) external {
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
        _clans[clanId].vaultIron = iron;
    }
}

contract VaultTransferOtcTest is Test {
    event VaultTransferProposed(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint64 expiryTick
    );
    event VaultTransferAccepted(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint64 settledAtTick
    );
    event VaultTransferCancelled(uint256 indexed proposalId);

    VaultTransferHarness world;
    address elderA = address(0xA1);
    address elderB = address(0xA2);
    address elderC = address(0xA3);

    function setUp() public {
        world = new VaultTransferHarness();
    }

    function test_proposeAndAcceptVaultTransfer_transfersAllResourcesAtomically() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setVault(clanA, 100e18, 80e18, 30e18, 20e18);
        world.setVault(clanB, 10e18, 11e18, 12e18, 13e18);

        vm.expectEmit(true, true, true, true, address(world));
        emit VaultTransferProposed(1, clanA, clanB, 15e18, 16e18, 2e18, 3e18, 10);
        uint256 proposalId = _propose(clanA, clanB, 15e18, 16e18, 2e18, 3e18, 10);

        VaultTransferProposal memory proposal = world.getOtcVaultTransferProposal(proposalId);
        assertEq(proposal.from, clanA, "proposal from");
        assertEq(proposal.to, clanB, "proposal to");
        assertEq(proposal.wood, 15e18, "proposal wood");
        assertEq(proposal.wheat, 16e18, "proposal wheat");
        assertEq(proposal.fish, 2e18, "proposal fish");
        assertEq(proposal.iron, 3e18, "proposal iron");
        assertFalse(proposal.accepted, "proposal not accepted");

        vm.expectEmit(true, true, true, true, address(world));
        emit VaultTransferAccepted(
            proposalId, clanA, clanB, 15e18, 16e18, 2e18, 3e18, world.getWorldState().currentTick
        );
        vm.prank(elderB);
        world.acceptVaultTransfer(proposalId);

        Clan memory fromAfter = world.getClan(clanA);
        Clan memory toAfter = world.getClan(clanB);
        assertEq(fromAfter.vaultWood, 85e18, "from wood debited");
        assertEq(fromAfter.vaultWheat, 64e18, "from wheat debited");
        assertEq(fromAfter.vaultFish, 28e18, "from fish debited");
        assertEq(fromAfter.vaultIron, 17e18, "from iron debited");
        assertEq(toAfter.vaultWood, 25e18, "to wood credited");
        assertEq(toAfter.vaultWheat, 27e18, "to wheat credited");
        assertEq(toAfter.vaultFish, 14e18, "to fish credited");
        assertEq(toAfter.vaultIron, 16e18, "to iron credited");
        assertTrue(world.getOtcVaultTransferProposal(proposalId).accepted, "proposal accepted");
    }

    function test_acceptVaultTransfer_revertsAndLeavesAllResourcesWhenOneResourceInsufficient() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setVault(clanA, 100e18, 100e18, 100e18, 5e18);
        world.setVault(clanB, 10e18, 10e18, 10e18, 10e18);
        uint256 proposalId = _propose(clanA, clanB, 20e18, 20e18, 20e18, 5e18, 10);
        world.setVault(clanA, 100e18, 100e18, 100e18, 4e18);

        vm.expectRevert("ERR_NOT_ENOUGH_RESOURCES");
        vm.prank(elderB);
        world.acceptVaultTransfer(proposalId);

        Clan memory fromAfter = world.getClan(clanA);
        Clan memory toAfter = world.getClan(clanB);
        assertEq(fromAfter.vaultWood, 100e18, "from wood unchanged");
        assertEq(fromAfter.vaultWheat, 100e18, "from wheat unchanged");
        assertEq(fromAfter.vaultFish, 100e18, "from fish unchanged");
        assertEq(fromAfter.vaultIron, 4e18, "from iron unchanged");
        assertEq(toAfter.vaultWood, 10e18, "to wood unchanged");
        assertEq(toAfter.vaultWheat, 10e18, "to wheat unchanged");
        assertEq(toAfter.vaultFish, 10e18, "to fish unchanged");
        assertEq(toAfter.vaultIron, 10e18, "to iron unchanged");
    }

    function test_acceptVaultTransfer_revertsWhenExpired() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setVault(clanA, 100e18, 100e18, 100e18, 100e18);
        uint256 proposalId = _propose(clanA, clanB, 1e18, 1e18, 1e18, 1e18, world.getWorldState().currentTick);
        _advanceTick();

        vm.expectRevert("ClanWorld: proposal expired");
        vm.prank(elderB);
        world.acceptVaultTransfer(proposalId);
    }

    function test_cancelVaultTransfer_byProposerBlocksAccept() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setVault(clanA, 100e18, 100e18, 100e18, 100e18);
        uint256 proposalId = _propose(clanA, clanB, 1e18, 1e18, 1e18, 1e18, 10);

        vm.expectEmit(true, false, false, true, address(world));
        emit VaultTransferCancelled(proposalId);
        vm.prank(elderA);
        world.cancelVaultTransfer(proposalId);

        assertTrue(world.getOtcVaultTransferProposal(proposalId).cancelled, "proposal cancelled");
        vm.expectRevert("ClanWorld: proposal cancelled");
        vm.prank(elderB);
        world.acceptVaultTransfer(proposalId);
    }

    function test_vaultTransfer_twoClanNoInterference() public {
        (uint32 clanA, uint32 clanB, uint32 clanC) = _mintThreeClans();
        world.setVault(clanA, 100e18, 100e18, 100e18, 100e18);
        world.setVault(clanB, 7e18, 8e18, 9e18, 10e18);
        world.setVault(clanC, 1e18, 2e18, 3e18, 4e18);

        uint256 proposalId = _propose(clanA, clanC, 11e18, 12e18, 13e18, 14e18, 10);
        vm.prank(elderC);
        world.acceptVaultTransfer(proposalId);

        Clan memory clanBAfter = world.getClan(clanB);
        Clan memory clanCAfter = world.getClan(clanC);
        assertEq(clanBAfter.vaultWood, 7e18, "unrelated wood unchanged");
        assertEq(clanBAfter.vaultWheat, 8e18, "unrelated wheat unchanged");
        assertEq(clanBAfter.vaultFish, 9e18, "unrelated fish unchanged");
        assertEq(clanBAfter.vaultIron, 10e18, "unrelated iron unchanged");
        assertEq(clanCAfter.vaultWood, 12e18, "target wood credited");
        assertEq(clanCAfter.vaultWheat, 14e18, "target wheat credited");
        assertEq(clanCAfter.vaultFish, 16e18, "target fish credited");
        assertEq(clanCAfter.vaultIron, 18e18, "target iron credited");
    }

    function _mintThreeClans() internal returns (uint32 clanA, uint32 clanB, uint32 clanC) {
        vm.prank(elderA);
        (clanA,) = world.mintClan(elderA);
        vm.prank(elderB);
        (clanB,) = world.mintClan(elderB);
        vm.prank(elderC);
        (clanC,) = world.mintClan(elderC);

        assertEq(uint8(world.getClan(clanA).clanState), uint8(ClanState.ACTIVE), "clan A alive");
        assertEq(uint8(world.getClan(clanB).clanState), uint8(ClanState.ACTIVE), "clan B alive");
        assertEq(uint8(world.getClan(clanC).clanState), uint8(ClanState.ACTIVE), "clan C alive");
    }

    function _propose(
        uint32 fromClanId,
        uint32 toClanId,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint64 expiryTick
    ) internal returns (uint256 proposalId) {
        vm.prank(elderA);
        proposalId = world.proposeVaultTransfer(fromClanId, toClanId, wood, wheat, fish, iron, expiryTick);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }
}
