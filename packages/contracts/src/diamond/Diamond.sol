// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {LibDiamond} from "./LibDiamond.sol";
import {IDiamondCut} from "./IDiamondCut.sol";

/// @title Diamond
/// @notice EIP-2535 proxy contract for ClanWorld.
///         Routes all external calls to the appropriate facet via delegatecall.
///         Stores selector→facet mapping in DiamondStorage (separate from AppStorage).
///
///         On deploy:
///         1. Sets owner (will be transferred to multisig post-deploy)
///         2. Accepts initial FacetCut array — all facets registered in one constructor tx
///         3. Optionally calls an init contract (for AppStorage initialization)
///
///         Adapted from Nick Mudgen's diamond-3-hardhat reference.
///         https://github.com/mudgen/diamond-3-hardhat
contract Diamond {
    constructor(address _contractOwner, IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) payable {
        LibDiamond.setContractOwner(_contractOwner);
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    /// @notice Fallback: route call to the facet registered for msg.sig.
    ///         Uses delegatecall so facets execute in Diamond's storage context.
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        require(facet != address(0), "Diamond: function does not exist");

        assembly {
            // Copy calldata into memory
            calldatacopy(0, 0, calldatasize())
            // delegatecall: execute facet code in this contract's storage context
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // Copy returndata
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
