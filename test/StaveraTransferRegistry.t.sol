// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StaveraTransferRegistry} from "../src/StaveraTransferRegistry.sol";

contract StaveraTransferRegistryTest is Test {
    StaveraTransferRegistry internal reg;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant SRC = keccak256("source tx 1");
    bytes32 internal constant SRC2 = keccak256("source tx 2");
    bytes32 internal constant DST = keccak256("destination tx 1");

    uint32 internal constant ARC = 26;
    uint32 internal constant ARB = 3;
    uint32 internal constant ETH = 0; // domain 0 is a valid domain

    event TransferRecorded(
        address indexed owner, bytes32 indexed sourceTxHash, uint32 sourceDomain, uint32 destinationDomain
    );
    event TransferCompleted(address indexed owner, bytes32 indexed sourceTxHash, bytes32 destinationTxHash);
    event TransferFailed(address indexed owner, bytes32 indexed sourceTxHash);

    function _u(StaveraTransferRegistry.Status s) internal pure returns (uint256) {
        return uint256(uint8(s));
    }

    function setUp() public {
        reg = new StaveraTransferRegistry();
        vm.warp(1_000_000);
    }

    // ---------- record ----------

    function test_record_storesTransferAndEmits() public {
        vm.expectEmit(true, true, false, true, address(reg));
        emit TransferRecorded(alice, SRC, ARC, ARB);

        vm.prank(alice);
        reg.record(SRC, ARC, ARB);

        StaveraTransferRegistry.Transfer memory t = reg.getTransfer(alice, SRC);
        assertEq(_u(t.status), _u(StaveraTransferRegistry.Status.Started));
        assertEq(uint256(t.sourceDomain), uint256(ARC));
        assertEq(uint256(t.destinationDomain), uint256(ARB));
        assertEq(uint256(t.createdAt), uint256(1_000_000));
        assertEq(uint256(t.updatedAt), uint256(1_000_000));
        assertEq(t.sourceTxHash, SRC);
        assertEq(t.destinationTxHash, bytes32(0));
        assertEq(reg.transferCount(alice), 1);
    }

    function test_record_allowsDomainZero() public {
        vm.prank(alice);
        reg.record(SRC, ETH, ARC);
        assertEq(uint256(reg.getTransfer(alice, SRC).sourceDomain), uint256(0));
    }

    function test_record_revertsOnZeroHash() public {
        vm.prank(alice);
        vm.expectRevert(StaveraTransferRegistry.ZeroHash.selector);
        reg.record(bytes32(0), ARC, ARB);
    }

    function test_record_revertsWhenDomainsEqual() public {
        vm.prank(alice);
        vm.expectRevert(StaveraTransferRegistry.SameDomain.selector);
        reg.record(SRC, ARC, ARC);
    }

    function test_record_revertsOnDuplicate() public {
        vm.startPrank(alice);
        reg.record(SRC, ARC, ARB);
        vm.expectRevert(StaveraTransferRegistry.AlreadyRecorded.selector);
        reg.record(SRC, ARC, ARB);
        vm.stopPrank();
        assertEq(reg.transferCount(alice), 1);
    }

    function test_record_duplicateRevertsEvenAfterCompletion() public {
        vm.startPrank(alice);
        reg.record(SRC, ARC, ARB);
        reg.complete(SRC, DST);
        vm.expectRevert(StaveraTransferRegistry.AlreadyRecorded.selector);
        reg.record(SRC, ARC, ARB);
        vm.stopPrank();
    }

    // ---------- authorization / isolation ----------

    function test_stranger_cannotCompleteOthersRecord() public {
        vm.prank(alice);
        reg.record(SRC, ARC, ARB);

        vm.prank(bob);
        vm.expectRevert(StaveraTransferRegistry.NotFound.selector);
        reg.complete(SRC, DST);

        assertEq(_u(reg.getTransfer(alice, SRC).status), _u(StaveraTransferRegistry.Status.Started));
        assertEq(reg.getTransfer(alice, SRC).destinationTxHash, bytes32(0));
    }

    function test_stranger_cannotMarkOthersRecordFailed() public {
        vm.prank(alice);
        reg.record(SRC, ARC, ARB);

        vm.prank(bob);
        vm.expectRevert(StaveraTransferRegistry.NotFound.selector);
        reg.markFailed(SRC);

        assertEq(_u(reg.getTransfer(alice, SRC).status), _u(StaveraTransferRegistry.Status.Started));
    }

    function test_stranger_cannotSquatSameHash() public {
        vm.prank(bob);
        reg.record(SRC, ARC, ARB);

        vm.prank(alice);
        reg.record(SRC, ARC, ETH);

        assertEq(uint256(reg.getTransfer(alice, SRC).destinationDomain), uint256(ETH));
        assertEq(uint256(reg.getTransfer(bob, SRC).destinationDomain), uint256(ARB));
    }

    // ---------- complete ----------

    function test_complete_setsDestinationAndEmits() public {
        vm.prank(alice);
        reg.record(SRC, ARC, ARB);

        vm.warp(1_000_500);
        vm.expectEmit(true, true, false, true, address(reg));
        emit TransferCompleted(alice, SRC, DST);

        vm.prank(alice);
        reg.complete(SRC, DST);

        StaveraTransferRegistry.Transfer memory t = reg.getTransfer(alice, SRC);
        assertEq(_u(t.status), _u(StaveraTransferRegistry.Status.Completed));
        assertEq(t.destinationTxHash, DST);
        assertEq(uint256(t.createdAt), uint256(1_000_000));
        assertEq(uint256(t.updatedAt), uint256(1_000_500));
    }

    function test_complete_revertsWhenUnknown() public {
        vm.prank(alice);
        vm.expectRevert(StaveraTransferRegistry.NotFound.selector);
        reg.complete(SRC, DST);
    }

    function test_complete_revertsOnZeroDestinationHash() public {
        vm.startPrank(alice);
        reg.record(SRC, ARC, ARB);
        vm.expectRevert(StaveraTransferRegistry.ZeroHash.selector);
        reg.complete(SRC, bytes32(0));
        vm.stopPrank();
    }

    function test_complete_isFinal() public {
        vm.startPrank(alice);
        reg.record(SRC, ARC, ARB);
        reg.complete(SRC, DST);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaveraTransferRegistry.InvalidStatus.selector, StaveraTransferRegistry.Status.Completed
            )
        );
        reg.complete(SRC, keccak256("another"));
        vm.stopPrank();
        assertEq(reg.getTransfer(alice, SRC).destinationTxHash, DST);
    }

    // ---------- markFailed ----------

    function test_markFailed_thenCompleteAllowed() public {
        vm.startPrank(alice);
        reg.record(SRC, ARC, ARB);

        vm.expectEmit(true, true, false, false, address(reg));
        emit TransferFailed(alice, SRC);
        reg.markFailed(SRC);
        assertEq(_u(reg.getTransfer(alice, SRC).status), _u(StaveraTransferRegistry.Status.Failed));

        reg.complete(SRC, DST);
        vm.stopPrank();
        assertEq(_u(reg.getTransfer(alice, SRC).status), _u(StaveraTransferRegistry.Status.Completed));
    }

    function test_markFailed_revertsWhenUnknown() public {
        vm.prank(alice);
        vm.expectRevert(StaveraTransferRegistry.NotFound.selector);
        reg.markFailed(SRC);
    }

    function test_markFailed_revertsWhenAlreadyFailedOrCompleted() public {
        vm.startPrank(alice);
        reg.record(SRC, ARC, ARB);
        reg.markFailed(SRC);
        vm.expectRevert(
            abi.encodeWithSelector(StaveraTransferRegistry.InvalidStatus.selector, StaveraTransferRegistry.Status.Failed)
        );
        reg.markFailed(SRC);

        reg.record(SRC2, ARC, ARB);
        reg.complete(SRC2, DST);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaveraTransferRegistry.InvalidStatus.selector, StaveraTransferRegistry.Status.Completed
            )
        );
        reg.markFailed(SRC2);
        vm.stopPrank();
    }

    // ---------- views / pagination ----------

    function test_getTransfer_unknownIsEmpty() public {
        StaveraTransferRegistry.Transfer memory t = reg.getTransfer(alice, SRC);
        assertEq(_u(t.status), _u(StaveraTransferRegistry.Status.None));
        assertEq(uint256(t.createdAt), uint256(0));
    }

    function test_getTransfers_pagination() public {
        vm.startPrank(alice);
        for (uint256 i = 1; i <= 5; i++) {
            reg.record(bytes32(i), ARC, ARB);
        }
        vm.stopPrank();

        assertEq(reg.transferCount(alice), 5);

        StaveraTransferRegistry.Transfer[] memory first = reg.getTransfers(alice, 0, 2);
        assertEq(first.length, 2);
        assertEq(first[0].sourceTxHash, bytes32(uint256(1)));
        assertEq(first[1].sourceTxHash, bytes32(uint256(2)));

        StaveraTransferRegistry.Transfer[] memory last = reg.getTransfers(alice, 4, 10);
        assertEq(last.length, 1);
        assertEq(last[0].sourceTxHash, bytes32(uint256(5)));

        assertEq(reg.getTransfers(alice, 5, 10).length, 0);
        assertEq(reg.getTransfers(alice, 0, 0).length, 0);
        assertEq(reg.getTransfers(bob, 0, 10).length, 0);
    }

    function test_getTransfers_revertsWhenPageTooLarge() public {
        vm.expectRevert(StaveraTransferRegistry.PageTooLarge.selector);
        reg.getTransfers(alice, 0, 51);
    }

    // ---------- no funds ----------

    function test_rejectsPlainEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(reg).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(reg).balance, 0);
    }

    function test_rejectsEtherOnFunctionCall() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(reg).call{value: 1 ether}(abi.encodeCall(reg.record, (SRC, ARC, ARB)));
        assertFalse(ok);
        assertEq(address(reg).balance, 0);
    }

    // ---------- fuzz ----------

    function testFuzz_recordsAreIsolatedPerOwner(address a, address b, bytes32 h, uint32 s, uint32 d) public {
        vm.assume(a != b && a != address(0) && b != address(0));
        vm.assume(h != bytes32(0) && s != d);

        vm.prank(a);
        reg.record(h, s, d);

        assertEq(_u(reg.getTransfer(b, h).status), _u(StaveraTransferRegistry.Status.None));

        vm.prank(b);
        vm.expectRevert(StaveraTransferRegistry.NotFound.selector);
        reg.complete(h, keccak256("x"));

        vm.prank(b);
        reg.record(h, d, s);
        assertEq(uint256(reg.getTransfer(a, h).sourceDomain), uint256(s));
        assertEq(uint256(reg.getTransfer(b, h).sourceDomain), uint256(d));
    }
}
