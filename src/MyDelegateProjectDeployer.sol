// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {DeployMyDelegateData} from "./structs/DeployMyDelegateData.sol";
import {LaunchProjectData} from "./structs/LaunchProjectData.sol";
import {LaunchFundingCyclesData} from "./structs/LaunchFundingCyclesData.sol";
import {ReconfigureFundingCyclesData} from "./structs/ReconfigureFundingCyclesData.sol";
import {MyDelegate} from "./MyDelegate.sol";
import {MyDelegateDeployer} from "./MyDelegateDeployer.sol";

/// @notice Deploys a project, or reconfigure an existing project's funding cycles, with a newly deployed Delegate attached.
contract MyDelegateProjectDeployer is JBOperatable {
    /// @notice The contract responsible for deploying the delegate.
    MyDelegateDeployer public immutable delegateDeployer;

    /// @param _delegateDeployer The delegate deployer.
    constructor(MyDelegateDeployer _delegateDeployer, IJBOperatorStore _operatorStore) JBOperatable(_operatorStore) {
        delegateDeployer = _delegateDeployer;
    }

    /// @notice Launches a new project with a delegate attached.
    /// @param _owner The address to set as the owner of the project. The project's ERC-721 will be owned by this address.
    /// @param _deployMyDelegateData Data necessary to deploy the delegate.
    /// @param _launchProjectData Data necessary to launch the project.
    /// @param _controller The controller with which the funding cycles should be configured.
    /// @return projectId The ID of the newly configured project.
    function launchProjectFor(
        address _owner,
        DeployMyDelegateData memory _deployMyDelegateData,
        LaunchProjectData memory _launchProjectData,
        IJBController3_1 _controller
    ) external returns (uint256 projectId) {
        // Get the project ID, optimistically knowing it will be one greater than the current count.
        projectId = _controller.projects().count() + 1;

        // Deploy the delegate contract.
        MyDelegate _delegate =
            delegateDeployer.deployDelegateFor(projectId, _deployMyDelegateData, _controller.directory());

        // Launch the project.
        _launchProjectFor(_owner, _launchProjectData, address(_delegate), _controller);
    }

    /// @notice Launches funding cycles for a project with an attached delegate.
    /// @dev Only a project's owner or operator can launch its funding cycles.
    /// @param _projectId The ID of the project for which the funding cycles will be launched.
    /// @param _deployMyDelegateData Data necessary to deploy the delegate.
    /// @param _launchFundingCyclesData Data necessary to launch the funding cycles for the project.
    /// @param _controller The controller with which the funding cycles should be configured.
    /// @return configuration The configuration of the funding cycle that was successfully created.
    function launchFundingCyclesFor(
        uint256 _projectId,
        DeployMyDelegateData memory _deployMyDelegateData,
        LaunchFundingCyclesData memory _launchFundingCyclesData,
        IJBController3_1 _controller
    )
        external
        requirePermission(_controller.projects().ownerOf(_projectId), _projectId, JBOperations.RECONFIGURE)
        returns (uint256 configuration)
    {
        // Deploy the delegate contract.
        MyDelegate _delegate =
            delegateDeployer.deployDelegateFor(_projectId, _deployMyDelegateData, _controller.directory());

        // Launch the funding cycles.
        return _launchFundingCyclesFor(_projectId, _launchFundingCyclesData, address(_delegate), _controller);
    }

    /// @notice Reconfigures funding cycles for a project with an attached delegate.
    /// @dev Only a project's owner or operator can configure its funding cycles.
    /// @param _projectId The ID of the project for which funding cycles are being reconfigured.
    /// @param _deployMyDelegateData Data necessary to deploy a delegate.
    /// @param _reconfigureFundingCyclesData Data necessary to reconfigure the funding cycle.
    /// @param _controller The controller with which the funding cycles should be configured.
    /// @return configuration The configuration of the successfully reconfigured funding cycle.
    function reconfigureFundingCyclesOf(
        uint256 _projectId,
        DeployMyDelegateData memory _deployMyDelegateData,
        ReconfigureFundingCyclesData memory _reconfigureFundingCyclesData,
        IJBController3_1 _controller
    )
        external
        requirePermission(_controller.projects().ownerOf(_projectId), _projectId, JBOperations.RECONFIGURE)
        returns (uint256 configuration)
    {
        // Deploy the delegate contract.
        MyDelegate _delegate =
            delegateDeployer.deployDelegateFor(_projectId, _deployMyDelegateData, _controller.directory());

        // Reconfigure the funding cycles.
        return _reconfigureFundingCyclesOf(_projectId, _reconfigureFundingCyclesData, address(_delegate), _controller);
    }

    /// @notice Launches a project.
    /// @param _owner The address to set as the project's owner.
    /// @param _launchProjectData Data needed to launch the project.
    /// @param _dataSource The data source to set for the project.
    /// @param _controller The controller to be used for configuring the project's funding cycles.
    function _launchProjectFor(
        address _owner,
        LaunchProjectData memory _launchProjectData,
        address _dataSource,
        IJBController3_1 _controller
    ) internal {
        _controller.launchProjectFor(
            _owner,
            _launchProjectData.projectMetadata,
            _launchProjectData.data,
            JBFundingCycleMetadata({
                global: _launchProjectData.metadata.global,
                reservedRate: _launchProjectData.metadata.reservedRate,
                redemptionRate: _launchProjectData.metadata.redemptionRate,
                ballotRedemptionRate: _launchProjectData.metadata.ballotRedemptionRate,
                pausePay: _launchProjectData.metadata.pausePay,
                pauseDistributions: _launchProjectData.metadata.pauseDistributions,
                pauseRedeem: _launchProjectData.metadata.pauseRedeem,
                pauseBurn: _launchProjectData.metadata.pauseBurn,
                allowMinting: _launchProjectData.metadata.allowMinting,
                allowTerminalMigration: _launchProjectData.metadata.allowTerminalMigration,
                allowControllerMigration: _launchProjectData.metadata.allowControllerMigration,
                holdFees: _launchProjectData.metadata.holdFees,
                preferClaimedTokenOverride: _launchProjectData.metadata.preferClaimedTokenOverride,
                useTotalOverflowForRedemptions: _launchProjectData.metadata.useTotalOverflowForRedemptions,
                useDataSourceForPay: _launchProjectData.metadata.useDataSourceForPay,
                useDataSourceForRedeem: _launchProjectData.metadata.useDataSourceForRedeem,
                // Set the delegate address as the data source of the project's funding cycle metadata.
                dataSource: _dataSource,
                metadata: _launchProjectData.metadata.metadata
            }),
            _launchProjectData.mustStartAtOrAfter,
            _launchProjectData.groupedSplits,
            _launchProjectData.fundAccessConstraints,
            _launchProjectData.terminals,
            _launchProjectData.memo
        );
    }

    /// @notice Launches a funding cycle for a project.
    /// @param _projectId The project ID to launch a funding cycle for.
    /// @param _launchFundingCyclesData Data necessary to launch a funding cycle for the project.
    /// @param _dataSource The data source to be set for the project.
    /// @param _controller The controller to configure the project's funding cycles with.
    /// @return configuration The configuration of the funding cycle that was successfully created.
    function _launchFundingCyclesFor(
        uint256 _projectId,
        LaunchFundingCyclesData memory _launchFundingCyclesData,
        address _dataSource,
        IJBController3_1 _controller
    ) internal returns (uint256) {
        return _controller.launchFundingCyclesFor(
            _projectId,
            _launchFundingCyclesData.data,
            JBFundingCycleMetadata({
                global: _launchFundingCyclesData.metadata.global,
                reservedRate: _launchFundingCyclesData.metadata.reservedRate,
                redemptionRate: _launchFundingCyclesData.metadata.redemptionRate,
                ballotRedemptionRate: _launchFundingCyclesData.metadata.ballotRedemptionRate,
                pausePay: _launchFundingCyclesData.metadata.pausePay,
                pauseDistributions: _launchFundingCyclesData.metadata.pauseDistributions,
                pauseRedeem: _launchFundingCyclesData.metadata.pauseRedeem,
                pauseBurn: _launchFundingCyclesData.metadata.pauseBurn,
                allowMinting: _launchFundingCyclesData.metadata.allowMinting,
                allowTerminalMigration: _launchFundingCyclesData.metadata.allowTerminalMigration,
                allowControllerMigration: _launchFundingCyclesData.metadata.allowControllerMigration,
                holdFees: _launchFundingCyclesData.metadata.holdFees,
                preferClaimedTokenOverride: _launchFundingCyclesData.metadata.preferClaimedTokenOverride,
                useTotalOverflowForRedemptions: _launchFundingCyclesData.metadata.useTotalOverflowForRedemptions,
                useDataSourceForPay: _launchFundingCyclesData.metadata.useDataSourceForPay,
                useDataSourceForRedeem: _launchFundingCyclesData.metadata.useDataSourceForRedeem,
                // Set the delegate address as the data source of the provided metadata.
                dataSource: _dataSource,
                metadata: _launchFundingCyclesData.metadata.metadata
            }),
            _launchFundingCyclesData.mustStartAtOrAfter,
            _launchFundingCyclesData.groupedSplits,
            _launchFundingCyclesData.fundAccessConstraints,
            _launchFundingCyclesData.terminals,
            _launchFundingCyclesData.memo
        );
    }

    /// @notice Reconfigure funding cycles for a project.
    /// @param _projectId The ID of the project for which the funding cycles are being reconfigured.
    /// @param _reconfigureFundingCyclesData Data necessary to reconfigure the project's funding cycles.
    /// @param _dataSource The data source to be set for the project.
    /// @param _controller The controller to be used for configuring the project's funding cycles.
    /// @return The configuration of the successfully reconfigured funding cycle.
    function _reconfigureFundingCyclesOf(
        uint256 _projectId,
        ReconfigureFundingCyclesData memory _reconfigureFundingCyclesData,
        address _dataSource,
        IJBController3_1 _controller
    ) internal returns (uint256) {
        return _controller.reconfigureFundingCyclesOf(
            _projectId,
            _reconfigureFundingCyclesData.data,
            JBFundingCycleMetadata({
                global: _reconfigureFundingCyclesData.metadata.global,
                reservedRate: _reconfigureFundingCyclesData.metadata.reservedRate,
                redemptionRate: _reconfigureFundingCyclesData.metadata.redemptionRate,
                ballotRedemptionRate: _reconfigureFundingCyclesData.metadata.ballotRedemptionRate,
                pausePay: _reconfigureFundingCyclesData.metadata.pausePay,
                pauseDistributions: _reconfigureFundingCyclesData.metadata.pauseDistributions,
                pauseRedeem: _reconfigureFundingCyclesData.metadata.pauseRedeem,
                pauseBurn: _reconfigureFundingCyclesData.metadata.pauseBurn,
                allowMinting: _reconfigureFundingCyclesData.metadata.allowMinting,
                allowTerminalMigration: _reconfigureFundingCyclesData.metadata.allowTerminalMigration,
                allowControllerMigration: _reconfigureFundingCyclesData.metadata.allowControllerMigration,
                holdFees: _reconfigureFundingCyclesData.metadata.holdFees,
                preferClaimedTokenOverride: _reconfigureFundingCyclesData.metadata.preferClaimedTokenOverride,
                useTotalOverflowForRedemptions: _reconfigureFundingCyclesData.metadata.useTotalOverflowForRedemptions,
                useDataSourceForPay: _reconfigureFundingCyclesData.metadata.useDataSourceForPay,
                useDataSourceForRedeem: _reconfigureFundingCyclesData.metadata.useDataSourceForRedeem,
                // Set the delegate address as the data source of the provided metadata.
                dataSource: address(_dataSource),
                metadata: _reconfigureFundingCyclesData.metadata.metadata
            }),
            _reconfigureFundingCyclesData.mustStartAtOrAfter,
            _reconfigureFundingCyclesData.groupedSplits,
            _reconfigureFundingCyclesData.fundAccessConstraints,
            _reconfigureFundingCyclesData.memo
        );
    }
}
