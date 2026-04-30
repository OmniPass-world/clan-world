// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/// @title IDiamondCut
/// @notice Interface for EIP-2535 Diamond facet management.
///         Ported from Nick Mudgen's diamond-3-hardhat reference implementation.
///         https://github.com/mudgen/diamond-3-hardhat
interface IDiamondCut {
    enum FacetCutAction {
        Add,     // Add new function selectors
        Replace, // Replace existing function selectors with new facet
        Remove   // Remove function selectors
    }

    struct FacetCut {
        address facetAddress;        // address(0) for Remove
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Add/replace/remove facets and optionally execute an init function.
    /// @param _diamondCut Array of FacetCut structs.
    /// @param _init Address of contract to call with _calldata; address(0) = skip.
    /// @param _calldata Encoded function call for initialization; empty = skip.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}
