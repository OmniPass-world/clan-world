// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {GoldBridgeToken} from "../GoldBridgeToken.sol";

/// @title UpgradeableGoldDeployer
/// @notice One-shot helper that deploys the Base GOLD implementation, timelock, and proxy stack.
/// @dev The helper is not privileged after construction; it only stores addresses for deploy scripts.
contract UpgradeableGoldDeployer {
    GoldBridgeToken public immutable implementation;
    TimelockController public immutable timelock;
    TransparentUpgradeableProxy public immutable proxy;

    event UpgradeableGoldDeployed(
        address indexed proxy, address indexed implementation, address indexed timelock
    );

    constructor(
        string memory name_,
        string memory symbol_,
        address initialMinter_,
        address timelockProposer_,
        address timelockExecutor_,
        address timelockAdmin_,
        uint256 timelockDelay_
    ) {
        address[] memory proposers = new address[](1);
        proposers[0] = timelockProposer_;

        address[] memory executors = new address[](1);
        executors[0] = timelockExecutor_;

        TimelockController deployedTimelock =
            new TimelockController(timelockDelay_, proposers, executors, timelockAdmin_);
        GoldBridgeToken deployedImplementation = new GoldBridgeToken();

        bytes memory initData = abi.encodeCall(
            GoldBridgeToken.initialize, (name_, symbol_, initialMinter_, address(deployedTimelock))
        );
        TransparentUpgradeableProxy deployedProxy = new TransparentUpgradeableProxy(
            address(deployedImplementation), address(deployedTimelock), initData
        );

        implementation = deployedImplementation;
        timelock = deployedTimelock;
        proxy = deployedProxy;

        emit UpgradeableGoldDeployed(
            address(deployedProxy), address(deployedImplementation), address(deployedTimelock)
        );
    }
}
