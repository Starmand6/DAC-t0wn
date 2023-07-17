// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MyDelegateDeployer} from "./MyDelegateDeployer.sol";
import {DominantJuice} from "./DominantJuice.sol";
import {DeployMyDelegateData} from "./structs/DeployMyDelegateData.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {LaunchFundingCyclesData} from "./structs/LaunchFundingCyclesData.sol";
import {LaunchProjectData} from "./structs/LaunchProjectData.sol";
import {ReconfigureFundingCyclesData} from "./structs/ReconfigureFundingCyclesData.sol";

/// @notice Deploys a project, or reconfigure an existing project's funding cycles, with a newly deployed Delegate attached.
contract MyDelegateProjectDeployer is JBOperatable {
    /// @notice The contract responsible for deploying the delegate.
    MyDelegateDeployer public immutable delegateDeployer;
    DominantJuice public _delegate;

    // Project Launch data structs and addresses
    IJBPaymentTerminal[] _terminals; // default empty
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    JBETHPaymentTerminal3_1_1 public paymentTerminal; // Default ETH terminal for hackathon purposes
    IJBController3_1 public controller; // Controller that configures funding cycles
    IJBSingleTokenPaymentTerminalStore3_1_1 public paymentTerminalStore;
    // ID is in storage to avoid "stack too depp" compile error. Refactoring needed after hackathon.
    uint256 public projectID;

    /// @param _delegateDeployer The delegate deployer.
    constructor(
        MyDelegateDeployer _delegateDeployer,
        IJBController3_1 _controller,
        IJBOperatorStore _operatorStore,
        IJBSingleTokenPaymentTerminalStore3_1_1 _paymentTerminalStore,
        JBETHPaymentTerminal3_1_1 _paymentTerminal
    ) JBOperatable(_operatorStore) {
        delegateDeployer = _delegateDeployer;
        controller = _controller;
        paymentTerminalStore = _paymentTerminalStore;
        paymentTerminal = JBETHPaymentTerminal3_1_1(_paymentTerminal);
        _terminals.push(paymentTerminal);
    }

    /// @notice Launches a new project with a delegate attached.
    /// @param _owner The address to set as the owner of the project. The project's ERC-721 will be owned by this address.
    /// @param _ipfsCID The CID obtained from IPFS for uploading project's metadata. Hardcoded here for Hackathon purposes
    /// @param _cycleTarget Funding target for the dominant assurance cycle/campaign.
    /// @param _startTime The timestamp that the cycle is desired to start.
    /// @param _duration The duration of the cycle in seconds.
    /// @param _minimumPledgeAmount Minimum amount that payers can pledge.
    /// @param _maxEarlyPledgers Maximum allowed early plegers for funding cycle.
    /// @return _projectID The ID of the newly configured project.
    function launchProjectFor(
        address _owner,
        string calldata _ipfsCID,
        uint256 _cycleTarget,
        uint256 _startTime,
        uint256 _duration,
        uint256 _minimumPledgeAmount,
        uint32 _maxEarlyPledgers
    ) external returns (uint256 _projectID) {
        // Get the project ID, optimistically knowing it will be one greater than the current count.
        _projectID = controller.projects().count() + 1;

        // Deploy the DominantJuice delegate contract.
        _delegate = delegateDeployer.deployDelegateFor(
            _owner,
            _projectID,
            _cycleTarget,
            _minimumPledgeAmount,
            _maxEarlyPledgers,
            controller,
            controller.directory(),
            paymentTerminalStore
        );

        _ipfsCID; // Placed inside function to silence unused parameter warning.
        // Project's metadata (name, logo, description, social media links) file hash and codec from IPFS
        JBProjectMetadata memory _projectMetadata =
            JBProjectMetadata({content: "QmZpzHK5tuNwVkm2EyJp2tVraD6xSJqdF2TE39hzinr9Bs", domain: 0});

        JBFundingCycleData memory _cycleData = JBFundingCycleData({
            duration: _duration,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        // This exact configuration will allow for pledger payments, no token redemptions/transfers/burns, and will
        // use the deployed Dominant Juice contract as the Data source for the first cycle of the project.
        JBFundingCycleMetadata memory _launchProjectData = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false, pauseTransfers: true}),
            reservedRate: 0,
            redemptionRate: 0,
            ballotRedemptionRate: 0,
            pausePay: false,
            pauseDistributions: true,
            pauseRedeem: true,
            pauseBurn: true,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: true,
            useDataSourceForRedeem: false,
            dataSource: address(_delegate),
            metadata: 0
        });

        // Operator struct to give project cycle reconfigure permissions to this contract.
        uint256[] memory _permissionIndexes = new uint[](1);
        _permissionIndexes[0] = 1;
        JBOperatorData memory operatorData =
            JBOperatorData({operator: address(this), domain: 0, permissionIndexes: _permissionIndexes});

        // Project creator needs to give permission to this contract to be able to reconfigure cycle.
        operatorStore.setOperator(operatorData);

        // Launch the project.
        _launchProjectFor(_owner, _startTime, _projectMetadata, _cycleData, _launchProjectData);
    }

    /// @notice Reconfigures funding cycles for a project with an attached delegate.
    /// @dev Only a project's owner or operator can configure its funding cycles. We need to again
    /// use the same delegate/DominantJuice contract address. Based on cycle results, the next cycle
    /// needs to be reconfigured accordingly before the cycle is over. See the result parameter below.
    /// @param _projectId The ID of the project for which funding cycles are being reconfigured.
    /// @param result Campaign result: 0 = too close to call; set frozen cycle, 1 = success, 2 = failure,
    /// @return configuration The configuration of the successfully reconfigured funding cycle.
    function reconfigureFundingCyclesOf(uint256 _projectId, uint8 result)
        external
        requirePermission(controller.projects().ownerOf(_projectId), _projectId, JBOperations.RECONFIGURE)
        returns (uint256 configuration)
    {
        require(result <= 2, "Input must be 0 (freeze), 1 (success), or 2 (fail)");

        uint256 _cycleDuration;
        bool _pauseTransfers;
        uint256 _redemptionRate;
        bool _pauseDistributions;
        bool _pauseRedeem;
        bool _pauseBurn;
        bool _useDataSourceForRedeem;
        // Storing _projectId to avoid stack too deep errors.
        projectID = _projectId;

        // If near the end of the cyle, results are too close to call, create a "frozen" cycle to allow
        // for any final minutes or seconds pledging.
        if (result == 0) {
            // Frozen cycle lasts for two days to allow time to reconfigure next payout or redemption cycle.
            _cycleDuration = 172800; // Two days in seconds
            _pauseTransfers = true;
            _redemptionRate = 0;
            _pauseDistributions = true;
            _pauseRedeem = true;
            _pauseBurn = true;
            _useDataSourceForRedeem = false;
        } else if (result == 1) {
            // If cycle has met funding goal, this is a project creator payout closing cycle.
            _cycleDuration = 172800; // Arbitrary two days of seconds.
            _pauseTransfers = false;
            _redemptionRate = 0;
            _pauseDistributions = false;
            _pauseRedeem = true;
            _pauseBurn = false;
            _useDataSourceForRedeem = false;
        } else {
            // If cycle failed to meet funding goal, this is a pledger redemption closing cycle.
            _cycleDuration = 172800; // Arbitrary two days of seconds.
            _pauseTransfers = false;
            _redemptionRate = 100;
            _pauseDistributions = true;
            _pauseRedeem = false;
            _pauseBurn = false;
            _useDataSourceForRedeem = true;
        }

        // Project's metadata (name, logo, description, etc) is used for subsequent cycles, so is not sent in the
        // reconfigure call. If desired, it can be changed in the Juicebox front end.

        JBFundingCycleData memory _cycleData = JBFundingCycleData({
            duration: _cycleDuration,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        // Reconfigure the funding cycles.
        return _reconfigureFundingCyclesOf(
            _cycleData,
            _pauseTransfers,
            _redemptionRate,
            _pauseDistributions,
            _pauseRedeem,
            _pauseBurn,
            _useDataSourceForRedeem
        );
    }

    /// @notice Calls the JB controller to launch a project.
    /// @param _owner The address to set as the project's owner.
    /// @param _startTime The cycle start timestamp.
    /// @param _projectMetadata Project's metadata (name, logo, description, etc)
    /// @param _launchProjectData Data needed to launch the project.
    function _launchProjectFor(
        address _owner,
        uint256 _startTime,
        JBProjectMetadata memory _projectMetadata,
        JBFundingCycleData memory _cycleData,
        JBFundingCycleMetadata memory _launchProjectData
    ) internal {
        controller.launchProjectFor(
            _owner,
            _projectMetadata,
            _cycleData,
            _launchProjectData,
            _startTime,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );
    }

    /// @notice Calls JB controller to reconfigure funding cycles for a project.
    /// @dev All input parameters set by reconfigureFundingCyclesOf().
    /// @return The configuration of the successfully reconfigured funding cycle.
    function _reconfigureFundingCyclesOf(
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
                dataSource: address(_delegate),
                metadata: 0
            }),
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );
    }
}
