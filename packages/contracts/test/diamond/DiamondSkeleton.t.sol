// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DiamondSelectors} from "../../script/DiamondSelectors.sol";
import {Diamond} from "../../src/diamond/Diamond.sol";
import {ClanWorld} from "../../src/ClanWorld.sol";
import {ClanWorldDiamondInit} from "../../src/diamond/ClanWorldDiamondInit.sol";
import {
    IClanWorld,
    ActiveBanditView,
    ActionType,
    BanditState,
    BanditTroop,
    Clan,
    ClanFullView,
    ClanWorldConstants,
    ClanOrder,
    ClansmanState,
    Clansman,
    DerivedClanState,
    DerivedClansmanState,
    MarketState,
    Mission,
    OrderResult,
    PoolSeedConfig,
    RegionOccupant,
    ResourceType,
    StatusCode,
    TreasuryState,
    WithdrawResourcesData,
    WheatPlot,
    WorldSnapshot,
    WorldState
} from "../../src/IClanWorld.sol";
import {IDiamondCut} from "../../src/diamond/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/diamond/IDiamondLoupe.sol";
import {DiamondCutFacet} from "../../src/diamond/facets/DiamondCutFacet.sol";
import {BanditViewsFacet} from "../../src/diamond/facets/BanditViewsFacet.sol";
import {BlueprintTransferFacet} from "../../src/diamond/facets/BlueprintTransferFacet.sol";
import {BundleTransferFacet} from "../../src/diamond/facets/BundleTransferFacet.sol";
import {ClanFullViewFacet} from "../../src/diamond/facets/ClanFullViewFacet.sol";
import {ClanLifecycleFacet} from "../../src/diamond/facets/ClanLifecycleFacet.sol";
import {ClanOwnershipFacet} from "../../src/diamond/facets/ClanOwnershipFacet.sol";
import {DerivedViewsFacet} from "../../src/diamond/facets/DerivedViewsFacet.sol";
import {DiamondLoupeFacet} from "../../src/diamond/facets/DiamondLoupeFacet.sol";
import {FinalizeSeasonFacet} from "../../src/diamond/facets/FinalizeSeasonFacet.sol";
import {GoldTransferFacet} from "../../src/diamond/facets/GoldTransferFacet.sol";
import {HeartbeatFacet} from "../../src/diamond/facets/HeartbeatFacet.sol";
import {MarketViewsFacet} from "../../src/diamond/facets/MarketViewsFacet.sol";
import {MinimalERC20} from "../../src/MinimalERC20.sol";
import {OwnershipFacet} from "../../src/diamond/facets/OwnershipFacet.sol";
import {QuoteViewsFacet} from "../../src/diamond/facets/QuoteViewsFacet.sol";
import {RawBanditViewsFacet} from "../../src/diamond/facets/RawBanditViewsFacet.sol";
import {RawClanViewsFacet} from "../../src/diamond/facets/RawClanViewsFacet.sol";
import {RawTreasuryViewsFacet} from "../../src/diamond/facets/RawTreasuryViewsFacet.sol";
import {RawWorldViewsFacet} from "../../src/diamond/facets/RawWorldViewsFacet.sol";
import {RegionViewsFacet} from "../../src/diamond/facets/RegionViewsFacet.sol";
import {ScoringViewsFacet} from "../../src/diamond/facets/ScoringViewsFacet.sol";
import {SettlementFacet} from "../../src/diamond/facets/SettlementFacet.sol";
import {SnapshotViewsFacet} from "../../src/diamond/facets/SnapshotViewsFacet.sol";
import {SubmitOrdersFacet} from "../../src/diamond/facets/SubmitOrdersFacet.sol";
import {StubPool} from "../../src/StubPool.sol";
import {TreasuryFacet} from "../../src/diamond/facets/TreasuryFacet.sol";
import {VaultResourceTransferFacet} from "../../src/diamond/facets/VaultResourceTransferFacet.sol";
import {LibBanditCombat} from "../../src/diamond/lib/LibBanditCombat.sol";
import {LibDiamond} from "../../src/diamond/lib/LibDiamond.sol";
import {LibOrderDefenders} from "../../src/diamond/lib/LibOrderDefenders.sol";
import {LibStorage} from "../../src/diamond/lib/LibStorage.sol";

contract PingFacet {
    function ping() external pure returns (uint256) {
        return 42;
    }
}

interface IPing {
    function ping() external view returns (uint256);
}

interface IOwnershipFacet {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

interface ISetWorldClock {
    function setWorldClock(
        uint64 currentTick,
        uint64 nextHeartbeatAtTick,
        uint64 nextHeartbeatAtTs,
        uint64 nextBanditSpawnEligibleTick,
        uint16 currentBanditSpawnChanceBps,
        bytes32 tickSeed
    ) external;
}

contract SetWorldClockFacet {
    function setWorldClock(
        uint64 currentTick,
        uint64 nextHeartbeatAtTick,
        uint64 nextHeartbeatAtTs,
        uint64 nextBanditSpawnEligibleTick,
        uint16 currentBanditSpawnChanceBps,
        bytes32 tickSeed
    ) external {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        s.world.currentTick = currentTick;
        s.world.nextHeartbeatAtTick = nextHeartbeatAtTick;
        s.world.nextHeartbeatAtTs = nextHeartbeatAtTs;
        s.world.nextBanditSpawnEligibleTick = nextBanditSpawnEligibleTick;
        s.world.currentBanditSpawnChanceBps = currentBanditSpawnChanceBps;
        s.world.currentTickSeed = tickSeed;
        s.tickSeeds[currentTick] = tickSeed;
    }
}

contract CoreBanditHarness is ClanWorld {
    function spawnBandit(uint8 region, uint32 strength) external returns (uint32) {
        return _spawnBandit(region, strength);
    }
}

interface ISpawnBandit {
    function spawnBandit(uint8 region, uint32 strength) external returns (uint32);
}

interface IBanditCleanupHarness {
    function registerTargetDefender(uint32 defenderClanId, uint32 targetClanId) external returns (uint32 clansmanId);
    function forceBanditAttack(uint32 banditId, uint32 targetClanId) external;
    function markClanDead(uint32 clanId, uint64 tick) external;
}

contract SpawnBanditFacet {
    function spawnBandit(uint8 region, uint32 strength) external returns (uint32 id) {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        require(
            region >= ClanWorldConstants.REGION_FOREST && region <= ClanWorldConstants.REGION_DEEP_SEA,
            "ClanWorld: invalid bandit region"
        );
        require(
            region != ClanWorldConstants.REGION_UNICORN_TOWN && region != ClanWorldConstants.REGION_DEEP_SEA,
            "ClanWorld: forbidden bandit region"
        );
        require(strength > 0, "ClanWorld: invalid bandit strength");

        id = s.nextBanditId++;
        s.bandits[id] = BanditTroop({
            id: id,
            region: region,
            state: BanditState.Spawned,
            targetClanId: 0,
            tickEnteredState: s.world.currentTick,
            strength: strength,
            tier: _tierForBanditAttackPower(strength),
            attackAttemptsMade: 0,
            carryWood: 0,
            carryIron: 0,
            carryWheat: 0,
            carryFish: 0,
            carryGold: 0
        });
        s.banditsByRegion[region].push(id);
        s.activeBanditCount += 1;
        s.banditSpawnByRegion[region].lastSpawnTick = s.world.currentTick;
        s.banditSpawnByRegion[region].probabilityAccum = 0;
        if (s.world.activeBanditId == ClanWorldConstants.BANDIT_ID_NULL) {
            s.world.activeBanditId = id;
        }
    }

    function _tierForBanditAttackPower(uint32 attackPower) private pure returns (uint8) {
        if (attackPower == 30) return 1;
        if (attackPower == 45) return 2;
        if (attackPower == 60) return 3;
        if (attackPower == 80) return 4;
        if (attackPower == 95) return 5;
        return 0;
    }
}

contract BanditCleanupHarnessFacet {
    function registerTargetDefender(uint32 defenderClanId, uint32 targetClanId) external returns (uint32 clansmanId) {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        clansmanId = s.clanClansmanIds[defenderClanId][0];
        uint8 targetRegion = s.clans[targetClanId].baseRegion;

        s.clansmen[clansmanId].state = ClansmanState.ACTING;
        s.clansmen[clansmanId].currentRegion = targetRegion;
        s.missions[clansmanId].active = true;
        s.missions[clansmanId].action = ActionType.DefendBase;
        s.missions[clansmanId].targetClanId = targetClanId;
        LibOrderDefenders.registerDefender(s, targetRegion, defenderClanId, clansmanId);
    }

    function forceBanditAttack(uint32 banditId, uint32 targetClanId) external {
        LibStorage.AppStorage storage s = LibStorage.appStorage();
        s.bandits[banditId].state = BanditState.Attacking;
        s.bandits[banditId].targetClanId = targetClanId;
        s.bandits[banditId].tickEnteredState = s.world.currentTick;
    }

    function markClanDead(uint32 clanId, uint64 tick) external {
        LibBanditCombat.markClanDead(LibStorage.appStorage(), clanId, "test", tick);
    }
}

contract DiamondSkeletonTest is Test {
    bytes32 private constant CLAN_SETTLED_TOPIC = keccak256("ClanSettled(uint32,uint64)");
    bytes32 private constant MISSION_COMPLETED_TOPIC = keccak256("MissionCompleted(uint32,uint32,uint64,uint8)");
    bytes32 private constant WORKER_ARRIVED_TOPIC = keccak256("WorkerArrived(uint32,uint32,uint8,uint64)");

    Diamond diamond;
    DiamondCutFacet cutFacet;

    function setUp() public {
        cutFacet = new DiamondCutFacet();
        diamond = new Diamond(address(this), address(cutFacet));
    }

    function testOwnerCanAddAndRouteFacetSelector() public {
        PingFacet pingFacet = new PingFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PingFacet.ping.selector;

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(pingFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        assertEq(IPing(address(diamond)).ping(), 42);
    }

    function testLoupeReportsAddedSelector() public {
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(loupeFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        assertEq(IDiamondLoupe(address(diamond)).facetAddress(IDiamondLoupe.facets.selector), address(loupeFacet));
        assertEq(IDiamondLoupe(address(diamond)).facetAddresses().length, 2);
    }

    function testOnlyOwnerCanDiamondCut() public {
        PingFacet pingFacet = new PingFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PingFacet.ping.selector;

        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(pingFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
    }

    function testOwnershipFacetTransfersDiamondCutAuthority() public {
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        IDiamondCut(address(diamond)).diamondCut(_adminOwnershipCut(address(ownershipFacet)), address(0), "");

        address newOwner = address(0xCAFE);
        assertEq(IOwnershipFacet(address(diamond)).owner(), address(this));
        IOwnershipFacet(address(diamond)).transferOwnership(newOwner);
        assertEq(IOwnershipFacet(address(diamond)).owner(), newOwner);

        PingFacet pingFacet = new PingFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PingFacet.ping.selector;
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(pingFacet), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.expectRevert();
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        vm.prank(newOwner);
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");
        assertEq(IPing(address(diamond)).ping(), 42);
    }

    function testDiamondCutRejectsNoCodeFacetAndInit() public {
        address noCode = address(0xBEEF);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = PingFacet.ping.selector;
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: noCode, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.expectRevert(abi.encodeWithSelector(LibDiamond.DiamondFacetHasNoCode.selector, noCode));
        IDiamondCut(address(diamond)).diamondCut(cut, address(0), "");

        IDiamondCut.FacetCut[] memory emptyCut = new IDiamondCut.FacetCut[](0);
        vm.expectRevert(abi.encodeWithSelector(LibDiamond.DiamondFacetHasNoCode.selector, noCode));
        IDiamondCut(address(diamond)).diamondCut(emptyCut, noCode, "");
    }

    function testProductionDiamondRoutesEveryExpectedSelector() public {
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();

        IDiamondCut(address(diamond))
            .diamondCut(_productionCut(address(loupeFacet)), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));

        bytes4[] memory selectors = _expectedProductionSelectors();
        for (uint256 i = 0; i < selectors.length; i++) {
            assertTrue(
                IDiamondLoupe(address(diamond)).facetAddress(selectors[i]) != address(0),
                "missing expected selector"
            );
            for (uint256 j = i + 1; j < selectors.length; j++) {
                assertTrue(selectors[i] != selectors[j], "duplicate expected selector");
            }
        }
    }

    function testCanInitializeDiamondAndReadRawWorldState() public {
        ClanWorld core = new ClanWorld();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));

        IClanWorld diamondWorld = IClanWorld(address(diamond));
        WorldState memory expected = core.getWorldState();
        WorldState memory actual = diamondWorld.getWorldState();
        _assertWorldStateEq(actual, expected);
        _assertTreasuryStateEq(diamondWorld.getTreasuryState(), core.getTreasuryState());

        assertEq(diamondWorld.isWinter(), core.isWinter());
        assertEq(diamondWorld.getActionDuration(ActionType.ChopWood), core.getActionDuration(ActionType.ChopWood));
        assertEq(diamondWorld.getTravelTicks(1, 8), core.getTravelTicks(1, 8));
        assertEq(diamondWorld.getResourceToken(0), core.getResourceToken(0));
        assertEq(diamondWorld.getPool(0), core.getPool(0));

        (uint256 wallWood, uint256 wallIron) = diamondWorld.getWallUpgradeCost(2);
        (uint256 coreWallWood, uint256 coreWallIron) = core.getWallUpgradeCost(2);
        assertEq(wallWood, coreWallWood);
        assertEq(wallIron, coreWallIron);

        assertEq(diamondWorld.getClanIds().length, 0);
        assertEq(uint8(diamondWorld.getBandit(1).state), 0);
    }

    function testDiamondInitCannotRunTwice() public {
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));

        IDiamondCut.FacetCut[] memory emptyCut = new IDiamondCut.FacetCut[](0);
        vm.expectRevert(ClanWorldDiamondInit.ClanWorldDiamondAlreadyInitialized.selector);
        IDiamondCut(address(diamond)).diamondCut(emptyCut, address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
    }

    function testDiamondMintClanMatchesCoreInitialState() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId, uint256 coreIftTokenId) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId, uint256 diamondIftTokenId) = IClanWorld(address(diamond)).mintClan(elder);

        assertEq(diamondClanId, coreClanId);
        assertEq(diamondIftTokenId, coreIftTokenId);
        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondClanId), core.getClan(coreClanId));
        assertEq(IClanWorld(address(diamond)).getClanIds().length, core.getClanIds().length);
        assertEq(IClanWorld(address(diamond)).getActiveDefenders(diamondClanId).length, 0);

        uint32[] memory diamondClansmen = IClanWorld(address(diamond)).getClanClansmanIds(diamondClanId);
        uint32[] memory coreClansmen = core.getClanClansmanIds(coreClanId);
        assertEq(diamondClansmen.length, coreClansmen.length);
        for (uint256 i = 0; i < coreClansmen.length; i++) {
            assertEq(diamondClansmen[i], coreClansmen[i]);
            _assertClansmanEq(
                IClanWorld(address(diamond)).getClansman(diamondClansmen[i]), core.getClansman(coreClansmen[i])
            );
        }

        (WheatPlot memory diamondWest, WheatPlot memory diamondEast) =
            IClanWorld(address(diamond)).getWheatPlots(diamondClanId);
        (WheatPlot memory coreWest, WheatPlot memory coreEast) = core.getWheatPlots(coreClanId);
        _assertWheatPlotEq(diamondWest, coreWest);
        _assertWheatPlotEq(diamondEast, coreEast);
    }

    function testDiamondTreasuryInitAndSeedPools() public {
        TreasuryFacet treasuryFacet = new TreasuryFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_treasuryCut(address(treasuryFacet)), address(0), "");

        (address[6] memory tokens, address[4] memory pools) = _deployTreasuryBoundary(address(diamond));
        PoolSeedConfig memory cfg = _seedConfig();
        _seedAndApproveTreasury(tokens, address(diamond), cfg);

        IClanWorld diamondWorld = IClanWorld(address(diamond));
        diamondWorld.initTreasury(tokens, pools);
        TreasuryState memory initialized = diamondWorld.getTreasuryState();
        assertEq(initialized.woodToken, tokens[0], "wood token");
        assertEq(initialized.ironToken, tokens[1], "iron token");
        assertEq(initialized.wheatToken, tokens[2], "wheat token");
        assertEq(initialized.fishToken, tokens[3], "fish token");
        assertEq(initialized.goldToken, tokens[4], "gold token");
        assertEq(initialized.blueprintToken, tokens[5], "blueprint token");
        assertEq(initialized.woodGoldPool, pools[0], "wood pool");
        assertEq(initialized.wheatGoldPool, pools[1], "wheat pool");
        assertEq(initialized.fishGoldPool, pools[2], "fish pool");
        assertEq(initialized.ironGoldPool, pools[3], "iron pool");
        assertEq(initialized.poolsSeeded, false, "seeded before seedPools");

        diamondWorld.seedPools(cfg);
        assertEq(diamondWorld.getTreasuryState().poolsSeeded, true, "pools seeded");
        _assertPoolReserves(pools[0], cfg.woodSeed, cfg.goldSeedForWood);
        _assertPoolReserves(pools[1], cfg.wheatSeed, cfg.goldSeedForWheat);
        _assertPoolReserves(pools[2], cfg.fishSeed, cfg.goldSeedForFish);
        _assertPoolReserves(pools[3], cfg.ironSeed, cfg.goldSeedForIron);
    }

    function testDiamondBasicDerivedViewsMatchCoreAfterMint() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        DerivedViewsFacet derivedViewsFacet = new DerivedViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_derivedViewsCut(address(derivedViewsFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        DerivedClanState memory diamondClan = IClanWorld(address(diamond)).getDerivedClanState(diamondClanId);
        DerivedClanState memory coreClan = core.getDerivedClanState(coreClanId);
        _assertDerivedClanStateEq(diamondClan, coreClan);

        uint32 clansmanId = core.getClanClansmanIds(coreClanId)[0];
        DerivedClansmanState memory diamondClansman = IClanWorld(address(diamond)).getDerivedClansmanState(clansmanId);
        DerivedClansmanState memory coreClansman = core.getDerivedClansmanState(clansmanId);
        _assertDerivedClansmanStateEq(diamondClansman, coreClansman);

        DerivedClansmanState memory missing = IClanWorld(address(diamond)).getDerivedClansmanState(999);
        assertEq(missing.effectiveRegion, 0);
        assertEq(missing.derivedAtTick, core.getWorldState().currentTick);
    }

    function testDiamondMarketStateMatchesCoreDefaults() public {
        ClanWorld core = new ClanWorld();
        MarketViewsFacet marketViewsFacet = new MarketViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_marketViewsCut(address(marketViewsFacet)), address(0), "");

        _assertMarketStateEq(IClanWorld(address(diamond)).getMarketState(), core.getMarketState());
    }

    function testDiamondActiveBanditViewMatchesCoreDefault() public {
        ClanWorld core = new ClanWorld();
        BanditViewsFacet banditViewsFacet = new BanditViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_banditViewsCut(address(banditViewsFacet)), address(0), "");

        _assertActiveBanditViewEq(IClanWorld(address(diamond)).getActiveBanditView(), core.getActiveBanditView());
    }

    function testDiamondRegionPopulationMatchesCoreAfterMint() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        RegionViewsFacet regionViewsFacet = new RegionViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_regionViewsCut(address(regionViewsFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        uint8 baseRegion = core.getClan(coreClanId).baseRegion;
        assertEq(baseRegion, IClanWorld(address(diamond)).getClan(diamondClanId).baseRegion);
        _assertRegionPopulationEq(
            IClanWorld(address(diamond)).getRegionPopulation(baseRegion), core.getRegionPopulation(baseRegion)
        );
    }

    function testDiamondWorldSnapshotMatchesCoreAfterMint() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        SnapshotViewsFacet snapshotViewsFacet = new SnapshotViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_snapshotViewsCut(address(snapshotViewsFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        core.mintClan(elder);
        vm.prank(elder);
        IClanWorld(address(diamond)).mintClan(elder);

        _assertWorldSnapshotEq(IClanWorld(address(diamond)).getWorldSnapshot(), core.getWorldSnapshot());
    }

    function testDiamondClanFullViewMatchesCoreAfterMint() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        ClanFullViewFacet clanFullViewFacet = new ClanFullViewFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_clanFullViewCut(address(clanFullViewFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        _assertClanFullViewEq(
            IClanWorld(address(diamond)).getClanFullView(diamondClanId), core.getClanFullView(coreClanId)
        );
    }

    function testDiamondQuoteViewsMatchCoreAfterMint() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        QuoteViewsFacet quoteViewsFacet = new QuoteViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_quoteViewsCut(address(quoteViewsFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        assertEq(IClanWorld(address(diamond)).quoteLootValueRaw(diamondClanId), core.quoteLootValueRaw(coreClanId));
        assertEq(IClanWorld(address(diamond)).getBanditTargetPreview(1), core.getBanditTargetPreview(1));

        for (uint8 src = 0; src <= 8; src++) {
            for (uint8 dst = 0; dst <= 8; dst++) {
                (uint8 diamondTicks, bytes8 diamondPath) = IClanWorld(address(diamond)).quoteTravel(src, dst);
                (uint8 coreTicks, bytes8 corePath) = core.quoteTravel(src, dst);
                assertEq(diamondTicks, coreTicks, "travel ticks");
                assertEq(diamondPath, corePath, "travel path");
            }
        }
    }

    function testDiamondScoringViewsMatchCoreAfterMint() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        ScoringViewsFacet scoringViewsFacet = new ScoringViewsFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_scoringViewsCut(address(scoringViewsFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        assertEq(
            IClanWorld(address(diamond)).quoteLootValueSettled(diamondClanId),
            core.quoteLootValueSettled(coreClanId),
            "settled loot"
        );

        (uint256 diamondScore, uint64 diamondReached, uint8 diamondLevel) =
            IClanWorld(address(diamond)).getClanScore(diamondClanId);
        (uint256 coreScore, uint64 coreReached, uint8 coreLevel) = core.getClanScore(coreClanId);
        assertEq(diamondScore, coreScore, "score");
        assertEq(diamondReached, coreReached, "monument reached");
        assertEq(diamondLevel, coreLevel, "monument level");

        (uint32[] memory diamondRanked, uint256[] memory diamondScores) = IClanWorld(address(diamond)).getRankings();
        (uint32[] memory coreRanked, uint256[] memory coreScores) = core.getRankings();
        assertEq(diamondRanked.length, coreRanked.length, "ranked length");
        assertEq(diamondScores.length, coreScores.length, "rank scores length");
        for (uint256 i = 0; i < coreRanked.length; i++) {
            assertEq(diamondRanked[i], coreRanked[i], "ranked clan");
            assertEq(diamondScores[i], coreScores[i], "rank score");
        }
    }

    function testDiamondSettleClanMatchesCoreAfterHeartbeatUpkeep() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        SettlementFacet settlementFacet = new SettlementFacet();
        SetWorldClockFacet setWorldClockFacet = new SetWorldClockFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_settlementCut(address(settlementFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_setWorldClockCut(address(setWorldClockFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        WorldState memory coreWorld = core.getWorldState();
        ISetWorldClock(address(diamond))
            .setWorldClock(
                coreWorld.currentTick,
                coreWorld.nextHeartbeatAtTick,
                coreWorld.nextHeartbeatAtTs,
                coreWorld.nextBanditSpawnEligibleTick,
                coreWorld.currentBanditSpawnChanceBps,
                coreWorld.currentTickSeed
            );
        IClanWorld(address(diamond)).settleClan(diamondClanId);

        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondClanId), core.getClan(coreClanId));
        _assertWorldStateEq(IClanWorld(address(diamond)).getWorldState(), core.getWorldState());
        uint32[] memory coreClansmen = core.getClanClansmanIds(coreClanId);
        for (uint256 i = 0; i < coreClansmen.length; i++) {
            _assertClansmanEq(
                IClanWorld(address(diamond)).getClansman(coreClansmen[i]), core.getClansman(coreClansmen[i])
            );
        }
    }

    function testDiamondHeartbeatAdvancesEmptyWorldLikeCore() public {
        ClanWorld core = new ClanWorld();
        HeartbeatFacet heartbeatFacet = new HeartbeatFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_heartbeatCut(address(heartbeatFacet)), address(0), "");

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        IClanWorld(address(diamond)).heartbeat();
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        IClanWorld(address(diamond)).heartbeat();
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        IClanWorld(address(diamond)).heartbeat();

        _assertWorldStateEq(IClanWorld(address(diamond)).getWorldState(), core.getWorldState());
    }

    function testDiamondHeartbeatAdvancesSpawnedBanditToCampedLikeCore() public {
        CoreBanditHarness core = new CoreBanditHarness();
        HeartbeatFacet heartbeatFacet = new HeartbeatFacet();
        SpawnBanditFacet spawnBanditFacet = new SpawnBanditFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_heartbeatCut(address(heartbeatFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_spawnBanditCut(address(spawnBanditFacet)), address(0), "");

        uint32 coreBanditId = core.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);
        uint32 diamondBanditId = ISpawnBandit(address(diamond)).spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        IClanWorld(address(diamond)).heartbeat();
        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        IClanWorld(address(diamond)).heartbeat();

        _assertWorldStateEq(IClanWorld(address(diamond)).getWorldState(), core.getWorldState());
        _assertBanditEq(IClanWorld(address(diamond)).getBandit(diamondBanditId), core.getBandit(coreBanditId));
        assertEq(uint8(IClanWorld(address(diamond)).getBandit(diamondBanditId).state), uint8(BanditState.Camped));
        assertEq(IClanWorld(address(diamond)).getBanditsInRegion(ClanWorldConstants.REGION_FOREST).length, 1);
    }

    function testDiamondHeartbeatRestsCampedBanditWithoutTargetLikeCore() public {
        CoreBanditHarness core = new CoreBanditHarness();
        HeartbeatFacet heartbeatFacet = new HeartbeatFacet();
        SpawnBanditFacet spawnBanditFacet = new SpawnBanditFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_heartbeatCut(address(heartbeatFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_spawnBanditCut(address(spawnBanditFacet)), address(0), "");

        uint32 coreBanditId = core.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);
        uint32 diamondBanditId = ISpawnBandit(address(diamond)).spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            core.heartbeat();
            IClanWorld(address(diamond)).heartbeat();
        }

        _assertWorldStateEq(IClanWorld(address(diamond)).getWorldState(), core.getWorldState());
        _assertBanditEq(IClanWorld(address(diamond)).getBandit(diamondBanditId), core.getBandit(coreBanditId));
        assertEq(uint8(IClanWorld(address(diamond)).getBandit(diamondBanditId).state), uint8(BanditState.Resting));
        assertEq(IClanWorld(address(diamond)).getBandit(diamondBanditId).attackAttemptsMade, 1);
    }

    function testDiamondHeartbeatResolvesBanditAttackLikeCore() public {
        CoreBanditHarness core = new CoreBanditHarness();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        HeartbeatFacet heartbeatFacet = new HeartbeatFacet();
        SpawnBanditFacet spawnBanditFacet = new SpawnBanditFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();
        address elder = address(0xBEEF);

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_heartbeatCut(address(heartbeatFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_spawnBanditCut(address(spawnBanditFacet)), address(0), "");

        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);
        uint32 coreBanditId = core.spawnBandit(ClanWorldConstants.REGION_FOREST, 100);
        uint32 diamondBanditId = ISpawnBandit(address(diamond)).spawnBandit(ClanWorldConstants.REGION_FOREST, 100);

        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
            core.heartbeat();
            IClanWorld(address(diamond)).heartbeat();
        }

        _assertWorldStateEq(IClanWorld(address(diamond)).getWorldState(), core.getWorldState());
        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondClanId), core.getClan(coreClanId));
        _assertBanditEq(IClanWorld(address(diamond)).getBandit(diamondBanditId), core.getBandit(coreBanditId));
        assertEq(uint8(IClanWorld(address(diamond)).getBandit(diamondBanditId).state), uint8(BanditState.Resting));
        assertEq(IClanWorld(address(diamond)).getBandit(diamondBanditId).targetClanId, 0);
    }

    function testDiamondMarkClanDeadCleansDefendersReservationsAndBanditTargets() public {
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        SpawnBanditFacet spawnBanditFacet = new SpawnBanditFacet();
        BanditCleanupHarnessFacet cleanupFacet = new BanditCleanupHarnessFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();
        address defenderOwner = address(0xA11CE);
        address targetOwner = address(0xB0B);

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_spawnBanditCut(address(spawnBanditFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_banditCleanupHarnessCut(address(cleanupFacet)), address(0), "");

        vm.prank(defenderOwner);
        (uint32 defenderClanId,) = IClanWorld(address(diamond)).mintClan(defenderOwner);
        vm.prank(targetOwner);
        (uint32 targetClanId,) = IClanWorld(address(diamond)).mintClan(targetOwner);

        uint32 defenderId =
            IBanditCleanupHarness(address(diamond)).registerTargetDefender(defenderClanId, targetClanId);
        uint32 banditId = ISpawnBandit(address(diamond)).spawnBandit(
            IClanWorld(address(diamond)).getClan(targetClanId).baseRegion, 100
        );
        IBanditCleanupHarness(address(diamond)).forceBanditAttack(banditId, targetClanId);

        assertEq(IClanWorld(address(diamond)).getActiveDefenders(targetClanId).length, 1, "defender registered");
        assertTrue(IClanWorld(address(diamond)).getActiveMission(defenderId).active, "defender mission active");

        IBanditCleanupHarness(address(diamond)).markClanDead(targetClanId, 7);

        assertEq(uint8(IClanWorld(address(diamond)).getClansman(defenderId).state), uint8(ClansmanState.WAITING));
        assertFalse(IClanWorld(address(diamond)).getActiveMission(defenderId).active, "defender mission cleared");
        assertEq(IClanWorld(address(diamond)).getActiveDefenders(targetClanId).length, 0, "defender registry cleared");
        assertEq(uint8(IClanWorld(address(diamond)).getBandit(banditId).state), uint8(BanditState.Escaped));
        assertEq(IClanWorld(address(diamond)).getBandit(banditId).targetClanId, 0, "bandit target cleared");
    }

    function testDiamondHeartbeatUpdatesBanditSpawnPreviewLikeCore() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        HeartbeatFacet heartbeatFacet = new HeartbeatFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();
        address elder = address(0xBEEF);

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_heartbeatCut(address(heartbeatFacet)), address(0), "");

        vm.prank(elder);
        core.mintClan(elder);
        vm.prank(elder);
        IClanWorld(address(diamond)).mintClan(elder);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        IClanWorld(address(diamond)).heartbeat();

        _assertWorldStateEq(IClanWorld(address(diamond)).getWorldState(), core.getWorldState());
        uint32 activeBanditId = core.getWorldState().activeBanditId;
        if (activeBanditId != ClanWorldConstants.BANDIT_ID_NULL) {
            _assertBanditEq(IClanWorld(address(diamond)).getBandit(activeBanditId), core.getBandit(activeBanditId));
        }
    }

    function testDiamondFinalizeSeasonRejectsBeforeSeasonEndLikeCore() public {
        ClanWorld core = new ClanWorld();
        FinalizeSeasonFacet finalizeSeasonFacet = new FinalizeSeasonFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_seasonCut(address(finalizeSeasonFacet)), address(0), "");

        vm.expectRevert(bytes("ClanWorld: season not ended"));
        core.finalizeSeason();
        vm.expectRevert(bytes("ClanWorld: season not ended"));
        IClanWorld(address(diamond)).finalizeSeason();
    }

    function testDiamondFinalizeSeasonBeforeInitReverts() public {
        FinalizeSeasonFacet finalizeSeasonFacet = new FinalizeSeasonFacet();

        IDiamondCut(address(diamond)).diamondCut(_seasonCut(address(finalizeSeasonFacet)), address(0), "");

        vm.expectRevert(bytes("ClanWorld: not initialized"));
        IClanWorld(address(diamond)).finalizeSeason();
    }

    function testDiamondSubmitWaitOrderMatchesCore() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        SubmitOrdersFacet submitOrdersFacet = new SubmitOrdersFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_submitOrdersCut(address(submitOrdersFacet)), address(0), "");

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        uint32 coreClansmanId = core.getClanClansmanIds(coreClanId)[0];
        uint32 diamondClansmanId = IClanWorld(address(diamond)).getClanClansmanIds(diamondClanId)[0];
        uint8 coreBaseRegion = core.getClan(coreClanId).baseRegion;
        uint8 diamondBaseRegion = IClanWorld(address(diamond)).getClan(diamondClanId).baseRegion;

        ClanOrder[] memory coreOrders = new ClanOrder[](1);
        coreOrders[0] = ClanOrder({
            clansmanId: coreClansmanId,
            gotoRegion: coreBaseRegion,
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
        ClanOrder[] memory diamondOrders = new ClanOrder[](1);
        diamondOrders[0] = ClanOrder({
            clansmanId: diamondClansmanId,
            gotoRegion: diamondBaseRegion,
            action: ActionType.Wait,
            targetClanId: 0,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });

        vm.prank(elder);
        OrderResult[] memory coreResults = core.submitClanOrders(coreClanId, coreOrders);
        vm.prank(elder);
        OrderResult[] memory diamondResults =
            IClanWorld(address(diamond)).submitClanOrders(diamondClanId, diamondOrders);

        assertEq(uint8(diamondResults[0].status), uint8(coreResults[0].status), "status");
        assertEq(diamondResults[0].cooldownEndsAtTs, coreResults[0].cooldownEndsAtTs, "cooldown");
        assertEq(diamondResults[0].missionNonce, coreResults[0].missionNonce, "nonce");
        assertEq(uint8(diamondResults[0].marketMode), uint8(coreResults[0].marketMode), "market mode");
        assertEq(uint8(diamondResults[0].status), uint8(StatusCode.OK), "submit ok");

        _assertClansmanEq(IClanWorld(address(diamond)).getClansman(diamondClansmanId), core.getClansman(coreClansmanId));
        _assertMissionEq(
            IClanWorld(address(diamond)).getActiveMission(diamondClansmanId), core.getActiveMission(coreClansmanId)
        );
    }

    function testDiamondHeartbeatCompletionLogsAndCooldownMatchCore() public {
        ClanWorld core = new ClanWorld();
        _installLifecycleSubmitHeartbeatFacets();

        address elder = address(0xA11CE);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        uint32 coreClansmanId = core.getClanClansmanIds(coreClanId)[0];
        uint32 diamondClansmanId = IClanWorld(address(diamond)).getClanClansmanIds(diamondClanId)[0];
        uint8 coreBaseRegion = core.getClan(coreClanId).baseRegion;
        uint8 diamondBaseRegion = IClanWorld(address(diamond)).getClan(diamondClanId).baseRegion;

        ClanOrder[] memory coreOrders = new ClanOrder[](1);
        coreOrders[0] = _basicOrder(coreClansmanId, coreBaseRegion, ActionType.DepositResources, 0);
        ClanOrder[] memory diamondOrders = new ClanOrder[](1);
        diamondOrders[0] = _basicOrder(diamondClansmanId, diamondBaseRegion, ActionType.DepositResources, 0);

        vm.prank(elder);
        OrderResult[] memory coreResults = core.submitClanOrders(coreClanId, coreOrders);
        vm.prank(elder);
        OrderResult[] memory diamondResults =
            IClanWorld(address(diamond)).submitClanOrders(diamondClanId, diamondOrders);
        assertEq(uint8(coreResults[0].status), uint8(StatusCode.OK), "core submit ok");
        assertEq(uint8(diamondResults[0].status), uint8(StatusCode.OK), "diamond submit ok");

        uint64 submittedCooldown = core.getClansman(coreClansmanId).cooldownEndsAtTs;
        assertEq(IClanWorld(address(diamond)).getClansman(diamondClansmanId).cooldownEndsAtTs, submittedCooldown);

        uint64 settlesAtTick = core.getActiveMission(coreClansmanId).settlesAtTick;
        Vm.Log[] memory coreLogs;
        Vm.Log[] memory diamondLogs;
        while (core.getWorldState().currentTick <= settlesAtTick) {
            vm.warp(core.getWorldState().nextHeartbeatAtTs);
            bool finalHeartbeat = core.getWorldState().currentTick == settlesAtTick;
            if (finalHeartbeat) vm.recordLogs();
            core.heartbeat();
            if (finalHeartbeat) coreLogs = vm.getRecordedLogs();
            if (finalHeartbeat) vm.recordLogs();
            IClanWorld(address(diamond)).heartbeat();
            if (finalHeartbeat) diamondLogs = vm.getRecordedLogs();
        }

        _assertEventFingerprintMatch(coreLogs, address(core), diamondLogs, address(diamond), CLAN_SETTLED_TOPIC);
        _assertEventFingerprintMatch(
            coreLogs, address(core), diamondLogs, address(diamond), MISSION_COMPLETED_TOPIC
        );
        _assertClansmanEq(IClanWorld(address(diamond)).getClansman(diamondClansmanId), core.getClansman(coreClansmanId));
        assertEq(core.getClansman(coreClansmanId).cooldownEndsAtTs, submittedCooldown, "core cooldown unchanged");
        assertEq(
            IClanWorld(address(diamond)).getClansman(diamondClansmanId).cooldownEndsAtTs,
            submittedCooldown,
            "diamond cooldown unchanged"
        );
    }

    function testDiamondTraveledDefenderArrivalLogsAndRegistryMatchCore() public {
        ClanWorld core = new ClanWorld();
        _installLifecycleSubmitHeartbeatFacets();

        address defenderElder = address(0xA11CE);
        address targetElder = address(0xB0B);
        vm.prank(defenderElder);
        (uint32 coreDefenderClanId,) = core.mintClan(defenderElder);
        vm.prank(targetElder);
        (uint32 coreTargetClanId,) = core.mintClan(targetElder);
        vm.prank(defenderElder);
        (uint32 diamondDefenderClanId,) = IClanWorld(address(diamond)).mintClan(defenderElder);
        vm.prank(targetElder);
        (uint32 diamondTargetClanId,) = IClanWorld(address(diamond)).mintClan(targetElder);

        uint32 coreClansmanId = core.getClanClansmanIds(coreDefenderClanId)[0];
        uint32 diamondClansmanId = IClanWorld(address(diamond)).getClanClansmanIds(diamondDefenderClanId)[0];
        uint8 coreTargetRegion = core.getClan(coreTargetClanId).baseRegion;
        uint8 diamondTargetRegion = IClanWorld(address(diamond)).getClan(diamondTargetClanId).baseRegion;

        ClanOrder[] memory coreOrders = new ClanOrder[](1);
        coreOrders[0] = _basicOrder(coreClansmanId, coreTargetRegion, ActionType.DefendBase, coreTargetClanId);
        ClanOrder[] memory diamondOrders = new ClanOrder[](1);
        diamondOrders[0] =
            _basicOrder(diamondClansmanId, diamondTargetRegion, ActionType.DefendBase, diamondTargetClanId);

        vm.prank(defenderElder);
        OrderResult[] memory coreResults = core.submitClanOrders(coreDefenderClanId, coreOrders);
        vm.prank(defenderElder);
        OrderResult[] memory diamondResults =
            IClanWorld(address(diamond)).submitClanOrders(diamondDefenderClanId, diamondOrders);
        assertEq(uint8(coreResults[0].status), uint8(StatusCode.OK), "core defend submit ok");
        assertEq(uint8(diamondResults[0].status), uint8(StatusCode.OK), "diamond defend submit ok");
        assertGt(core.getActiveMission(coreClansmanId).arrivalTick, core.getWorldState().currentTick, "traveling setup");
        assertEq(core.getDefendingClans(coreTargetRegion).length, 0, "core not registered before arrival");
        assertEq(IClanWorld(address(diamond)).getDefendingClans(diamondTargetRegion).length, 0, "diamond not registered before arrival");

        uint64 arrivalTick = core.getActiveMission(coreClansmanId).arrivalTick;
        Vm.Log[] memory coreLogs;
        Vm.Log[] memory diamondLogs;
        while (core.getWorldState().currentTick <= arrivalTick) {
            vm.warp(core.getWorldState().nextHeartbeatAtTs);
            bool finalHeartbeat = core.getWorldState().currentTick == arrivalTick;
            if (finalHeartbeat) vm.recordLogs();
            core.heartbeat();
            if (finalHeartbeat) coreLogs = vm.getRecordedLogs();
            if (finalHeartbeat) vm.recordLogs();
            IClanWorld(address(diamond)).heartbeat();
            if (finalHeartbeat) diamondLogs = vm.getRecordedLogs();
        }

        _assertEventFingerprintMatch(coreLogs, address(core), diamondLogs, address(diamond), WORKER_ARRIVED_TOPIC);
        _assertClansmanEq(IClanWorld(address(diamond)).getClansman(diamondClansmanId), core.getClansman(coreClansmanId));
        _assertMissionEq(
            IClanWorld(address(diamond)).getActiveMission(diamondClansmanId), core.getActiveMission(coreClansmanId)
        );
        assertEq(
            IClanWorld(address(diamond)).getClansmanDefendingRegion(diamondClansmanId),
            core.getClansmanDefendingRegion(coreClansmanId),
            "defending region"
        );

        uint32[] memory coreActiveDefenders = core.getActiveDefenders(coreTargetClanId);
        uint32[] memory diamondActiveDefenders = IClanWorld(address(diamond)).getActiveDefenders(diamondTargetClanId);
        assertEq(diamondActiveDefenders.length, coreActiveDefenders.length, "active defender length");
        assertEq(diamondActiveDefenders[0], coreActiveDefenders[0], "active defender id");

        uint32[] memory coreDefendingClans = core.getDefendingClans(coreTargetRegion);
        uint32[] memory diamondDefendingClans = IClanWorld(address(diamond)).getDefendingClans(diamondTargetRegion);
        assertEq(diamondDefendingClans.length, coreDefendingClans.length, "defending clan length");
        assertEq(diamondDefendingClans[0], coreDefendingClans[0], "defending clan id");
    }

    function testDiamondTransferClanOwnershipMatchesCoreAfterSettlement() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        ClanOwnershipFacet ownershipFacet = new ClanOwnershipFacet();
        SetWorldClockFacet setWorldClockFacet = new SetWorldClockFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_ownershipCut(address(ownershipFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_setWorldClockCut(address(setWorldClockFacet)), address(0), "");

        address elder = address(0xA11CE);
        address newOwner = address(0xB0B);
        vm.prank(elder);
        (uint32 coreClanId,) = core.mintClan(elder);
        vm.prank(elder);
        (uint32 diamondClanId,) = IClanWorld(address(diamond)).mintClan(elder);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        WorldState memory coreWorld = core.getWorldState();
        ISetWorldClock(address(diamond))
            .setWorldClock(
                coreWorld.currentTick,
                coreWorld.nextHeartbeatAtTick,
                coreWorld.nextHeartbeatAtTs,
                coreWorld.nextBanditSpawnEligibleTick,
                coreWorld.currentBanditSpawnChanceBps,
                coreWorld.currentTickSeed
            );

        vm.prank(elder);
        core.transferClanOwnership(coreClanId, newOwner);
        vm.prank(elder);
        IClanWorld(address(diamond)).transferClanOwnership(diamondClanId, newOwner);

        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondClanId), core.getClan(coreClanId));
    }

    function testDiamondTransferGoldMatchesCoreAfterSettlement() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        GoldTransferFacet goldTransferFacet = new GoldTransferFacet();
        SetWorldClockFacet setWorldClockFacet = new SetWorldClockFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_goldTransferCut(address(goldTransferFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_setWorldClockCut(address(setWorldClockFacet)), address(0), "");

        address elder = address(0xA11CE);
        address recipient = address(0xB0B);
        vm.prank(elder);
        (uint32 coreFromClanId,) = core.mintClan(elder);
        vm.prank(recipient);
        (uint32 coreToClanId,) = core.mintClan(recipient);
        vm.prank(elder);
        (uint32 diamondFromClanId,) = IClanWorld(address(diamond)).mintClan(elder);
        vm.prank(recipient);
        (uint32 diamondToClanId,) = IClanWorld(address(diamond)).mintClan(recipient);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        WorldState memory coreWorld = core.getWorldState();
        ISetWorldClock(address(diamond))
            .setWorldClock(
                coreWorld.currentTick,
                coreWorld.nextHeartbeatAtTick,
                coreWorld.nextHeartbeatAtTs,
                coreWorld.nextBanditSpawnEligibleTick,
                coreWorld.currentBanditSpawnChanceBps,
                coreWorld.currentTickSeed
            );

        vm.prank(elder);
        core.transferGold(coreFromClanId, coreToClanId, 1e18);
        vm.prank(elder);
        IClanWorld(address(diamond)).transferGold(diamondFromClanId, diamondToClanId, 1e18);

        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondFromClanId), core.getClan(coreFromClanId));
        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondToClanId), core.getClan(coreToClanId));
    }

    function testDiamondTransferVaultResourceMatchesCoreAfterSettlement() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        VaultResourceTransferFacet vaultResourceTransferFacet = new VaultResourceTransferFacet();
        SetWorldClockFacet setWorldClockFacet = new SetWorldClockFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond))
            .diamondCut(_vaultResourceTransferCut(address(vaultResourceTransferFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_setWorldClockCut(address(setWorldClockFacet)), address(0), "");

        address elder = address(0xA11CE);
        address recipient = address(0xB0B);
        vm.prank(elder);
        (uint32 coreFromClanId,) = core.mintClan(elder);
        vm.prank(recipient);
        (uint32 coreToClanId,) = core.mintClan(recipient);
        vm.prank(elder);
        (uint32 diamondFromClanId,) = IClanWorld(address(diamond)).mintClan(elder);
        vm.prank(recipient);
        (uint32 diamondToClanId,) = IClanWorld(address(diamond)).mintClan(recipient);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        WorldState memory coreWorld = core.getWorldState();
        ISetWorldClock(address(diamond))
            .setWorldClock(
                coreWorld.currentTick,
                coreWorld.nextHeartbeatAtTick,
                coreWorld.nextHeartbeatAtTs,
                coreWorld.nextBanditSpawnEligibleTick,
                coreWorld.currentBanditSpawnChanceBps,
                coreWorld.currentTickSeed
            );

        vm.prank(elder);
        core.transferVaultResource(coreFromClanId, coreToClanId, ResourceType.Wood, 1e18);
        vm.prank(elder);
        IClanWorld(address(diamond)).transferVaultResource(diamondFromClanId, diamondToClanId, ResourceType.Wood, 1e18);

        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondFromClanId), core.getClan(coreFromClanId));
        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondToClanId), core.getClan(coreToClanId));
    }

    function testDiamondTransferBlueprintRejectsLikeCoreWithoutBalance() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        BlueprintTransferFacet blueprintTransferFacet = new BlueprintTransferFacet();
        SetWorldClockFacet setWorldClockFacet = new SetWorldClockFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_blueprintTransferCut(address(blueprintTransferFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_setWorldClockCut(address(setWorldClockFacet)), address(0), "");

        address elder = address(0xA11CE);
        address recipient = address(0xB0B);
        vm.prank(elder);
        (uint32 coreFromClanId,) = core.mintClan(elder);
        vm.prank(recipient);
        (uint32 coreToClanId,) = core.mintClan(recipient);
        vm.prank(elder);
        (uint32 diamondFromClanId,) = IClanWorld(address(diamond)).mintClan(elder);
        vm.prank(recipient);
        (uint32 diamondToClanId,) = IClanWorld(address(diamond)).mintClan(recipient);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        WorldState memory coreWorld = core.getWorldState();
        ISetWorldClock(address(diamond))
            .setWorldClock(
                coreWorld.currentTick,
                coreWorld.nextHeartbeatAtTick,
                coreWorld.nextHeartbeatAtTs,
                coreWorld.nextBanditSpawnEligibleTick,
                coreWorld.currentBanditSpawnChanceBps,
                coreWorld.currentTickSeed
            );

        vm.prank(elder);
        vm.expectRevert(bytes("ClanWorld: insufficient blueprints"));
        core.transferBlueprint(coreFromClanId, coreToClanId, 1e18);

        vm.prank(elder);
        vm.expectRevert(bytes("ClanWorld: insufficient blueprints"));
        IClanWorld(address(diamond)).transferBlueprint(diamondFromClanId, diamondToClanId, 1e18);
    }

    function testDiamondTransferBundleMatchesCoreAfterSettlement() public {
        ClanWorld core = new ClanWorld();
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        BundleTransferFacet bundleTransferFacet = new BundleTransferFacet();
        SetWorldClockFacet setWorldClockFacet = new SetWorldClockFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_bundleTransferCut(address(bundleTransferFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_setWorldClockCut(address(setWorldClockFacet)), address(0), "");

        address elder = address(0xA11CE);
        address recipient = address(0xB0B);
        vm.prank(elder);
        (uint32 coreFromClanId,) = core.mintClan(elder);
        vm.prank(recipient);
        (uint32 coreToClanId,) = core.mintClan(recipient);
        vm.prank(elder);
        (uint32 diamondFromClanId,) = IClanWorld(address(diamond)).mintClan(elder);
        vm.prank(recipient);
        (uint32 diamondToClanId,) = IClanWorld(address(diamond)).mintClan(recipient);

        vm.warp(block.timestamp + ClanWorldConstants.HEARTBEAT_INTERVAL_SECONDS);
        core.heartbeat();
        WorldState memory coreWorld = core.getWorldState();
        ISetWorldClock(address(diamond))
            .setWorldClock(
                coreWorld.currentTick,
                coreWorld.nextHeartbeatAtTick,
                coreWorld.nextHeartbeatAtTs,
                coreWorld.nextBanditSpawnEligibleTick,
                coreWorld.currentBanditSpawnChanceBps,
                coreWorld.currentTickSeed
            );

        vm.prank(elder);
        core.transferBundle(coreFromClanId, coreToClanId, 1e18, 0, 1e18, 0, 0, 0);
        vm.prank(elder);
        IClanWorld(address(diamond)).transferBundle(diamondFromClanId, diamondToClanId, 1e18, 0, 1e18, 0, 0, 0);

        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondFromClanId), core.getClan(coreFromClanId));
        _assertClanEq(IClanWorld(address(diamond)).getClan(diamondToClanId), core.getClan(coreToClanId));
    }

    function _installLifecycleSubmitHeartbeatFacets() internal {
        ClanLifecycleFacet lifecycleFacet = new ClanLifecycleFacet();
        SubmitOrdersFacet submitOrdersFacet = new SubmitOrdersFacet();
        HeartbeatFacet heartbeatFacet = new HeartbeatFacet();
        ClanWorldDiamondInit init = new ClanWorldDiamondInit();

        IDiamondCut(address(diamond))
            .diamondCut(_rawViewsCut(), address(init), abi.encodeCall(ClanWorldDiamondInit.init, ()));
        IDiamondCut(address(diamond)).diamondCut(_lifecycleCut(address(lifecycleFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_submitOrdersCut(address(submitOrdersFacet)), address(0), "");
        IDiamondCut(address(diamond)).diamondCut(_heartbeatCut(address(heartbeatFacet)), address(0), "");
    }

    function _basicOrder(uint32 clansmanId, uint8 gotoRegion, ActionType action, uint32 targetClanId)
        internal
        pure
        returns (ClanOrder memory)
    {
        return ClanOrder({
            clansmanId: clansmanId,
            gotoRegion: gotoRegion,
            action: action,
            targetClanId: targetClanId,
            marketToken: address(0),
            marketAmount: 0,
            maxGoldIn: 0,
            withdrawResources: WithdrawResourcesData({wood: 0, iron: 0, wheat: 0, fish: 0})
        });
    }

    function _assertEventFingerprintMatch(
        Vm.Log[] memory coreLogs,
        address coreEmitter,
        Vm.Log[] memory diamondLogs,
        address diamondEmitter,
        bytes32 topic0
    ) internal pure {
        bytes32 coreFingerprint = _singleEventFingerprint(coreLogs, coreEmitter, topic0);
        bytes32 diamondFingerprint = _singleEventFingerprint(diamondLogs, diamondEmitter, topic0);
        assertEq(diamondFingerprint, coreFingerprint, "event fingerprint");
    }

    function _singleEventFingerprint(Vm.Log[] memory logs, address emitter, bytes32 topic0)
        internal
        pure
        returns (bytes32 fingerprint)
    {
        uint256 matches;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != emitter || logs[i].topics.length == 0 || logs[i].topics[0] != topic0) continue;
            fingerprint = keccak256(abi.encode(logs[i].topics, logs[i].data));
            matches++;
        }
        assertEq(matches, 1, "event count");
    }

    function _rawViewsCut() internal returns (IDiamondCut.FacetCut[] memory cut) {
        RawWorldViewsFacet rawWorldViewsFacet = new RawWorldViewsFacet();
        RawTreasuryViewsFacet rawTreasuryViewsFacet = new RawTreasuryViewsFacet();
        RawClanViewsFacet rawClanViewsFacet = new RawClanViewsFacet();
        RawBanditViewsFacet rawBanditViewsFacet = new RawBanditViewsFacet();

        cut = new IDiamondCut.FacetCut[](4);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(rawWorldViewsFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawWorldViewsSelectors()
        });
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(rawTreasuryViewsFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawTreasuryViewsSelectors()
        });
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(rawClanViewsFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawClanViewsSelectors()
        });
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(rawBanditViewsFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawBanditViewsSelectors()
        });
    }

    function _productionCut(address loupeFacet) internal returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](25);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: loupeFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.loupeSelectors()
        });
        cut[1] = IDiamondCut.FacetCut({
            facetAddress: address(new OwnershipFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.ownershipFacetSelectors()
        });
        cut[2] = IDiamondCut.FacetCut({
            facetAddress: address(new HeartbeatFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.heartbeatSelectors()
        });
        cut[3] = IDiamondCut.FacetCut({
            facetAddress: address(new FinalizeSeasonFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.seasonSelectors()
        });
        cut[4] = IDiamondCut.FacetCut({
            facetAddress: address(new RawWorldViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawWorldViewsSelectors()
        });
        cut[5] = IDiamondCut.FacetCut({
            facetAddress: address(new RawTreasuryViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawTreasuryViewsSelectors()
        });
        cut[6] = IDiamondCut.FacetCut({
            facetAddress: address(new RawClanViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawClanViewsSelectors()
        });
        cut[7] = IDiamondCut.FacetCut({
            facetAddress: address(new RawBanditViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.rawBanditViewsSelectors()
        });
        cut[8] = IDiamondCut.FacetCut({
            facetAddress: address(new ClanLifecycleFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.lifecycleSelectors()
        });
        cut[9] = IDiamondCut.FacetCut({
            facetAddress: address(new SubmitOrdersFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.submitOrdersSelectors()
        });
        cut[10] = IDiamondCut.FacetCut({
            facetAddress: address(new ClanOwnershipFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.ownershipSelectors()
        });
        cut[11] = IDiamondCut.FacetCut({
            facetAddress: address(new TreasuryFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.treasurySelectors()
        });
        cut[12] = IDiamondCut.FacetCut({
            facetAddress: address(new SettlementFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.settlementSelectors()
        });
        cut[13] = IDiamondCut.FacetCut({
            facetAddress: address(new GoldTransferFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.goldTransferSelectors()
        });
        cut[14] = IDiamondCut.FacetCut({
            facetAddress: address(new VaultResourceTransferFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.vaultResourceTransferSelectors()
        });
        cut[15] = IDiamondCut.FacetCut({
            facetAddress: address(new BlueprintTransferFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.blueprintTransferSelectors()
        });
        cut[16] = IDiamondCut.FacetCut({
            facetAddress: address(new BundleTransferFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.bundleTransferSelectors()
        });
        cut[17] = IDiamondCut.FacetCut({
            facetAddress: address(new DerivedViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.derivedViewsSelectors()
        });
        cut[18] = IDiamondCut.FacetCut({
            facetAddress: address(new MarketViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.marketViewsSelectors()
        });
        cut[19] = IDiamondCut.FacetCut({
            facetAddress: address(new BanditViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.banditViewsSelectors()
        });
        cut[20] = IDiamondCut.FacetCut({
            facetAddress: address(new RegionViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.regionViewsSelectors()
        });
        cut[21] = IDiamondCut.FacetCut({
            facetAddress: address(new SnapshotViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.snapshotViewsSelectors()
        });
        cut[22] = IDiamondCut.FacetCut({
            facetAddress: address(new ClanFullViewFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.clanFullViewSelectors()
        });
        cut[23] = IDiamondCut.FacetCut({
            facetAddress: address(new QuoteViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.quoteViewsSelectors()
        });
        cut[24] = IDiamondCut.FacetCut({
            facetAddress: address(new ScoringViewsFacet()),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.scoringViewsSelectors()
        });
    }

    function _expectedProductionSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](59);
        uint256 offset;
        selectors[offset++] = IDiamondCut.diamondCut.selector;
        offset = _copySelectors(selectors, offset, DiamondSelectors.loupeSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.ownershipFacetSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.heartbeatSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.seasonSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.rawWorldViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.rawTreasuryViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.rawClanViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.rawBanditViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.lifecycleSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.submitOrdersSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.ownershipSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.treasurySelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.settlementSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.goldTransferSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.vaultResourceTransferSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.blueprintTransferSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.bundleTransferSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.derivedViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.marketViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.banditViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.regionViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.snapshotViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.clanFullViewSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.quoteViewsSelectors());
        offset = _copySelectors(selectors, offset, DiamondSelectors.scoringViewsSelectors());
        require(offset == selectors.length, "selector count drift");
    }

    function _copySelectors(bytes4[] memory out, uint256 offset, bytes4[] memory selectors)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < selectors.length; i++) {
            out[offset++] = selectors[i];
        }
        return offset;
    }

    function _adminOwnershipCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.ownershipFacetSelectors()
        });
    }

    function _lifecycleCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.lifecycleSelectors()
        });
    }

    function _heartbeatCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.heartbeatSelectors()
        });
    }

    function _seasonCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.seasonSelectors()
        });
    }

    function _spawnBanditCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SpawnBanditFacet.spawnBandit.selector;

        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
    }

    function _banditCleanupHarnessCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = BanditCleanupHarnessFacet.registerTargetDefender.selector;
        selectors[1] = BanditCleanupHarnessFacet.forceBanditAttack.selector;
        selectors[2] = BanditCleanupHarnessFacet.markClanDead.selector;

        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
    }

    function _submitOrdersCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.submitOrdersSelectors()
        });
    }

    function _ownershipCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.ownershipSelectors()
        });
    }

    function _treasuryCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.treasurySelectors()
        });
    }

    function _settlementCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.settlementSelectors()
        });
    }

    function _goldTransferCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.goldTransferSelectors()
        });
    }

    function _vaultResourceTransferCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.vaultResourceTransferSelectors()
        });
    }

    function _blueprintTransferCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.blueprintTransferSelectors()
        });
    }

    function _bundleTransferCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.bundleTransferSelectors()
        });
    }

    function _setWorldClockCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SetWorldClockFacet.setWorldClock.selector;

        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
    }

    function _derivedViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.derivedViewsSelectors()
        });
    }

    function _marketViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.marketViewsSelectors()
        });
    }

    function _banditViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.banditViewsSelectors()
        });
    }

    function _regionViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.regionViewsSelectors()
        });
    }

    function _snapshotViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.snapshotViewsSelectors()
        });
    }

    function _clanFullViewCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.clanFullViewSelectors()
        });
    }

    function _quoteViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.quoteViewsSelectors()
        });
    }

    function _scoringViewsCut(address facet) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: facet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: DiamondSelectors.scoringViewsSelectors()
        });
    }

    function _assertWorldStateEq(WorldState memory actual, WorldState memory expected) internal pure {
        assertEq(actual.currentTick, expected.currentTick, "currentTick");
        assertEq(actual.seasonStartTick, expected.seasonStartTick, "seasonStartTick");
        assertEq(actual.seasonEndTick, expected.seasonEndTick, "seasonEndTick");
        assertEq(actual.seasonFinalized, expected.seasonFinalized, "seasonFinalized");
        assertEq(actual.currentSeasonNumber, expected.currentSeasonNumber, "currentSeasonNumber");
        assertEq(actual.nextHeartbeatAtTick, expected.nextHeartbeatAtTick, "nextHeartbeatAtTick");
        assertEq(actual.nextHeartbeatAtTs, expected.nextHeartbeatAtTs, "nextHeartbeatAtTs");
        assertEq(actual.nextBanditSpawnEligibleTick, expected.nextBanditSpawnEligibleTick, "banditEligible");
        assertEq(actual.currentBanditSpawnChanceBps, expected.currentBanditSpawnChanceBps, "banditChance");
        assertEq(actual.currentTickSeed, expected.currentTickSeed, "currentTickSeed");
        assertEq(actual.activeBanditId, expected.activeBanditId, "activeBanditId");
        assertEq(actual.winterActive, expected.winterActive, "winterActive");
        assertEq(actual.winterStartsAtTick, expected.winterStartsAtTick, "winterStartsAtTick");
        assertEq(actual.winterEndsAtTick, expected.winterEndsAtTick, "winterEndsAtTick");
        assertEq(actual.nextCommitSequence, expected.nextCommitSequence, "nextCommitSequence");
    }

    function _assertTreasuryStateEq(TreasuryState memory actual, TreasuryState memory expected) internal pure {
        assertEq(actual.treasuryOwner, expected.treasuryOwner, "treasuryOwner");
        assertEq(actual.prizePotGold, expected.prizePotGold, "prizePotGold");
        assertEq(actual.poolsSeeded, expected.poolsSeeded, "poolsSeeded");
        assertEq(actual.woodToken, expected.woodToken, "woodToken");
        assertEq(actual.wheatToken, expected.wheatToken, "wheatToken");
        assertEq(actual.fishToken, expected.fishToken, "fishToken");
        assertEq(actual.ironToken, expected.ironToken, "ironToken");
        assertEq(actual.goldToken, expected.goldToken, "goldToken");
        assertEq(actual.blueprintToken, expected.blueprintToken, "blueprintToken");
        assertEq(actual.woodGoldPool, expected.woodGoldPool, "woodGoldPool");
        assertEq(actual.wheatGoldPool, expected.wheatGoldPool, "wheatGoldPool");
        assertEq(actual.fishGoldPool, expected.fishGoldPool, "fishGoldPool");
        assertEq(actual.ironGoldPool, expected.ironGoldPool, "ironGoldPool");
    }

    function _deployTreasuryBoundary(address engine)
        internal
        returns (address[6] memory tokens, address[4] memory pools)
    {
        tokens[0] = address(new MinimalERC20("Wood", "WOOD"));
        tokens[1] = address(new MinimalERC20("Iron", "IRON"));
        tokens[2] = address(new MinimalERC20("Wheat", "WHEAT"));
        tokens[3] = address(new MinimalERC20("Fish", "FISH"));
        tokens[4] = address(new MinimalERC20("Gold", "GOLD"));
        tokens[5] = address(new MinimalERC20("Blueprint", "BPRT"));

        pools[0] = address(new StubPool(tokens[0], tokens[4], engine));
        pools[1] = address(new StubPool(tokens[2], tokens[4], engine));
        pools[2] = address(new StubPool(tokens[3], tokens[4], engine));
        pools[3] = address(new StubPool(tokens[1], tokens[4], engine));
    }

    function _seedAndApproveTreasury(address[6] memory tokens, address spender, PoolSeedConfig memory cfg) internal {
        MinimalERC20(tokens[0]).seedTreasury(address(this), cfg.woodSeed);
        MinimalERC20(tokens[1]).seedTreasury(address(this), cfg.ironSeed);
        MinimalERC20(tokens[2]).seedTreasury(address(this), cfg.wheatSeed);
        MinimalERC20(tokens[3]).seedTreasury(address(this), cfg.fishSeed);
        MinimalERC20(tokens[4])
            .seedTreasury(
                address(this), cfg.goldSeedForWood + cfg.goldSeedForWheat + cfg.goldSeedForFish + cfg.goldSeedForIron
            );
        MinimalERC20(tokens[5]).seedTreasury(address(this), 1);

        for (uint256 i = 0; i < tokens.length; i++) {
            MinimalERC20(tokens[i]).approve(spender, type(uint256).max);
        }
    }

    function _seedConfig() internal pure returns (PoolSeedConfig memory) {
        return PoolSeedConfig({
            woodSeed: 1_000,
            wheatSeed: 700,
            fishSeed: 500,
            ironSeed: 250,
            goldSeedForWood: 100,
            goldSeedForWheat: 120,
            goldSeedForFish: 140,
            goldSeedForIron: 160
        });
    }

    function _assertPoolReserves(address pool, uint256 reserveA, uint256 reserveB) internal view {
        (uint256 actualA, uint256 actualB) = StubPool(pool).getReserves();
        assertEq(actualA, reserveA, "reserve A");
        assertEq(actualB, reserveB, "reserve B");
    }

    function _assertClanEq(Clan memory actual, Clan memory expected) internal pure {
        assertEq(actual.clanId, expected.clanId, "clanId");
        assertEq(actual.iftTokenId, expected.iftTokenId, "iftTokenId");
        assertEq(actual.owner, expected.owner, "owner");
        assertEq(uint8(actual.clanState), uint8(expected.clanState), "clanState");
        assertEq(actual.baseRegion, expected.baseRegion, "baseRegion");
        assertEq(actual.baseLevel, expected.baseLevel, "baseLevel");
        assertEq(actual.wallLevel, expected.wallLevel, "wallLevel");
        assertEq(actual.monumentLevel, expected.monumentLevel, "monumentLevel");
        assertEq(actual.livingClansmen, expected.livingClansmen, "livingClansmen");
        assertEq(actual.lastSettledTick, expected.lastSettledTick, "lastSettledTick");
        assertEq(actual.starvationStartsAtTick, expected.starvationStartsAtTick, "starvationStartsAtTick");
        assertEq(actual.coldDamage, expected.coldDamage, "coldDamage");
        assertEq(actual.ownerNonce, expected.ownerNonce, "ownerNonce");
        assertEq(actual.goldBalance, expected.goldBalance, "goldBalance");
        assertEq(actual.blueprintBalance, expected.blueprintBalance, "blueprintBalance");
        assertEq(actual.vaultWood, expected.vaultWood, "vaultWood");
        assertEq(actual.vaultIron, expected.vaultIron, "vaultIron");
        assertEq(actual.vaultWheat, expected.vaultWheat, "vaultWheat");
        assertEq(actual.vaultFish, expected.vaultFish, "vaultFish");
    }

    function _assertClansmanEq(Clansman memory actual, Clansman memory expected) internal pure {
        assertEq(actual.clansmanId, expected.clansmanId, "clansmanId");
        assertEq(actual.clanId, expected.clanId, "clansman clanId");
        assertEq(uint8(actual.state), uint8(expected.state), "clansman state");
        assertEq(actual.currentRegion, expected.currentRegion, "currentRegion");
        assertEq(actual.cooldownEndsAtTs, expected.cooldownEndsAtTs, "cooldownEndsAtTs");
        assertEq(actual.lastMissionNonce, expected.lastMissionNonce, "lastMissionNonce");
        assertEq(actual.carryWood, expected.carryWood, "carryWood");
        assertEq(actual.carryIron, expected.carryIron, "carryIron");
        assertEq(actual.carryWheat, expected.carryWheat, "carryWheat");
        assertEq(actual.carryFish, expected.carryFish, "carryFish");
    }

    function _assertBanditEq(BanditTroop memory actual, BanditTroop memory expected) internal pure {
        assertEq(actual.id, expected.id, "bandit id");
        assertEq(actual.region, expected.region, "bandit region");
        assertEq(uint8(actual.state), uint8(expected.state), "bandit state");
        assertEq(actual.targetClanId, expected.targetClanId, "bandit target");
        assertEq(actual.tickEnteredState, expected.tickEnteredState, "bandit tickEnteredState");
        assertEq(actual.strength, expected.strength, "bandit strength");
        assertEq(actual.tier, expected.tier, "bandit tier");
        assertEq(actual.attackAttemptsMade, expected.attackAttemptsMade, "bandit attempts");
        assertEq(actual.carryWood, expected.carryWood, "bandit wood");
        assertEq(actual.carryIron, expected.carryIron, "bandit iron");
        assertEq(actual.carryWheat, expected.carryWheat, "bandit wheat");
        assertEq(actual.carryFish, expected.carryFish, "bandit fish");
        assertEq(actual.carryGold, expected.carryGold, "bandit gold");
    }

    function _assertMissionEq(Mission memory actual, Mission memory expected) internal pure {
        assertEq(actual.active, expected.active, "mission active");
        assertEq(actual.nonce, expected.nonce, "mission nonce");
        assertEq(actual.clansmanId, expected.clansmanId, "mission clansmanId");
        assertEq(actual.submittedAtTick, expected.submittedAtTick, "submitted");
        assertEq(actual.executesAtTick, expected.executesAtTick, "executes");
        assertEq(actual.settlesAtTick, expected.settlesAtTick, "settles");
        assertEq(actual.startRegion, expected.startRegion, "start region");
        assertEq(actual.targetRegion, expected.targetRegion, "target region");
        assertEq(uint8(actual.action), uint8(expected.action), "action");
        assertEq(actual.startTick, expected.startTick, "start tick");
        assertEq(actual.arrivalTick, expected.arrivalTick, "arrival");
        assertEq(actual.actionStartTick, expected.actionStartTick, "action start");
        assertEq(actual.missionSeed, expected.missionSeed, "seed");
        assertEq(uint8(actual.marketMode), uint8(expected.marketMode), "market mode");
        assertEq(actual.targetClanId, expected.targetClanId, "target clan");
        assertEq(actual.marketToken, expected.marketToken, "market token");
        assertEq(actual.marketAmount, expected.marketAmount, "market amount");
        assertEq(actual.maxGoldIn, expected.maxGoldIn, "max gold");
    }

    function _assertWheatPlotEq(WheatPlot memory actual, WheatPlot memory expected) internal pure {
        assertEq(uint8(actual.state), uint8(expected.state), "plot state");
        assertEq(actual.region, expected.region, "plot region");
        assertEq(actual.remainingWheat, expected.remainingWheat, "remainingWheat");
        assertEq(actual.regrowUntilTick, expected.regrowUntilTick, "regrowUntilTick");
    }

    function _assertDerivedClanStateEq(DerivedClanState memory actual, DerivedClanState memory expected) internal pure {
        _assertClanEq(actual.clan, expected.clan);
        assertEq(actual.isStarving, expected.isStarving, "isStarving");
        assertEq(actual.lootValue, expected.lootValue, "lootValue");
        assertEq(actual.derivedAtTick, expected.derivedAtTick, "derivedAtTick");
    }

    function _assertDerivedClansmanStateEq(DerivedClansmanState memory actual, DerivedClansmanState memory expected)
        internal
        pure
    {
        _assertClansmanEq(actual.clansman, expected.clansman);
        assertEq(actual.effectiveRegion, expected.effectiveRegion, "effectiveRegion");
        assertEq(actual.derivedAtTick, expected.derivedAtTick, "derived clansman tick");
        assertEq(actual.activeMission.active, expected.activeMission.active, "mission active");
        assertEq(actual.activeMission.nonce, expected.activeMission.nonce, "mission nonce");
    }

    function _assertMarketStateEq(MarketState memory actual, MarketState memory expected) internal pure {
        assertEq(actual.wood.resourceToken, expected.wood.resourceToken, "wood token");
        assertEq(actual.wheat.resourceToken, expected.wheat.resourceToken, "wheat token");
        assertEq(actual.fish.resourceToken, expected.fish.resourceToken, "fish token");
        assertEq(actual.iron.resourceToken, expected.iron.resourceToken, "iron token");
        assertEq(actual.currentTick, expected.currentTick, "market tick");
        assertEq(actual.currentTickQueue.length, expected.currentTickQueue.length, "current queue");
        assertEq(actual.nextTickQueue.length, expected.nextTickQueue.length, "next queue");
    }

    function _assertActiveBanditViewEq(ActiveBanditView memory actual, ActiveBanditView memory expected) internal pure {
        assertEq(actual.exists, expected.exists, "bandit exists");
        assertEq(actual.banditId, expected.banditId, "bandit id");
        assertEq(uint8(actual.state), uint8(expected.state), "bandit state");
        assertEq(actual.currentRegion, expected.currentRegion, "bandit region");
        assertEq(actual.attackAttemptsMade, expected.attackAttemptsMade, "bandit attempts");
        assertEq(actual.maxAttemptsRemaining, expected.maxAttemptsRemaining, "bandit remaining");
        assertEq(actual.stateEnteredTick, expected.stateEnteredTick, "bandit entered");
        assertEq(actual.nextActionTick, expected.nextActionTick, "bandit next");
        assertEq(actual.tier, expected.tier, "bandit tier");
        assertEq(actual.attackPower, expected.attackPower, "bandit power");
        assertEq(actual.carryWood, expected.carryWood, "bandit wood");
        assertEq(actual.carryIron, expected.carryIron, "bandit iron");
        assertEq(actual.carryWheat, expected.carryWheat, "bandit wheat");
        assertEq(actual.carryFish, expected.carryFish, "bandit fish");
        assertEq(actual.projectedTargetClanId, expected.projectedTargetClanId, "bandit target");
        assertEq(actual.projectedTargetLootValue, expected.projectedTargetLootValue, "bandit loot");
    }

    function _assertRegionPopulationEq(RegionOccupant[] memory actual, RegionOccupant[] memory expected) internal pure {
        assertEq(actual.length, expected.length, "population length");
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i].clansmanId, expected[i].clansmanId, "population clansman");
            assertEq(actual[i].clanId, expected[i].clanId, "population clan");
            assertEq(uint8(actual[i].state), uint8(expected[i].state), "population state");
            assertEq(uint8(actual[i].currentAction), uint8(expected[i].currentAction), "population action");
            assertEq(actual[i].missionNonce, expected[i].missionNonce, "population nonce");
        }
    }

    function _assertWorldSnapshotEq(WorldSnapshot memory actual, WorldSnapshot memory expected) internal pure {
        assertEq(actual.currentTick, expected.currentTick, "snapshot currentTick");
        assertEq(actual.seasonStartTick, expected.seasonStartTick, "snapshot seasonStartTick");
        assertEq(actual.seasonEndTick, expected.seasonEndTick, "snapshot seasonEndTick");
        assertEq(actual.seasonFinalized, expected.seasonFinalized, "snapshot seasonFinalized");
        assertEq(actual.currentSeasonNumber, expected.currentSeasonNumber, "snapshot season");
        assertEq(actual.nextHeartbeatAtTick, expected.nextHeartbeatAtTick, "snapshot next heartbeat");
        assertEq(actual.winterActive, expected.winterActive, "snapshot winterActive");
        assertEq(actual.winterStartsAtTick, expected.winterStartsAtTick, "snapshot winter start");
        assertEq(actual.winterEndsAtTick, expected.winterEndsAtTick, "snapshot winter end");
        assertEq(actual.activeBanditId, expected.activeBanditId, "snapshot active bandit");
        assertEq(actual.currentTickSeed, expected.currentTickSeed, "snapshot seed");
        assertEq(actual.leaderboard.length, expected.leaderboard.length, "leaderboard length");
        for (uint256 i = 0; i < expected.leaderboard.length; i++) {
            assertEq(actual.leaderboard[i].clanId, expected.leaderboard[i].clanId, "leaderboard clanId");
            assertEq(actual.leaderboard[i].owner, expected.leaderboard[i].owner, "leaderboard owner");
            assertEq(actual.leaderboard[i].monumentLevel, expected.leaderboard[i].monumentLevel, "leaderboard monument");
            assertEq(actual.leaderboard[i].baseLevel, expected.leaderboard[i].baseLevel, "leaderboard base");
            assertEq(actual.leaderboard[i].wallLevel, expected.leaderboard[i].wallLevel, "leaderboard wall");
            assertEq(actual.leaderboard[i].livingClansmen, expected.leaderboard[i].livingClansmen, "leaderboard living");
            assertEq(uint8(actual.leaderboard[i].state), uint8(expected.leaderboard[i].state), "leaderboard state");
            assertEq(actual.leaderboard[i].lootValue, expected.leaderboard[i].lootValue, "leaderboard loot");
        }
    }

    function _assertClanFullViewEq(ClanFullView memory actual, ClanFullView memory expected) internal pure {
        _assertDerivedClanStateEq(actual.clan, expected.clan);
        assertEq(actual.clansmen.length, expected.clansmen.length, "full clansmen length");
        for (uint256 i = 0; i < expected.clansmen.length; i++) {
            _assertDerivedClansmanStateEq(actual.clansmen[i].clansman, expected.clansmen[i].clansman);
            assertEq(actual.clansmen[i].activeMission.active, expected.clansmen[i].activeMission.active, "full active");
            assertEq(actual.clansmen[i].activeMission.nonce, expected.clansmen[i].activeMission.nonce, "full nonce");
            assertEq(
                uint8(actual.clansmen[i].activeMission.action),
                uint8(expected.clansmen[i].activeMission.action),
                "full action"
            );
        }
        _assertWheatPlotEq(actual.westPlot, expected.westPlot);
        _assertWheatPlotEq(actual.eastPlot, expected.eastPlot);
        assertEq(actual.incomingDefenderIds.length, expected.incomingDefenderIds.length, "incoming defenders");
        assertEq(actual.thisClanDefendingBaseId, expected.thisClanDefendingBaseId, "defending base");
    }
}
