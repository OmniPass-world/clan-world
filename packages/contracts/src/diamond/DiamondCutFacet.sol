// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IDiamondCut} from "./IDiamondCut.sol";
import {LibDiamond} from "./LibDiamond.sol";

/// @title DiamondCutFacet
/// @notice Implements EIP-2535 facet management (add/replace/remove).
///         Only the Diamond owner may call diamondCut.
///
///         In production: ownership should be transferred to a 2-of-3 multisig
///         with a 48-hour timelock (see docs/architecture/diamond-pattern.md §5).
///
///         Adapted from Nick Mudgen's diamond-3-hardhat reference.
///         https://github.com/mudgen/diamond-3-hardhat
contract DiamondCutFacet is IDiamondCut {
    /// @inheritdoc IDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
