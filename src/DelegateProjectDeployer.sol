// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DominantJuice} from "./DominantJuice.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBProjects} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
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
//import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
//import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
//import {LaunchFundingCyclesData} from "./structs/LaunchFundingCyclesData.sol";
import {LaunchProjectData} from "./structs/LaunchProjectData.sol";
//import {ReconfigureFundingCyclesData} from "./structs/ReconfigureFundingCyclesData.sol";

/// @notice Deploys a project, or reconfigure an existing project's funding cycles, with a newly deployed Delegate attached.
contract DelegateProjectDeployer is JBOperatable {
    /// @notice The dominant assurance contract (DAC) instance
    DominantJuice public delegate;

    // Project Launch parameters and addresses
    IJBController3_1 public controller; // Controller that configures funding cycles
    IJBSingleTokenPaymentTerminalStore3_1_1 public paymentTerminalStore; // Stores all payment terminals
    JBETHPaymentTerminal3_1_1 public paymentTerminal; // Default ETH payment terminal
    IJBPaymentTerminal[] _terminals; // default empty
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty

    // Storage Variables and Mappings
    // ID is in storage to avoid "stack too depp" compile error. Refactoring needed after hackathon.
    uint256 public projectID;
    mapping(uint256 => address) public projectOwner;
    /// @notice Mapping to easily find the delegate address for each projectID.
    mapping(uint256 => address) public delegateOfProject;

    event DelegateDeployed(uint256 _projectID, address _delegate, address _owner);

    constructor(address _controller, address _operatorStore, address _paymentTerminalStore, address _paymentTerminal)
        JBOperatable(IJBOperatorStore(_operatorStore))
    {
        controller = IJBController3_1(_controller);
        paymentTerminalStore = IJBSingleTokenPaymentTerminalStore3_1_1(_paymentTerminalStore);
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
    /// @return _projectID The ID of the newly configured project.
    function launchProjectFor(
        address _owner,
        string calldata _ipfsCID,
        uint256 _cycleTarget,
        uint256 _startTime,
        uint256 _duration,
        uint256 _minimumPledgeAmount
    ) external returns (uint256 _projectID) {
        require(_owner != address(0), "Invalid address");
        // Get the project ID, optimistically knowing it will be one greater than the current count.
        IJBProjects projects = controller.projects();
        _projectID = projects.count() + 1; // TODO: Need to add projects contract here?

        //_projectID = controller.projects().count() + 1;

        // Deploy the DAC and store the instance. _owner will become new owner of DAC.
        DominantJuice _delegate = deployDelegateFor(_owner, _projectID);

        // Set project Launch variables:

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
        // use the deployed dominant assurance contract as the Data source for the first cycle of the project.
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

        // Launch the project.
        _launchProjectFor(_owner, _startTime, _projectMetadata, _cycleData, _launchProjectData);

        // Initialize the DominantJuice delegate.
        _delegate.initialize(_projectID, _cycleTarget, _minimumPledgeAmount, controller, paymentTerminalStore);

        projectOwner[_projectID] = _owner;

        return _projectID;
    }

    /// @notice Deploys a dominant assurance escrow delegate for the provided project ID.
    /// @param _projectID The ID of the project for which the delegate will be deployed.
    /// @return delegate The address of the newly deployed DominantJuice delegate.
    function deployDelegateFor(address _owner, uint256 _projectID) public returns (DominantJuice) {
        require(_owner != address(0), "Invalid address");
        // Deploys a new dominant assurance escrow contract
        DominantJuice _delegate = new DominantJuice();
        delegateOfProject[_projectID] = address(_delegate);

        // Transfer delegate / DAC ownership to launchProjectFor() _owner parameter.
        _delegate.transferOwnership(_owner);

        emit DelegateDeployed(_projectID, address(_delegate), _owner);

        return _delegate;
    }

    /// @notice Reconfigures funding cycles for a project with an attached delegate.
    /// @dev Only a project's owner or operator can configure its funding cycles. We need to again
    /// use the same delegate/DominantJuice contract address. Based on cycle results, the next cycle
    /// needs to be reconfigured accordingly before the cycle is over. See the result parameter below.
    /// @param _projectID The ID of the project for which funding cycles are being reconfigured.
    /// @param _result Campaign result: 0 = too close to call; set frozen cycle, 1 = success, 2 = failure,
    /// @return configuration The configuration of the successfully reconfigured funding cycle.
    function reconfigureFundingCyclesOf(uint256 _projectID, uint8 _result) external returns (uint256 configuration) {
        require(projectOwner[_projectID] == msg.sender, "Caller is not project owner.");
        require(_result <= 2, "Input must be 0 (freeze), 1 (success), or 2 (fail)");

        uint256 _cycleDuration;
        bool _pauseTransfers;
        uint256 _redemptionRate;
        bool _pauseDistributions;
        bool _pauseRedeem;
        bool _pauseBurn;
        bool _useDataSourceForRedeem;
        // Storing _projectId to avoid stack too deep errors.
        projectID = _projectID;

        // If near the end of the cyle, results are too close to call, create a "frozen" cycle to allow
        // for any final minutes or seconds pledging.
        if (_result == 0) {
            // Frozen cycle lasts for two days to allow time to reconfigure next payout or redemption cycle.
            _cycleDuration = 172800; // Two days in seconds
            _pauseTransfers = true;
            _redemptionRate = 0;
            _pauseDistributions = true;
            _pauseRedeem = true;
            _pauseBurn = true;
            _useDataSourceForRedeem = false;
        } else if (_result == 1) {
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
    /// with existing data source address.
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
                dataSource: address(delegate),
                metadata: 0
            }),
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );
    }

    function getDelegateOfProject(uint256 _projectID) external view returns (address) {
        return delegateOfProject[_projectID];
    }
}
