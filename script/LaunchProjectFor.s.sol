// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";

// Imports for launchProjectFor():
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBTokenAmount} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";

contract LaunchProjectFor is Script {
    // Variables for JB functions: launchProjectFor(), pay(), redeemTokensOf()
    DominantJuice dominantJuice = DominantJuice(payable(0xa9E390E216E072106B989fcc8a41D3858f4dAAd7));
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleMetadata _metadata;
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty

    // Dominant Assurance variables and instances
    uint256 public projectID;
    uint256 public constant CYCLE_TARGET = 100000 gwei; // 0.0001 ether, 1e14 wei
    uint256 public constant CYCLE_DURATION = 30 minutes;
    uint256 public constant MIN_PLEDGE_AMOUNT = 1000 gwei; // 0.000001 ether, 1e12 wei
    uint32 public constant MAX_EARLY_PLEDGERS = 2;
    uint256 public constant TOTAL_REFUND_BONUS = 10000 gwei; // 0.00001 ether, 1e13 wei
    address ethToken = 0x000000000000000000000000000000000000EEEe;
    JBETHPaymentTerminal3_1_1 goerliETHTerminal3_1_1 =
        JBETHPaymentTerminal3_1_1(0x82129d4109625F94582bDdF6101a8Cd1a27919f5);

    function run() external returns (uint256) {
        HelperConfig helperConfig = new HelperConfig();
        (address _controller,,) = helperConfig.activeNetworkConfig();
        IJBController3_1 controller = IJBController3_1(_controller);

        // Project Launch variables:
        _projectMetadata = JBProjectMetadata({content: "testDominantJuice #1", domain: 1});

        _data = JBFundingCycleData({
            duration: CYCLE_DURATION,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false, pauseTransfers: true}),
            reservedRate: 0, // 0%
            redemptionRate: 0, // 0% in cycle 1. If failed campaign, change to 100% for cycle 2.
            ballotRedemptionRate: 0,
            pausePay: false, // Change to true for cycle 2
            pauseDistributions: true, // if successful cycle, change to false for cycle 2.
            pauseRedeem: true, // if failed cycle, change to false in cycle 2
            pauseBurn: true, // if failed cycle, change to false in cycle 2
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: true,
            useDataSourceForRedeem: false, // if failed campaign, must be changed to true in cycle 2
            dataSource: address(dominantJuice),
            metadata: 0
        });

        _terminals.push(goerliETHTerminal3_1_1);

        vm.startBroadcast();
        projectID = controller.launchProjectFor(
            msg.sender,
            _projectMetadata,
            _data,
            _metadata,
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );
        dominantJuice.initialize(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
        vm.stopBroadcast();

        return projectID;
    }
}
