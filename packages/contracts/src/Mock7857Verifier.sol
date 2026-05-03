// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface IAgentTransferVerifier {
    function verifyTransfer(
        uint256 tokenId,
        address from,
        address to,
        bytes32 newDataHash,
        bytes32 encryptedKeyHash,
        bytes calldata proof
    ) external returns (bool);

    function verifyMetadataUpdate(
        uint256 tokenId,
        bytes32 newDataHash,
        bytes calldata proof
    ) external returns (bool);
}

/// @notice Demo verifier for ERC-7857-style iNFT flows.
/// @dev This is intentionally not a production proof verifier. It rejects empty
///      proof/data payloads so tests and demo scripts cannot accidentally hand
///      wave the transfer path, while still keeping the S2 demo shippable.
contract Mock7857Verifier is IAgentTransferVerifier {
    event TransferProofVerified(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        bytes32 newDataHash,
        bytes32 encryptedKeyHash
    );

    event MetadataProofVerified(uint256 indexed tokenId, bytes32 newDataHash);

    function verifyTransfer(
        uint256 tokenId,
        address from,
        address to,
        bytes32 newDataHash,
        bytes32 encryptedKeyHash,
        bytes calldata proof
    ) external returns (bool) {
        bool ok = tokenId != 0
            && from != address(0)
            && to != address(0)
            && newDataHash != bytes32(0)
            && encryptedKeyHash != bytes32(0)
            && proof.length != 0;
        if (ok) {
            emit TransferProofVerified(tokenId, from, to, newDataHash, encryptedKeyHash);
        }
        return ok;
    }

    function verifyMetadataUpdate(uint256 tokenId, bytes32 newDataHash, bytes calldata proof) external returns (bool) {
        bool ok = tokenId != 0 && newDataHash != bytes32(0) && proof.length != 0;
        if (ok) {
            emit MetadataProofVerified(tokenId, newDataHash);
        }
        return ok;
    }
}
