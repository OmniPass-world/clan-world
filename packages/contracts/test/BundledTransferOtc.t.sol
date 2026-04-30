// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {BundledTransferProposal, ClanWorldConstants, Clan, ClanState} from "../src/IClanWorld.sol";

contract BundledTransferHarness is ClanWorld {
    function setBalances(
        uint32 clanId,
        uint256 gold,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint256 blueprint
    ) external {
        _clans[clanId].goldBalance = gold;
        _clans[clanId].vaultWood = wood;
        _clans[clanId].vaultWheat = wheat;
        _clans[clanId].vaultFish = fish;
        _clans[clanId].vaultIron = iron;
        _clans[clanId].blueprintBalance = blueprint;
    }
}

contract BundledTransferOtcTest is Test {
    event BundledTransferProposed(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 gold,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint256 blueprint,
        uint64 expiryTick
    );
    event BundledTransferAccepted(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 gold,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint256 blueprint,
        uint64 settledAtTick
    );
    event BundledTransferCancelled(uint256 indexed proposalId);

    BundledTransferHarness world;
    address elderA = address(0xA1);
    address elderB = address(0xA2);
    address elderC = address(0xA3);

    function setUp() public {
        world = new BundledTransferHarness();
    }

    function test_proposeAndAcceptBundledTransfer_transfersAllComponentsAtomically() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBalances(clanA, 100e18, 80e18, 70e18, 60e18, 50e18, 40e18);
        world.setBalances(clanB, 10e18, 11e18, 12e18, 13e18, 14e18, 15e18);

        vm.expectEmit(true, true, true, true, address(world));
        emit BundledTransferProposed(1, clanA, clanB, 9e18, 8e18, 7e18, 6e18, 5e18, 4e18, 10);
        uint256 proposalId = _propose(clanA, clanB, 9e18, 8e18, 7e18, 6e18, 5e18, 4e18, 10);

        BundledTransferProposal memory proposal = world.getOtcBundledTransferProposal(proposalId);
        assertEq(proposal.from, clanA, "proposal from");
        assertEq(proposal.to, clanB, "proposal to");
        assertEq(proposal.gold, 9e18, "proposal gold");
        assertEq(proposal.wood, 8e18, "proposal wood");
        assertEq(proposal.wheat, 7e18, "proposal wheat");
        assertEq(proposal.fish, 6e18, "proposal fish");
        assertEq(proposal.iron, 5e18, "proposal iron");
        assertEq(proposal.blueprint, 4e18, "proposal blueprint");
        assertEq(proposal.expiryTick, 10, "proposal expiry");
        assertFalse(proposal.accepted, "proposal not accepted");
        assertFalse(proposal.cancelled, "proposal not cancelled");

        vm.expectEmit(true, true, true, true, address(world));
        emit BundledTransferAccepted(
            proposalId, clanA, clanB, 9e18, 8e18, 7e18, 6e18, 5e18, 4e18, world.getWorldState().currentTick
        );
        vm.prank(elderB);
        world.acceptBundledTransfer(proposalId);

        _assertBalances(clanA, 91e18, 72e18, 63e18, 54e18, 45e18, 36e18, "from debited");
        _assertBalances(clanB, 19e18, 19e18, 19e18, 19e18, 19e18, 19e18, "to credited");
        assertEq(world.getOtcBundledTransferProposal(proposalId).from, 0, "proposal deleted");
    }

    function test_acceptBundledTransfer_revertsAndLeavesAllComponentsWhenGoldInsufficient() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBalances(clanA, 10e18, 80e18, 70e18, 60e18, 50e18, 40e18);
        world.setBalances(clanB, 1e18, 2e18, 3e18, 4e18, 5e18, 6e18);
        uint256 proposalId = _propose(clanA, clanB, 10e18, 8e18, 7e18, 6e18, 5e18, 4e18, 10);
        world.setBalances(clanA, 9e18, 80e18, 70e18, 60e18, 50e18, 40e18);

        vm.expectRevert("ERR_NOT_ENOUGH_GOLD");
        vm.prank(elderB);
        world.acceptBundledTransfer(proposalId);

        _assertBalances(clanA, 9e18, 80e18, 70e18, 60e18, 50e18, 40e18, "from unchanged");
        _assertBalances(clanB, 1e18, 2e18, 3e18, 4e18, 5e18, 6e18, "to unchanged");
    }

    function test_acceptBundledTransfer_revertsAndLeavesAllComponentsWhenOneResourceInsufficient() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBalances(clanA, 100e18, 80e18, 70e18, 60e18, 5e18, 40e18);
        world.setBalances(clanB, 1e18, 2e18, 3e18, 4e18, 5e18, 6e18);
        uint256 proposalId = _propose(clanA, clanB, 10e18, 8e18, 7e18, 6e18, 5e18, 4e18, 10);
        world.setBalances(clanA, 100e18, 80e18, 70e18, 60e18, 4e18, 40e18);

        vm.expectRevert("ERR_NOT_ENOUGH_RESOURCES");
        vm.prank(elderB);
        world.acceptBundledTransfer(proposalId);

        _assertBalances(clanA, 100e18, 80e18, 70e18, 60e18, 4e18, 40e18, "from unchanged");
        _assertBalances(clanB, 1e18, 2e18, 3e18, 4e18, 5e18, 6e18, "to unchanged");
    }

    function test_acceptBundledTransfer_revertsWhenExpired() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBalances(clanA, 100e18, 80e18, 70e18, 60e18, 50e18, 40e18);
        uint256 proposalId =
            _propose(clanA, clanB, 1e18, 1e18, 1e18, 1e18, 1e18, 1e18, world.getWorldState().currentTick);
        _advanceTick();

        vm.expectRevert("ClanWorld: proposal expired");
        vm.prank(elderB);
        world.acceptBundledTransfer(proposalId);
    }

    function test_cancelBundledTransfer_byProposerBlocksAccept() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBalances(clanA, 100e18, 80e18, 70e18, 60e18, 50e18, 40e18);
        uint256 proposalId = _propose(clanA, clanB, 1e18, 1e18, 1e18, 1e18, 1e18, 1e18, 10);

        vm.expectEmit(true, false, false, true, address(world));
        emit BundledTransferCancelled(proposalId);
        vm.prank(elderA);
        world.cancelBundledTransfer(proposalId);

        assertEq(world.getOtcBundledTransferProposal(proposalId).from, 0, "proposal deleted");
        vm.expectRevert("ClanWorld: proposal not found");
        vm.prank(elderB);
        world.acceptBundledTransfer(proposalId);
    }

    function test_proposeBundledTransfer_revertsWhenEmpty() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();

        vm.expectRevert("ERR_ZERO_AMOUNT");
        _propose(clanA, clanB, 0, 0, 0, 0, 0, 0, 10);
    }

    function test_proposeBundledTransfer_revertsWhenSelfTransfer() public {
        (uint32 clanA,,) = _mintThreeClans();

        vm.expectRevert("ERR_SELF_TRANSFER");
        _propose(clanA, clanA, 1e18, 0, 0, 0, 0, 0, 10);
    }

    function test_bundledTransfer_twoClanNoInterference() public {
        (uint32 clanA, uint32 clanB, uint32 clanC) = _mintThreeClans();
        world.setBalances(clanA, 100e18, 80e18, 70e18, 60e18, 50e18, 40e18);
        world.setBalances(clanB, 1e18, 2e18, 3e18, 4e18, 5e18, 6e18);
        world.setBalances(clanC, 10e18, 20e18, 30e18, 40e18, 50e18, 60e18);

        uint256 proposalId = _propose(clanA, clanC, 9e18, 8e18, 7e18, 6e18, 5e18, 4e18, 10);
        vm.prank(elderC);
        world.acceptBundledTransfer(proposalId);

        _assertBalances(clanB, 1e18, 2e18, 3e18, 4e18, 5e18, 6e18, "unrelated unchanged");
        _assertBalances(clanC, 19e18, 28e18, 37e18, 46e18, 55e18, 64e18, "target credited");
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
        uint256 gold,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint256 blueprint,
        uint64 expiryTick
    ) internal returns (uint256 proposalId) {
        vm.prank(elderA);
        proposalId =
            world.proposeBundledTransfer(fromClanId, toClanId, gold, wood, wheat, fish, iron, blueprint, expiryTick);
    }

    function _assertBalances(
        uint32 clanId,
        uint256 gold,
        uint256 wood,
        uint256 wheat,
        uint256 fish,
        uint256 iron,
        uint256 blueprint,
        string memory label
    ) internal view {
        Clan memory clan = world.getClan(clanId);
        assertEq(clan.goldBalance, gold, label);
        assertEq(clan.vaultWood, wood, label);
        assertEq(clan.vaultWheat, wheat, label);
        assertEq(clan.vaultFish, fish, label);
        assertEq(clan.vaultIron, iron, label);
        assertEq(clan.blueprintBalance, blueprint, label);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }
}
