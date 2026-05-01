// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {GoldBridgeToken} from "../src/GoldBridgeToken.sol";
import {GoldBridgeTokenV2} from "../src/GoldBridgeTokenV2.sol";

interface Vm {
    function load(address target, bytes32 slot) external view returns (bytes32);
    function warp(uint256 newTimestamp) external;
}

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
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 private constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    GoldBridgeToken private token;
    Actor private actor;

    function setUp() public {
        GoldBridgeToken implementation = new GoldBridgeToken();
        bytes memory initData = abi.encodeCall(
            GoldBridgeToken.initialize, ("Gold", "GOLD", address(this), address(this))
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(this), initData);
        token = GoldBridgeToken(address(proxy));
        actor = new Actor();
    }

    function testInitializer() public view {
        require(keccak256(bytes(token.name())) == keccak256(bytes("Gold")), "bad name");
        require(keccak256(bytes(token.symbol())) == keccak256(bytes("GOLD")), "bad symbol");
        require(token.decimals() == 9, "bad decimals");
        require(token.owner() == address(this), "bad owner");
        require(token.minter() == address(this), "bad minter");
        require(!token.recoveryDisabled(), "recovery disabled");
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

    function testRecoveryRequiresAllowedSource() public {
        token.mint(address(actor), 100);

        bool reverted;
        try token.recoverFromAllowedSource(address(actor), address(this), 10) {
            reverted = false;
        } catch {
            reverted = true;
        }
        require(reverted, "unallowed recovery did not revert");
    }

    function testOwnerCanRecoverFromAllowedSource() public {
        token.mint(address(actor), 100);
        token.setRecoveryAllowed(address(actor), true);

        token.recoverFromAllowedSource(address(actor), address(this), 40);

        require(token.balanceOf(address(actor)) == 60, "bad source balance");
        require(token.balanceOf(address(this)) == 40, "bad recipient balance");
    }

    function testRecoveryCanBeDisabledForever() public {
        token.setRecoveryAllowed(address(actor), true);
        token.disableRecoveryForever();
        require(token.recoveryDisabled(), "not disabled");

        bool reverted;
        try token.setRecoveryAllowed(address(this), true) {
            reverted = false;
        } catch {
            reverted = true;
        }
        require(reverted, "allowlist changed after disable");
    }

    function testTransparentProxyTimelockOwnerCanAdminToken() public {
        (GoldBridgeToken proxyToken, TimelockController timelock,) = deployProxyToken();
        require(proxyToken.owner() == address(timelock), "token owner not timelock");

        bytes memory setMinterData = abi.encodeCall(GoldBridgeToken.setMinter, (address(actor)));
        executeTimelock(timelock, address(proxyToken), setMinterData);

        require(proxyToken.minter() == address(actor), "timelock minter handoff failed");
    }

    function testTransparentProxyAdminIsOwnedByTimelock() public {
        (GoldBridgeToken proxyToken, TimelockController timelock, address proxyAdmin) =
            deployProxyToken();

        require(ProxyAdmin(proxyAdmin).owner() == address(timelock), "admin owner not timelock");
        require(proxyToken.decimals() == 9, "bad proxy decimals");
    }

    function testUpgradeToV2PreservesStateAndRemovesRecoveryAbi() public {
        (GoldBridgeToken proxyToken, TimelockController timelock, address proxyAdmin) =
            deployProxyToken();

        bytes memory setMinterData = abi.encodeCall(GoldBridgeToken.setMinter, (address(this)));
        executeTimelock(timelock, address(proxyToken), setMinterData);

        proxyToken.mint(address(actor), 500);
        actor.approveToken(proxyToken, address(this), 200);
        bytes memory allowRecoveryData =
            abi.encodeCall(GoldBridgeToken.setRecoveryAllowed, (address(actor), true));
        executeTimelock(timelock, address(proxyToken), allowRecoveryData);

        GoldBridgeTokenV2 v2 = new GoldBridgeTokenV2();
        bytes memory upgradeData = abi.encodeCall(
            ProxyAdmin.upgradeAndCall,
            (ITransparentUpgradeableProxy(address(proxyToken)), address(v2), "")
        );
        executeTimelock(timelock, proxyAdmin, upgradeData);

        GoldBridgeTokenV2 upgraded = GoldBridgeTokenV2(address(proxyToken));
        require(upgraded.balanceOf(address(actor)) == 500, "balance not preserved");
        require(upgraded.allowance(address(actor), address(this)) == 200, "allowance not preserved");
        require(upgraded.minter() == address(this), "minter not preserved");
        require(upgraded.owner() == address(timelock), "owner not preserved");
        require(upgraded.decimals() == 9, "decimals changed");

        (bool ok,) = address(upgraded)
            .call(
                abi.encodeWithSignature(
                    "recoverFromAllowedSource(address,address,uint256)",
                    address(actor),
                    address(this),
                    1
                )
            );
        require(!ok, "recovery ABI still callable");
    }

    function deployProxyToken()
        private
        returns (GoldBridgeToken proxyToken, TimelockController timelock, address proxyAdmin)
    {
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(this);

        timelock = new TimelockController(0, proposers, executors, address(0));
        GoldBridgeToken implementation = new GoldBridgeToken();
        bytes memory initData = abi.encodeCall(
            GoldBridgeToken.initialize, ("Gold", "GOLD", address(this), address(timelock))
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(timelock), initData);

        proxyToken = GoldBridgeToken(address(proxy));
        proxyAdmin = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
    }

    function executeTimelock(
        TimelockController timelock,
        address target,
        bytes memory data
    )
        private
    {
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256(abi.encode(target, data, address(this)));

        vm.warp(2);
        timelock.schedule(target, 0, data, predecessor, salt, 0);
        timelock.execute(target, 0, data, predecessor, salt);
    }
}
