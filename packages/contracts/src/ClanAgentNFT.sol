// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IAgentTransferVerifier} from "./Mock7857Verifier.sol";

/// @notice Minimal ERC-721 receiver interface used by safeTransferFrom.
interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

/// @notice ERC-7857-style demo iNFT for ClanWorld Elders.
/// @dev Token IDs intentionally match ClanWorld clan IDs for the hackathon demo.
///      Base ClanWorld ownership is not validated here.
contract ClanAgentNFT {
    struct IntelligentData {
        string label;
        bytes32 dataHash;
        string uri;
    }

    struct TransferProof {
        bytes32 newDataHash;
        bytes32 encryptedKeyHash;
        string newUri;
        bytes proof;
    }

    string public name;
    string public symbol;
    address public owner;
    IAgentTransferVerifier public verifier;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => IntelligentData[]) private _intelligentData;
    mapping(uint256 => bytes32) public currentDataHash;
    mapping(uint256 => bytes32) public encryptedKeyHash;
    mapping(uint256 => mapping(address => bool)) public usageAuthorizations;
    mapping(uint256 => address) public delegatedAccess;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event VerifierUpdated(address indexed verifier);
    /// @notice Emitted on data replacement. `dataHash` covers the FULL item set;
    ///         `uri` is `data[0].uri` by convention (the "primary" item, e.g. persona).
    ///         Indexers needing per-item URIs should follow IntelligentDataItem events below.
    event IntelligentDataUpdated(uint256 indexed tokenId, bytes32 dataHash, string uri);
    /// @notice One emit per data item, in order. Lets indexers reconstruct the full URI list.
    event IntelligentDataItem(uint256 indexed tokenId, uint256 indexed slot, string label, bytes32 dataHash, string uri);
    event UsageAuthorized(uint256 indexed tokenId, address indexed user);
    event UsageRevoked(uint256 indexed tokenId, address indexed user);
    event AccessDelegated(uint256 indexed tokenId, address indexed delegate);
    event IntelligentTransfer(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        bytes32 newDataHash,
        bytes32 encryptedKeyHash,
        string newUri
    );

    error NotOwner();
    error TokenNotFound();
    error NotApprovedOrOwner();
    error InvalidAddress();
    error InvalidProof();
    error InvalidData();
    error UnsafeRecipient();

    constructor(string memory name_, string memory symbol_, address verifier_) {
        if (verifier_ == address(0)) revert InvalidAddress();
        name = name_;
        symbol = symbol_;
        owner = msg.sender;
        verifier = IAgentTransferVerifier(verifier_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setVerifier(address newVerifier) external onlyOwner {
        if (newVerifier == address(0)) revert InvalidAddress();
        verifier = IAgentTransferVerifier(newVerifier);
        emit VerifierUpdated(newVerifier);
    }

    function balanceOf(address tokenOwner) external view returns (uint256) {
        if (tokenOwner == address(0)) revert InvalidAddress();
        return _balances[tokenOwner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenNotFound();
        return tokenOwner;
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId);
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address tokenOwner, address operator) public view returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && !isApprovedForAll(tokenOwner, msg.sender)) revert NotApprovedOrOwner();
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        if (operator == msg.sender) revert InvalidAddress();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function mint(address to, uint256 tokenId, IntelligentData[] calldata data) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (_owners[tokenId] != address(0)) revert InvalidData();
        if (data.length == 0) revert InvalidData();

        _owners[tokenId] = to;
        _balances[to] += 1;
        _replaceData(tokenId, data);

        emit Transfer(address(0), to, tokenId);
    }

    function intelligentDataOf(uint256 tokenId) external view returns (IntelligentData[] memory) {
        ownerOf(tokenId);
        return _intelligentData[tokenId];
    }

    function updateMetadata(uint256 tokenId, IntelligentData[] calldata data, bytes calldata proof) external {
        address tokenOwner = ownerOf(tokenId);
        if (msg.sender != tokenOwner && !usageAuthorizations[tokenId][msg.sender]) revert NotApprovedOrOwner();
        if (data.length == 0) revert InvalidData();

        bytes32 newHash = _hashData(data);
        if (!verifier.verifyMetadataUpdate(tokenId, newHash, proof)) revert InvalidProof();
        _replaceData(tokenId, data);
    }

    function authorizeUsage(uint256 tokenId, address user) external {
        if (msg.sender != ownerOf(tokenId)) revert NotApprovedOrOwner();
        if (user == address(0)) revert InvalidAddress();
        usageAuthorizations[tokenId][user] = true;
        emit UsageAuthorized(tokenId, user);
    }

    function revokeAuthorization(uint256 tokenId, address user) external {
        if (msg.sender != ownerOf(tokenId)) revert NotApprovedOrOwner();
        usageAuthorizations[tokenId][user] = false;
        emit UsageRevoked(tokenId, user);
    }

    function delegateAccess(uint256 tokenId, address delegate) external {
        if (msg.sender != ownerOf(tokenId)) revert NotApprovedOrOwner();
        delegatedAccess[tokenId] = delegate;
        emit AccessDelegated(tokenId, delegate);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {
        if (to.code.length == 0) return; // EOA — no callback required.
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            if (retval != IERC721Receiver.onERC721Received.selector) revert UnsafeRecipient();
        } catch {
            revert UnsafeRecipient();
        }
    }

    function iTransfer(address to, uint256 tokenId, IntelligentData[] calldata newData, TransferProof calldata transferProof)
        external
    {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotApprovedOrOwner();
        if (to == address(0)) revert InvalidAddress();
        if (newData.length == 0) revert InvalidData();

        address from = ownerOf(tokenId);
        bytes32 newHash = _hashData(newData);
        // Optional caller-supplied integrity check: if non-zero, must match the locally
        // computed hash. Prevents UI/contract drift where the operator thinks they're
        // committing one payload and the contract stores another.
        if (transferProof.newDataHash != bytes32(0) && transferProof.newDataHash != newHash) {
            revert InvalidProof();
        }
        if (
            !verifier.verifyTransfer(
                tokenId,
                from,
                to,
                newHash,
                transferProof.encryptedKeyHash,
                transferProof.proof
            )
        ) revert InvalidProof();

        _transfer(from, to, tokenId);
        encryptedKeyHash[tokenId] = transferProof.encryptedKeyHash;
        _replaceData(tokenId, newData);

        emit IntelligentTransfer(
            tokenId,
            from,
            to,
            newHash,
            transferProof.encryptedKeyHash,
            transferProof.newUri
        );
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) private view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return spender == tokenOwner || spender == _tokenApprovals[tokenId] || isApprovedForAll(tokenOwner, spender);
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        if (ownerOf(tokenId) != from) revert NotApprovedOrOwner();
        if (to == address(0)) revert InvalidAddress();

        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _replaceData(uint256 tokenId, IntelligentData[] calldata data) private {
        delete _intelligentData[tokenId];
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i].dataHash == bytes32(0)) revert InvalidData();
            _intelligentData[tokenId].push(data[i]);
            emit IntelligentDataItem(tokenId, i, data[i].label, data[i].dataHash, data[i].uri);
        }
        bytes32 newHash = _hashData(data);
        currentDataHash[tokenId] = newHash;
        emit IntelligentDataUpdated(tokenId, newHash, data[0].uri);
    }

    function _hashData(IntelligentData[] calldata data) private pure returns (bytes32) {
        bytes32 rolling = bytes32(0);
        for (uint256 i = 0; i < data.length; i++) {
            rolling = keccak256(abi.encode(rolling, data[i].label, data[i].dataHash, data[i].uri));
        }
        return rolling;
    }
}
