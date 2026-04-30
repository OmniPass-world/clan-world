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
        uint64 expiryTick
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
        uint64 expiryTick = 10;

        vm.expectEmit(true, true, true, true, address(world));
        emit GoldTransferProposed(1, clanA, clanB, amount, expiryTick);
        vm.prank(elderA);
        uint256 proposalId = world.proposeGoldTransfer(clanA, clanB, amount, expiryTick);

        assertEq(proposalId, 1, "first proposal id");
        OtcProposal memory proposal = world.getOtcGoldProposal(proposalId);
        assertEq(proposal.from, clanA, "proposal from");
        assertEq(proposal.to, clanB, "proposal to");
        assertEq(proposal.amount, amount, "proposal amount");
        assertEq(proposal.expiryTick, expiryTick, "proposal expiry");
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

    function test_cancelGoldTransfer_newOwnerCanCancelInheritedProposal() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, 100);

        // Transfer clan A to a new owner
        address elderD = address(0xD1);
        vm.prank(elderA);
        world.transferClanOwnership(clanA, elderD);

        // New owner (elderD) can cancel the inherited stale proposal
        vm.expectEmit(true, false, false, false, address(world));
        emit GoldTransferCancelled(proposalId);
        vm.prank(elderD);
        world.cancelGoldTransfer(proposalId);

        // Proposal deleted
        assertEq(world.getOtcGoldProposal(proposalId).from, 0, "proposal deleted after new-owner cancel");
        // OTC slot freed — new owner can now propose
        vm.prank(elderD);
        world.proposeGoldTransfer(clanA, clanB, 1e18, 200);
    }

    function test_cancelGoldTransfer_oldOwnerCannotCancelAfterTransfer() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, 100);

        // Transfer clan A to a new owner
        address elderD = address(0xD1);
        vm.prank(elderA);
        world.transferClanOwnership(clanA, elderD);

        // Old owner (elderA) cannot cancel — no longer the owner
        vm.expectRevert("ClanWorld: not clan owner");
        vm.prank(elderA);
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

        vm.expectRevert("ERR_EMPTY_TRANSFER");
        _propose(clanA, clanB, 0, 10);
    }

    function test_acceptGoldTransfer_revertsAfterOwnershipTransfer() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, 100);

        // Transfer clan A to a new owner
        address elderD = address(0xD1);
        vm.prank(elderA);
        world.transferClanOwnership(clanA, elderD);

        // elderB tries to accept — should revert because nonce changed
        vm.expectRevert("ERR_PROPOSER_NO_LONGER_OWNER");
        vm.prank(elderB);
        world.acceptGoldTransfer(proposalId);
    }

    function test_acceptGoldTransfer_succeedsWithoutOwnershipChange() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();
        uint256 proposalId = _propose(clanA, clanB, 1e18, 100);

        // No ownership change — should succeed
        vm.prank(elderB);
        world.acceptGoldTransfer(proposalId);

        assertEq(world.getOtcGoldProposal(proposalId).from, 0, "proposal deleted");
    }

    function test_transferClanOwnership_incrementsNonce() public {
        (uint32 clanA,,) = _mintThreeClans();
        uint64 nonceBefore = world.getClan(clanA).ownerNonce;

        address elderD = address(0xD1);
        vm.prank(elderA);
        world.transferClanOwnership(clanA, elderD);

        assertEq(world.getClan(clanA).ownerNonce, nonceBefore + 1, "nonce incremented");
        assertEq(world.getClan(clanA).owner, elderD, "owner updated");
    }

    function test_transferClanOwnership_revertsForNonOwner() public {
        (uint32 clanA,,) = _mintThreeClans();

        vm.expectRevert("ClanWorld: not clan owner");
        vm.prank(elderB);
        world.transferClanOwnership(clanA, elderB);
    }

    function test_transferClanOwnership_revertsForSameOwner() public {
        (uint32 clanA,,) = _mintThreeClans();

        vm.expectRevert("ClanWorld: same owner");
        vm.prank(elderA);
        world.transferClanOwnership(clanA, elderA);
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

    function test_goldTransfer_expiredProposalsDoNotConsumeCap() public {
        (uint32 clanA, uint32 clanB,) = _mintThreeClans();

        uint64 expiryTick = world.getWorldState().currentTick + 10;
        for (uint256 i = 0; i < world.MAX_OPEN_OTC_PROPOSALS_PER_CLAN(); i++) {
            _propose(clanA, clanB, 1, expiryTick);
        }

        vm.expectRevert("ERR_OTC_CAP");
        _propose(clanA, clanB, 1, expiryTick);

        _advanceTicks(11);

        uint256 newProposalId = _propose(clanA, clanB, 1, world.getWorldState().currentTick + 10);
        assertGt(newProposalId, world.MAX_OPEN_OTC_PROPOSALS_PER_CLAN(), "expired slots reaped on propose");
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
        proposalId = world.proposeGoldTransfer(fromClanId, toClanId, amount, expiryTick);
    }

    function _advanceTick() internal {
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        world.heartbeat();
    }

    function _advanceTicks(uint64 ticks) internal {
        for (uint64 i = 0; i < ticks; i++) {
            _advanceTick();
        }
    }
}
