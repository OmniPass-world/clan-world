// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ClanAgentNFT} from "../src/ClanAgentNFT.sol";
import {Mock7857Verifier} from "../src/Mock7857Verifier.sol";

contract ClanAgentNFTTest is Test {
    Mock7857Verifier verifier;
    ClanAgentNFT nft;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address operator = address(0x0A);

    function setUp() public {
        verifier = new Mock7857Verifier();
        nft = new ClanAgentNFT("ClanWorld Elder iNFT", "ELDER", address(verifier));
    }

    function test_mintStoresIntelligentData() public {
        nft.mint(alice, 7, _data("persona", "0xpersona"));

        assertEq(nft.ownerOf(7), alice);
        ClanAgentNFT.IntelligentData[] memory data = nft.intelligentDataOf(7);
        assertEq(data.length, 1);
        assertEq(data[0].label, "persona");
        assertEq(data[0].uri, "0xpersona");
        assertTrue(nft.currentDataHash(7) != bytes32(0));
    }

    function test_iTransferChangesOwnerAndUpdatesData() public {
        nft.mint(alice, 7, _data("memory", "0xold"));

        vm.prank(alice);
        nft.iTransfer(
            bob,
            7,
            _data("memory", "0xnew"),
            ClanAgentNFT.TransferProof({
                newDataHash: bytes32(0),
                encryptedKeyHash: keccak256("dek-bob"),
                newUri: "0xnew",
                proof: "demo-proof"
            })
        );

        assertEq(nft.ownerOf(7), bob);
        assertEq(nft.encryptedKeyHash(7), keccak256("dek-bob"));
        ClanAgentNFT.IntelligentData[] memory data = nft.intelligentDataOf(7);
        assertEq(data[0].uri, "0xnew");
    }

    function test_nonOwnerCannotTransfer() public {
        nft.mint(alice, 7, _data("memory", "0xold"));

        vm.prank(operator);
        vm.expectRevert(ClanAgentNFT.NotApprovedOrOwner.selector);
        nft.iTransfer(
            bob,
            7,
            _data("memory", "0xnew"),
            ClanAgentNFT.TransferProof({
                newDataHash: bytes32(0),
                encryptedKeyHash: keccak256("dek-bob"),
                newUri: "0xnew",
                proof: "demo-proof"
            })
        );
    }

    function test_authorizedUserCanUpdateMetadata() public {
        nft.mint(alice, 7, _data("memory", "0xold"));

        vm.prank(alice);
        nft.authorizeUsage(7, operator);

        vm.prank(operator);
        nft.updateMetadata(7, _data("memory", "0xoperator"), "metadata-proof");

        ClanAgentNFT.IntelligentData[] memory data = nft.intelligentDataOf(7);
        assertEq(data[0].uri, "0xoperator");
    }

    function test_emptyProofRejected() public {
        nft.mint(alice, 7, _data("memory", "0xold"));

        vm.prank(alice);
        vm.expectRevert(ClanAgentNFT.InvalidProof.selector);
        nft.updateMetadata(7, _data("memory", "0xnew"), "");
    }

    function _data(string memory label, string memory uri) private pure returns (ClanAgentNFT.IntelligentData[] memory data) {
        data = new ClanAgentNFT.IntelligentData[](1);
        data[0] = ClanAgentNFT.IntelligentData({
            label: label,
            dataHash: keccak256(bytes(uri)),
            uri: uri
        });
    }
}
