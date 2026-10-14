// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title StaveraTransferRegistry
/// @notice An optional, public journal in which each wallet records ITS OWN cross-chain
///         transfers made through Stavera (source transaction hash, route, and later the
///         destination transaction hash).
/// @dev Holds no funds, moves no tokens, has no owner, no admin and no upgrade path.
///      Records are keyed by (msg.sender, sourceTxHash), so nobody can create, change or
///      "squat" a record that belongs to another address.
///      A record is a SELF-REPORTED note. It is NOT proof that a burn or mint happened:
///      always confirm the referenced transactions on the block explorers.
contract StaveraTransferRegistry {
    enum Status {
        None, // never recorded
        Started, // source transaction recorded
        Completed, // destination transaction recorded
        Failed // owner marked it as failed / needs recovery
    }

    struct Transfer {
        Status status;
        uint32 sourceDomain; // Circle CCTP domain id of the source chain
        uint32 destinationDomain; // Circle CCTP domain id of the destination chain
        uint64 createdAt;
        uint64 updatedAt;
        bytes32 sourceTxHash;
        bytes32 destinationTxHash;
    }

    /// @notice Largest page size accepted by {getTransfers}.
    uint256 public constant MAX_PAGE = 50;

    mapping(address owner => mapping(bytes32 sourceTxHash => Transfer)) private _transfers;
    mapping(address owner => bytes32[]) private _sourceHashes;

    event TransferRecorded(
        address indexed owner, bytes32 indexed sourceTxHash, uint32 sourceDomain, uint32 destinationDomain
    );
    event TransferCompleted(address indexed owner, bytes32 indexed sourceTxHash, bytes32 destinationTxHash);
    event TransferFailed(address indexed owner, bytes32 indexed sourceTxHash);

    error ZeroHash();
    error SameDomain();
    error AlreadyRecorded();
    error NotFound();
    error InvalidStatus(Status current);
    error PageTooLarge();

    /// @notice Record a new transfer for the caller.
    /// @param sourceTxHash Hash of the source-chain transaction (the burn). Must be non-zero.
    /// @param sourceDomain CCTP domain of the source chain.
    /// @param destinationDomain CCTP domain of the destination chain. Must differ from the source.
    function record(bytes32 sourceTxHash, uint32 sourceDomain, uint32 destinationDomain) external {
        if (sourceTxHash == bytes32(0)) revert ZeroHash();
        if (sourceDomain == destinationDomain) revert SameDomain();

        Transfer storage t = _transfers[msg.sender][sourceTxHash];
        if (t.status != Status.None) revert AlreadyRecorded();

        uint64 nowTs = uint64(block.timestamp);
        t.status = Status.Started;
        t.sourceDomain = sourceDomain;
        t.destinationDomain = destinationDomain;
        t.createdAt = nowTs;
        t.updatedAt = nowTs;
        t.sourceTxHash = sourceTxHash;

        _sourceHashes[msg.sender].push(sourceTxHash);
        emit TransferRecorded(msg.sender, sourceTxHash, sourceDomain, destinationDomain);
    }

    /// @notice Attach the destination (mint) transaction hash to one of the caller's records.
    /// @dev Allowed from Started or Failed. A Completed record is final.
    function complete(bytes32 sourceTxHash, bytes32 destinationTxHash) external {
        if (destinationTxHash == bytes32(0)) revert ZeroHash();

        Transfer storage t = _transfers[msg.sender][sourceTxHash];
        if (t.status == Status.None) revert NotFound();
        if (t.status == Status.Completed) revert InvalidStatus(t.status);

        t.status = Status.Completed;
        t.destinationTxHash = destinationTxHash;
        t.updatedAt = uint64(block.timestamp);
        emit TransferCompleted(msg.sender, sourceTxHash, destinationTxHash);
    }

    /// @notice Flag one of the caller's records as failed (for example "mint failed, needs recovery").
    /// @dev Only a Started record can be flagged. It can still be completed later.
    function markFailed(bytes32 sourceTxHash) external {
        Transfer storage t = _transfers[msg.sender][sourceTxHash];
        if (t.status == Status.None) revert NotFound();
        if (t.status != Status.Started) revert InvalidStatus(t.status);

        t.status = Status.Failed;
        t.updatedAt = uint64(block.timestamp);
        emit TransferFailed(msg.sender, sourceTxHash);
    }

    /// @notice Read one record. Returns a zeroed struct (status None) when it does not exist.
    function getTransfer(address owner, bytes32 sourceTxHash) external view returns (Transfer memory) {
        return _transfers[owner][sourceTxHash];
    }

    /// @notice Number of records an address has made.
    function transferCount(address owner) external view returns (uint256) {
        return _sourceHashes[owner].length;
    }

    /// @notice A page of an address's records, oldest first.
    /// @param limit At most {MAX_PAGE}.
    function getTransfers(address owner, uint256 offset, uint256 limit) external view returns (Transfer[] memory page) {
        if (limit > MAX_PAGE) revert PageTooLarge();

        bytes32[] storage hashes = _sourceHashes[owner];
        uint256 total = hashes.length;
        if (offset >= total || limit == 0) return new Transfer[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        page = new Transfer[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = _transfers[owner][hashes[i]];
        }
    }
}
