// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ClanState, IClanWorldEvents} from "../../IClanWorld.sol";
import {LibScoring} from "../../lib/LibScoring.sol";
import {LibSettlement} from "../lib/LibSettlement.sol";
import {LibStorage} from "../lib/LibStorage.sol";

contract FinalizeSeasonFacet is IClanWorldEvents {
    uint256 private constant MAX_CLAN_SCAN_FOR_RANKING = 24;

    function finalizeSeason() external {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        LibStorage.enterNonReentrant(s);
        require(s.initialized, "ClanWorld: not initialized");
        require(s.world.currentTick >= s.world.seasonEndTick, "ClanWorld: season not ended");
        require(!s.world.seasonFinalized, "ClanWorld: season finalized");

        for (uint256 i = 0; i < s.allClanIds.length; i++) {
            uint32 clanId = s.allClanIds[i];
            LibSettlement.SettlementSimulation memory sim =
                LibSettlement.simulateToTick(s, clanId, s.world.currentTick);
            LibSettlement.commitSimulation(s, sim);
        }

        (uint32[] memory rankedClanIds, uint256[] memory scores) = _computeRankings(s);

        s.world.seasonFinalized = true;
        emit SeasonFinalized(uint64(s.world.seasonEndTick), rankedClanIds, scores);
        LibStorage.exitNonReentrant(s);
    }

    function _computeRankings(LibStorage.AppStorage storage s)
        private
        view
        returns (uint32[] memory clanIdsRanked, uint256[] memory scores)
    {
        uint256 scanCount = s.allClanIds.length;
        if (scanCount > MAX_CLAN_SCAN_FOR_RANKING) scanCount = MAX_CLAN_SCAN_FOR_RANKING;

        uint32[] memory tempClanIds = new uint32[](scanCount);
        uint256[] memory tempScores = new uint256[](scanCount);
        uint256 liveCount;

        for (uint256 i = 0; i < scanCount; i++) {
            uint32 clanId = s.allClanIds[i];
            LibSettlement.SettlementSimulation memory sim = LibSettlement.simulateToTick(s, clanId, s.world.currentTick);
            if (sim.clan.clanState != ClanState.ACTIVE) continue;

            uint256 score = _clanScore(s, clanId, sim);
            tempClanIds[liveCount] = clanId;
            tempScores[liveCount] = score;
            liveCount++;
        }

        for (uint256 i = 1; i < liveCount; i++) {
            uint32 keyClanId = tempClanIds[i];
            uint256 keyScore = tempScores[i];
            uint256 j = i;
            while (j > 0 && LibScoring.rankingComesAfter(tempClanIds[j - 1], tempScores[j - 1], keyClanId, keyScore)) {
                tempClanIds[j] = tempClanIds[j - 1];
                tempScores[j] = tempScores[j - 1];
                j--;
            }
            tempClanIds[j] = keyClanId;
            tempScores[j] = keyScore;
        }

        clanIdsRanked = new uint32[](liveCount);
        scores = new uint256[](liveCount);
        for (uint256 i = 0; i < liveCount; i++) {
            clanIdsRanked[i] = tempClanIds[i];
            scores[i] = tempScores[i];
        }
    }

    function _clanScore(LibStorage.AppStorage storage s, uint32 clanId, LibSettlement.SettlementSimulation memory sim)
        private
        view
        returns (uint256 score)
    {
        uint8 monumentLevel = sim.clan.monumentLevel;
        uint64 monumentReachedAtTick;
        if (monumentLevel > 0) {
            monumentReachedAtTick = s.monumentLevelReachedAt[clanId][monumentLevel];
            if (monumentReachedAtTick == 0) {
                monumentReachedAtTick = sim.simMonumentReachedAt[monumentLevel];
            }
        }

        (score,,) = LibScoring.packClanScore(sim.clan, monumentReachedAtTick, monumentLevel);
    }
}
