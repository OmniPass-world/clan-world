// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanWorld} from "../src/ClanWorld.sol";
import {MinimalERC20} from "../src/MinimalERC20.sol";
import {StubPool} from "../src/StubPool.sol";
import {ResourceType} from "../src/IClanWorld.sol";

contract ResourceBoundaryTokensTest is Test {
    event ResourceMinted(uint8 indexed resourceType, address indexed to, uint256 amount);
    event ResourceBurned(uint8 indexed resourceType, address indexed from, uint256 amount);

    ClanWorld world;
    MinimalERC20 woodToken;
    MinimalERC20 ironToken;
    MinimalERC20 wheatToken;
    MinimalERC20 fishToken;
    MinimalERC20 goldToken;
    MinimalERC20 blueprintToken;

    function setUp() public {
        world = new ClanWorld();
        woodToken = new MinimalERC20("Wood", "WOOD");
        ironToken = new MinimalERC20("Iron", "IRON");
        wheatToken = new MinimalERC20("Wheat", "WHEAT");
        fishToken = new MinimalERC20("Fish", "FISH");
        goldToken = new MinimalERC20("Gold", "GOLD");
        blueprintToken = new MinimalERC20("BPRT", "BPRT");

        woodToken.configureBoundary(uint8(ResourceType.Wood), address(world));
        ironToken.configureBoundary(uint8(ResourceType.Iron), address(world));
        wheatToken.configureBoundary(uint8(ResourceType.Wheat), address(world));
        fishToken.configureBoundary(uint8(ResourceType.Fish), address(world));
    }

    function test_getResourceTokenReturnsConfiguredBoundaryTokens() public {
        StubPool woodPool = new StubPool(address(woodToken), address(goldToken), address(world));
        StubPool wheatPool = new StubPool(address(wheatToken), address(goldToken), address(world));
        StubPool fishPool = new StubPool(address(fishToken), address(goldToken), address(world));
        StubPool ironPool = new StubPool(address(ironToken), address(goldToken), address(world));

        address[6] memory tokens = [
            address(woodToken),
            address(ironToken),
            address(wheatToken),
            address(fishToken),
            address(goldToken),
            address(blueprintToken)
        ];
        address[4] memory pools = [address(woodPool), address(wheatPool), address(fishPool), address(ironPool)];

        world.initTreasury(tokens, pools);

        assertEq(world.getResourceToken(uint8(ResourceType.Wood)), address(woodToken), "wood");
        assertEq(world.getResourceToken(uint8(ResourceType.Iron)), address(ironToken), "iron");
        assertEq(world.getResourceToken(uint8(ResourceType.Wheat)), address(wheatToken), "wheat");
        assertEq(world.getResourceToken(uint8(ResourceType.Fish)), address(fishToken), "fish");
    }

    function test_onlyEngineCanMintAndBurnBoundaryTokens() public {
        address holder = address(0xCAFE);

        vm.expectRevert(bytes("MinimalERC20: not engine"));
        woodToken.mint(holder, 10e18);

        vm.expectEmit(true, true, false, true, address(woodToken));
        emit ResourceMinted(uint8(ResourceType.Wood), holder, 10e18);
        vm.prank(address(world));
        woodToken.mint(holder, 10e18);

        assertEq(woodToken.balanceOf(holder), 10e18, "minted balance");

        vm.expectEmit(true, true, false, true, address(woodToken));
        emit ResourceBurned(uint8(ResourceType.Wood), holder, 4e18);
        vm.prank(address(world));
        woodToken.burn(holder, 4e18);

        assertEq(woodToken.balanceOf(holder), 6e18, "burned balance");
    }

    function test_seedTreasuryMintsStartingSupply() public {
        address treasury = address(0xBEEF);

        woodToken.seedTreasury(treasury, 1000e18);

        assertEq(woodToken.balanceOf(treasury), 1000e18, "treasury balance");
        assertEq(woodToken.totalSupply(), 1000e18, "total supply");
    }

    function test_seedTreasuryCanOnlyRunOnce() public {
        address treasury = address(0xBEEF);

        woodToken.seedTreasury(treasury, 1000e18);

        vm.expectRevert(bytes("MinimalERC20: treasury seeded"));
        woodToken.seedTreasury(treasury, 1e18);
    }

    function test_onlyDeployerCanSeedTreasury() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("MinimalERC20: not deployer"));
        woodToken.seedTreasury(address(0xBEEF), 1000e18);
    }
}
