// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {GoldBridgeToken} from "../src/GoldBridgeToken.sol";

contract Actor {
    function mint(GoldBridgeToken token, address account, uint256 amount) external {
        token.mint(account, amount);
    }

    function burn(GoldBridgeToken token, uint256 amount) external {
        token.burn(amount);
    }

    function transferToken(GoldBridgeToken token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }

    function approveToken(GoldBridgeToken token, address spender, uint256 amount) external {
        require(token.approve(spender, amount), "approve failed");
    }
}

contract GoldBridgeTokenTest {
    GoldBridgeToken private token;
    Actor private actor;

    function setUp() public {
        token = new GoldBridgeToken("Gold", "GOLD", address(this), address(this));
        actor = new Actor();
    }

    function testConstructor() public view {
        require(keccak256(bytes(token.name())) == keccak256(bytes("Gold")), "bad name");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes("GOLD")), "bad symbol");
        require(token.decimals() == 9, "bad decimals");
        require(token.owner() == address(this), "bad owner");
        require(token.minter() == address(this), "bad minter");
    }

    function testMintTransferAndBurn() public {
        token.mint(address(actor), 1_000);
        require(token.totalSupply() == 1_000, "bad supply after mint");
        require(token.balanceOf(address(actor)) == 1_000, "bad actor balance");

        actor.transferToken(token, address(this), 250);
        require(token.balanceOf(address(actor)) == 750, "bad actor balance after transfer");
        require(token.balanceOf(address(this)) == 250, "bad recipient balance after transfer");

        actor.burn(token, 500);
        require(token.totalSupply() == 500, "bad supply after burn");
        require(token.balanceOf(address(actor)) == 250, "bad actor balance after burn");
    }

    function testOnlyMinterCanMint() public {
        bool reverted;
        try actor.mint(token, address(actor), 1) {
            reverted = false;
        } catch {
            reverted = true;
        }
        require(reverted, "non-minter mint did not revert");
    }

    function testOwnerCanRotateMinter() public {
        token.setMinter(address(actor));
        require(token.minter() == address(actor), "minter not rotated");
        actor.mint(token, address(this), 123);
        require(token.balanceOf(address(this)) == 123, "rotated minter failed");
    }

    function testClanWorldCompatibleAllowancePull() public {
        token.mint(address(actor), 1_000_000_000);

        actor.approveToken(token, address(this), 400_000_000);
        require(token.allowance(address(actor), address(this)) == 400_000_000, "bad allowance");

        require(
            token.transferFrom(address(actor), address(this), 250_000_000), "transferFrom failed"
        );

        require(token.balanceOf(address(actor)) == 750_000_000, "bad source balance");
        require(token.balanceOf(address(this)) == 250_000_000, "bad recipient balance");
        require(
            token.allowance(address(actor), address(this)) == 150_000_000, "bad remaining allowance"
        );
    }

    function testUnlimitedAllowanceDoesNotDecrease() public {
        token.mint(address(actor), 10);
        actor.approveToken(token, address(this), type(uint256).max);

        require(token.transferFrom(address(actor), address(this), 4), "transferFrom failed");

        require(
            token.allowance(address(actor), address(this)) == type(uint256).max,
            "unlimited allowance changed"
        );
        require(token.balanceOf(address(actor)) == 6, "bad source balance");
    }
}
