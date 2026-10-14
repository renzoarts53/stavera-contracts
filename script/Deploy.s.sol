// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StaveraTransferRegistry} from "../src/StaveraTransferRegistry.sol";

/// @notice Deploys StaveraTransferRegistry to Arc Testnet (chain id 5042002).
/// The signer comes from the command line (a Foundry keystore via --account, or --ledger).
/// No private key is read from, or written to, this file.
contract Deploy is Script {
    uint256 internal constant ARC_TESTNET_CHAIN_ID = 5042002;

    function run() external returns (StaveraTransferRegistry registry) {
        require(block.chainid == ARC_TESTNET_CHAIN_ID, "Wrong network: expected Arc Testnet (5042002)");

        vm.startBroadcast();
        registry = new StaveraTransferRegistry();
        vm.stopBroadcast();

        console.log("StaveraTransferRegistry deployed at:", address(registry));
    }
}
