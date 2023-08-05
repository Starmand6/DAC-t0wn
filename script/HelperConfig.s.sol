// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address controller;
        address operatorStore;
        address paymentTerminalStore3_1_1;
        address ethPaymentTerminal3_1_1;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 5) {
            activeNetworkConfig = getGoerliConfig();
        }
        if (block.chainid == 1) {
            activeNetworkConfig = getMainnetConfig();
        }
    }

    function getGoerliConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory goerliConfig = NetworkConfig({
            controller: 0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6, // JBController 3_1
            operatorStore: 0x99dB6b517683237dE9C494bbd17861f3608F3585,
            paymentTerminalStore3_1_1: 0x5d8eC74256DB2326843714B852df3acE45144492,
            ethPaymentTerminal3_1_1: 0x82129d4109625F94582bDdF6101a8Cd1a27919f5
        });
        return goerliConfig;
    }

    function getMainnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory mainnetConfig = NetworkConfig({
            controller: 0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b, // JBController 3_1
            operatorStore: 0x6F3C5afCa0c9eDf3926eF2dDF17c8ae6391afEfb,
            paymentTerminalStore3_1_1: 0x82129d4109625F94582bDdF6101a8Cd1a27919f5,
            ethPaymentTerminal3_1_1: 0x457cD63bee88ac01f3cD4a67D5DCc921D8C0D573
        });
        return mainnetConfig;
    }
}
