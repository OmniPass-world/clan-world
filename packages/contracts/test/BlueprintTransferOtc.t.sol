// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {BlueprintTransferProposal, ClanWorldConstants, Clan, ClanState} from "../src/IClanWorld.sol";

contract BlueprintTransferHarness is ClanWorld {
    function setBlueprintBalance(uint32 clanId, uint256 amount) external {
        _clans[clanId].blueprintBalance = amount;
    }
}

contract BlueprintTransferOtcTest is Test {
    event BlueprintTransferProposed(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 amount,
        uint64 expiryTick
    );
    event BlueprintTransferAccepted(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 amount,
        uint64 settledAtTick
    );
    event BlueprintTransferCancelled(uint256 indexed proposalId);

    BlueprintTransferHarness world;
    address elderA = address(0xA1);
    address elderB = address(0xA2);
    address elderC = address(0xA3);

    function setUp() public {
        world = new BlueprintTransferHarness();
    }

    function test_proposeAndAcceptBlueprintTransfer_transfersAtomically() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBlueprintBalance(clanA, 10e18);
        world.setBlueprintBalance(clanB, 2e18);
        uint256 amount = 3e18;

        vm.expectEmit(true, true, true, true, address(world));
        emit BlueprintTransferProposed(1, clanA, clanB, amount, 10);
        uint256 proposalId = _propose(clanA, clanB, amount, 10);

        BlueprintTransferProposal memory proposal = world.getOtcBlueprintTransferProposal(proposalId);
        assertEq(proposal.from, clanA, "proposal from");
        assertEq(proposal.to, clanB, "proposal to");
        assertEq(proposal.amount, amount, "proposal amount");
        assertEq(proposal.expiryTick, 10, "proposal expiry");

        vm.expectEmit(true, true, true, true, address(world));
        emit BlueprintTransferAccepted(proposalId, clanA, clanB, amount, world.getWorldState().currentTick);
        vm.prank(elderB);
        world.acceptBlueprintTransfer(proposalId);

        assertEq(world.getClan(clanA).blueprintBalance, 7e18, "from debited");
        assertEq(world.getClan(clanB).blueprintBalance, 5e18, "to credited");
        assertEq(world.getOtcBlueprintTransferProposal(proposalId).from, 0, "proposal deleted");
    }

    function test_acceptBlueprintTransfer_revertsWhenBalanceChangedAfterProposal() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBlueprintBalance(clanA, 3e18);
        world.setBlueprintBalance(clanB, 1e18);
        uint256 proposalId = _propose(clanA, clanB, 3e18, 10);
        world.setBlueprintBalance(clanA, 2e18);

        vm.expectRevert("ERR_NOT_ENOUGH_BLUEPRINT");
        vm.prank(elderB);
        world.acceptBlueprintTransfer(proposalId);

        Clan memory fromAfter = world.getClan(clanA);
        Clan memory toAfter = world.getClan(clanB);
        assertEq(fromAfter.blueprintBalance, 2e18, "from unchanged");
        assertEq(toAfter.blueprintBalance, 1e18, "to unchanged");
    }

    function test_acceptBlueprintTransfer_revertsWhenExpired() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBlueprintBalance(clanA, 3e18);
        uint256 proposalId = _propose(clanA, clanB, 1e18, world.getWorldState().currentTick);
        _advanceTick();

        vm.expectRevert("ClanWorld: proposal expired");
        vm.prank(elderB);
        world.acceptBlueprintTransfer(proposalId);
    }

    function test_cancelBlueprintTransfer_byProposerBlocksAccept() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        world.setBlueprintBalance(clanA, 3e18);
        uint256 proposalId = _propose(clanA, clanB, 1e18, 10);

        vm.expectEmit(true, false, false, true, address(world));
        emit BlueprintTransferCancelled(proposalId);
        vm.prank(elderA);
        world.cancelBlueprintTransfer(proposalId);

        assertEq(world.getOtcBlueprintTransferProposal(proposalId).from, 0, "proposal deleted");
        vm.expectRevert("ClanWorld: proposal not found");
        vm.prank(elderB);
        world.acceptBlueprintTransfer(proposalId);
    }

    function test_blueprintTransfer_twoClanNoInterference() public {
        (uint32 clanA, uint32 clanB, uint32 clanC) = _mintThreeClans();
        world.setBlueprintBalance(clanA, 10e18);
        world.setBlueprintBalance(clanB, 4e18);
        world.setBlueprintBalance(clanC, 1e18);

        uint256 proposalId = _propose(clanA, clanC, 6e18, 10);
        vm.prank(elderC);
        world.acceptBlueprintTransfer(proposalId);

        assertEq(world.getClan(clanB).blueprintBalance, 4e18, "unrelated clan unchanged");
        assertEq(world.getClan(clanC).blueprintBalance, 7e18, "target clan credited");
    }

    function test_proposeBlueprintTransfer_revertsWhenZeroAmount() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();

        vm.expectRevert("ERR_ZERO_AMOUNT");
        _propose(clanA, clanB, 0, 10);
    }

    function test_proposeBlueprintTransfer_revertsWhenSelfTransfer() public {
        (uint32 clanA,,) = _mintThreeClans();

        vm.expectRevert("ERR_SELF_TRANSFER");
        _propose(clanA, clanA, 1e18, 10);
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

    function _propose(uint32 fromClanId, uint32 toClanId, uint256 amount, uint64 expiryTick)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(elderA);
        proposalId = world.proposeBlueprintTransfer(fromClanId, toClanId, amount, expiryTick);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }
}
