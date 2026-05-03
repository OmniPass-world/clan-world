// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {ClanAgentNFT} from "../src/ClanAgentNFT.sol";

contract MintClanAgent is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        ClanAgentNFT nft = ClanAgentNFT(vm.envAddress("OG_INFT_ADDRESS"));
        address to = vm.envAddress("INFT_OWNER");
        uint256 tokenId = vm.envUint("INFT_TOKEN_ID");
        string memory uri = vm.envOr("INFT_METADATA_URI", string("0g://clanworld/demo"));

        ClanAgentNFT.IntelligentData[] memory data = new ClanAgentNFT.IntelligentData[](3);
        data[0] = ClanAgentNFT.IntelligentData({
            label: "persona",
            dataHash: keccak256(abi.encodePacked(tokenId, "persona", uri)),
            uri: uri
        });
        data[1] = ClanAgentNFT.IntelligentData({
            label: "memory",
            dataHash: keccak256(abi.encodePacked(tokenId, "memory", uri)),
            uri: uri
        });
        data[2] = ClanAgentNFT.IntelligentData({
            label: "owner_notes",
            dataHash: keccak256(abi.encodePacked(tokenId, "owner_notes", uri)),
            uri: uri
        });

        vm.startBroadcast(deployerPrivateKey);
        nft.mint(to, tokenId, data);
        vm.stopBroadcast();
    }
}
