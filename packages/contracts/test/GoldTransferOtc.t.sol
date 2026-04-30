// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {ClanWorldConstants, ClanState, OtcProposal} from "../src/IClanWorld.sol";

contract GoldTransferOtcTest is Test {
    event GoldTransferProposed(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 amount,
        uint256 expiryTick
    );
    event GoldTransferAccepted(
        uint256 indexed proposalId,
        uint32 indexed fromClanId,
        uint32 indexed toClanId,
        uint256 amount,
        uint64 settledAtTick
    );
    event GoldTransferCancelled(uint256 indexed proposalId);

    ClanWorld world;
    address elderA = address(0xA1);
    address elderB = address(0xA2);
    address elderC = address(0xA3);

    function setUp() public {
        world = new ClanWorld();
    }

    function test_proposeGoldTransfer_storesProposalAndEmits() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 amount = 1e18;
        uint256 expiryTick = 10;

        vm.expectEmit(true, true, true, true, address(world));
        emit GoldTransferProposed(1, clanA, clanB, amount, expiryTick);
        vm.prank(elderA);
        uint256 proposalId = world.proposeGoldTransfer(clanA, clanB, amount, expiryTick);

        assertEq(proposalId, 1, "first proposal id");
        OtcProposal memory proposal = world.getOtcGoldProposal(proposalId);
        assertEq(proposal.from, clanA, "proposal from");
        assertEq(proposal.to, clanB, "proposal to");
        assertEq(proposal.amount, amount, "proposal amount");
        assertEq(proposal.expiryTick, uint64(expiryTick), "proposal expiry");
        assertFalse(proposal.accepted, "proposal not accepted");
        assertFalse(proposal.cancelled, "proposal not cancelled");
    }

    function test_acceptGoldTransfer_transfersAtomicallyAndEmits() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 amount = 1e18;
        uint256 fromBefore = world.getClan(clanA).goldBalance;
        uint256 toBefore = world.getClan(clanB).goldBalance;

        uint256 proposalId = _propose(clanA, clanB, amount, 10);

        vm.expectEmit(true, true, true, true, address(world));
        emit GoldTransferAccepted(proposalId, clanA, clanB, amount, world.getWorldState().currentTick);
        vm.prank(elderB);
        world.acceptGoldTransfer(proposalId);

        assertEq(world.getClan(clanA).goldBalance, fromBefore - amount, "from debited");
        assertEq(world.getClan(clanB).goldBalance, toBefore + amount, "to credited");
        assertEq(world.getOtcGoldProposal(proposalId).from, 0, "proposal deleted");
    }

    function test_acceptGoldTransfer_revertsWhenBalanceChangedAfterProposal() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalOne = _propose(clanA, clanB, 3e18, 10);
        uint256 proposalTwo = _propose(clanA, clanB, 3e18, 10);

        vm.prank(elderB);
        world.acceptGoldTransfer(proposalOne);

        vm.expectRevert("ERR_NOT_ENOUGH_GOLD");
        vm.prank(elderB);
        world.acceptGoldTransfer(proposalTwo);
    }

    function test_acceptGoldTransfer_revertsWhenExpired() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, world.getWorldState().currentTick);
        _advanceTick();

        vm.expectRevert("ClanWorld: proposal expired");
        vm.prank(elderB);
        world.acceptGoldTransfer(proposalId);
    }

    function test_goldTransfer_wrongCallersRevert() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();

        vm.expectRevert("ClanWorld: not clan owner");
        vm.prank(elderB);
        world.proposeGoldTransfer(clanA, clanB, 1e18, 10);

        uint256 proposalId = _propose(clanA, clanB, 1e18, 10);
        vm.expectRevert("ClanWorld: not clan owner");
        vm.prank(elderA);
        world.acceptGoldTransfer(proposalId);
    }

    function test_cancelGoldTransfer_byProposerBlocksAccept() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, 10);

        vm.expectEmit(true, false, false, true, address(world));
        emit GoldTransferCancelled(proposalId);
        vm.prank(elderA);
        world.cancelGoldTransfer(proposalId);

        assertEq(world.getOtcGoldProposal(proposalId).from, 0, "proposal deleted");
        vm.expectRevert("ClanWorld: proposal not found");
        vm.prank(elderB);
        world.acceptGoldTransfer(proposalId);
    }

    function test_cancelGoldTransfer_acceptorCannotCancel() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, 10);

        vm.expectRevert("ClanWorld: not clan owner");
        vm.prank(elderB);
        world.cancelGoldTransfer(proposalId);
    }

    function test_goldTransfer_twoClanNoInterference() public {
        (uint32 clanA, uint32 clanB, uint32 clanC) = _mintThreeClans();
        uint256 clanBBefore = world.getClan(clanB).goldBalance;
        uint256 clanCBefore = world.getClan(clanC).goldBalance;

        uint256 proposalId = _propose(clanA, clanC, 1e18, 10);
        vm.prank(elderC);
        world.acceptGoldTransfer(proposalId);

        assertEq(world.getClan(clanB).goldBalance, clanBBefore, "unrelated clan unchanged");
        assertEq(world.getClan(clanC).goldBalance, clanCBefore + 1e18, "target clan credited");
    }

    function test_proposeGoldTransfer_revertsWhenZeroAmount() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();

        vm.expectRevert("ERR_ZERO_AMOUNT");
        _propose(clanA, clanB, 0, 10);
    }

    function test_proposeGoldTransfer_revertsWhenSelfTransfer() public {
        (uint32 clanA,,) = _mintThreeClans();

        vm.expectRevert("ERR_SELF_TRANSFER");
        _propose(clanA, clanA, 1e18, 10);
    }

    function test_goldTransfer_openProposalCapDecrementsAfterAccept() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();

        uint256 firstProposalId;
        uint256 secondProposalId;
        for (uint256 i = 0; i < world.MAX_OPEN_OTC_PROPOSALS_PER_CLAN(); i++) {
            uint256 proposalId = _propose(clanA, clanB, 1, 10);
            if (i == 0) firstProposalId = proposalId;
            if (i == 1) secondProposalId = proposalId;
        }

        vm.expectRevert("ERR_OTC_CAP");
        _propose(clanA, clanB, 1, 10);

        vm.prank(elderB);
        world.acceptGoldTransfer(firstProposalId);

        uint256 newProposalId = _propose(clanA, clanB, 1, 10);
        assertGt(newProposalId, firstProposalId, "cap slot reopened after accept");

        vm.expectRevert("ERR_OTC_CAP");
        _propose(clanA, clanB, 1, 10);

        vm.prank(elderA);
        world.cancelGoldTransfer(secondProposalId);

        uint256 postCancelProposalId = _propose(clanA, clanB, 1, 10);
        assertGt(postCancelProposalId, newProposalId, "cap slot reopened after cancel");
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

    function _propose(uint32 fromClanId, uint32 toClanId, uint256 amount, uint256 expiryTick)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(elderA);
        proposalId = world.proposeGoldTransfer(fromClanId, toClanId, amount, expiryTick);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }
}
