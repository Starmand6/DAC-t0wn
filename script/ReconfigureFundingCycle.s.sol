// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {JBETHPaymentTerminal3_1_2} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_2.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";

// Script to change an existing JB project's cycle parameters. Three configurations have been abstracted down to one number input.
contract ReconfigureFundingCycle is Script {
    // Campaign contracts
    IJBController3_1 controller;
    IJBPaymentTerminal jbETHPaymentTerminal3_1_2;
    address delegate; // In storage to avoid stack too deep errors.
    uint256 projectID;

    // JB Project Launch struct parameters (in storage to avoid stack too deep errors)
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData cycleData;
    JBFundingCycleMetadata _cycleMetadata;
    IJBPaymentTerminal[] _terminals; // default empty
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] fundAccessConstraints; // Default empty

    event ProjectCycleReconfigured(uint256 _projectID, uint8 _result, address _delegate);

    function run(uint256 _projectID, uint8 _result, uint256 _duration, address _delegate) external returns (uint256) {
        vm.startBroadcast();
        HelperConfig helperConfig = new HelperConfig();
        (address _controller,, address _ethPaymentTerminal3_1_2) = helperConfig.activeNetworkConfig();
        controller = IJBController3_1(_controller);
        jbETHPaymentTerminal3_1_2 = IJBPaymentTerminal(_ethPaymentTerminal3_1_2);
        projectID = _projectID;
        delegate = _delegate;

        console.log("Calling reconfigureFundingCyclesOf() on JB controller...");
        uint256 _configuration = reconfigureFundingCyclesOf(_result, _duration);
        console.log("Cycle has been reconfigured.");
        vm.stopBroadcast();

        return (_configuration);
    }

    // Reconfigures funding cycles for a project with an attached delegate. Only a project's owner or operator can
    // configure its funding cycles. The same delegate/DominantJuice contract address must be used throughout. Based
    // on cycle results, the next cycle needs to be reconfigured accordingly before the cycle is over.
    // @param _projectID The ID of the project for which funding cycles are being reconfigured.
    // @param _result Campaign result: 0 == failure, 1 == success, 2 == too close to call. Sets frozen cycle
    // @param _cycleDuration Duration of the next cycle in seconds.
    // @return configuration The configuration of the successfully reconfigured funding cycle.
    function reconfigureFundingCyclesOf(uint8 _result, uint256 _cycleDuration) public returns (uint256 configuration) {
        require(_result < 4, "Input must be 0 (fail), 1 (success), or 2 (freeze)");
        bool _pauseTransfers;
        uint256 _redemptionRate;
        bool _pauseDistributions;
        bool _pauseRedeem;
        bool _pauseBurn;
        bool _useDataSourceForRedeem;

        if (_result == 0) {
            // If cycle failed to meet funding goal, this is a pledger redemption closing cycle.
            _pauseTransfers = false;
            _redemptionRate = 10000; // This is 100% with two decimal places
            _pauseDistributions = true;
            _pauseRedeem = false;
            _pauseBurn = false;
            _useDataSourceForRedeem = true;
        } else if (_result == 1) {
            // If cycle has met funding goal, this is a project creator payout closing cycle.
            // This struct defines the successful fund payouts from JB to project creator.
            fundAccessConstraints.push(JBFundAccessConstraints({
                terminal: jbETHPaymentTerminal3_1_2,
                token: 0x000000000000000000000000000000000000EEEe,
                distributionLimit: 1e18,
                distributionLimitCurrency: 1,
                overflowAllowance: 0,
                overflowAllowanceCurrency: 1
            }));
            _pauseTransfers = true;
            _redemptionRate = 0;
            _pauseDistributions = false;
            _pauseRedeem = true;
            _pauseBurn = true;
            _useDataSourceForRedeem = false;
        } else if (_result == 3) {
            _pauseTransfers = false;
            _redemptionRate = 10000;
            _pauseDistributions = false;
            _pauseRedeem = false;
            _pauseBurn = false;
            _useDataSourceForRedeem = false;
            } else {
            // Result == 2: Frozen cycle to allow time to reconfigure next payout or redemption cycle. This should
            // be chosen if campaign is too close to call or manager wants to wait to see if there are any last minute
            // target-meeting pledges.
            _pauseTransfers = true;
            _redemptionRate = 0;
            _pauseDistributions = true;
            _pauseRedeem = true;
            _pauseBurn = true;
            _useDataSourceForRedeem = false;
        }

        // Project's existing metadata (name, logo, description, etc) is used for subsequent cycles, so is not
        // sent in the reconfigure call. If desired, it can be changed through the Juicebox front end.

        cycleData = JBFundingCycleData({
            duration: _cycleDuration,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        // Reconfigure the funding cycles.
        uint256 reconfiguration = _reconfigureFundingCyclesOf(
            fundAccessConstraints,
            cycleData,
            _pauseTransfers,
            _redemptionRate,
            _pauseDistributions,
            _pauseRedeem,
            _pauseBurn,
            _useDataSourceForRedeem
        );

        emit ProjectCycleReconfigured(projectID, _result, delegate);

        return reconfiguration;
    }

    // Calls JB controller to reconfigure funding cycles for a project with existing data source address.
    // All DAC campaign-affecting input parameters are set in reconfigureFundingCyclesOf().
    function _reconfigureFundingCyclesOf(
        JBFundAccessConstraints[] memory _fundAccessConstraints,
        JBFundingCycleData memory _cycleData,
        bool _pauseTransfers,
        uint256 _redemptionRate,
        bool _pauseDistributions,
        bool _pauseRedeem,
        bool _pauseBurn,
        bool _useDataSourceForRedeem
    ) internal returns (uint256) {
        return controller.reconfigureFundingCyclesOf(
            projectID,
            _cycleData,
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: _pauseTransfers
                }),
                reservedRate: 0,
                redemptionRate: _redemptionRate,
                ballotRedemptionRate: 0,
                pausePay: true,
                pauseDistributions: _pauseDistributions,
                pauseRedeem: _pauseRedeem,
                pauseBurn: _pauseBurn,
                allowMinting: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                preferClaimedTokenOverride: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: false,
                useDataSourceForRedeem: _useDataSourceForRedeem,
                dataSource: delegate,
                metadata: 0
            }),
            block.timestamp, // The "now" timestamp means changes will take place starting with the next cycle. Can't alter current cycle
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );
    }
}
