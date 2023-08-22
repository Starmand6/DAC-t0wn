// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
// import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
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
//import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
//import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
//import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
//import {LaunchProjectData} from "./structs/LaunchProjectData.sol";

contract LaunchAndDeploy is Script {
    // Juicebox contracts
    struct Contracts {
        IJBController3_1 controller; // Controller that configures funding cycles
        IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore; // Stores all payment terminals
        JBETHPaymentTerminal3_1_1 ethPaymentTerminal; // Default ETH payment terminal
    }

    Contracts contracts;

    // JB Project Launch struct array parameters
    IJBPaymentTerminal[] _terminals; // default empty
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty

    // Campaign parameters
    address payable owner = payable(msg.sender);
    uint256 cycleTarget = 1200 ether;
    uint256 startTime = block.timestamp + 172800; // 48 hours from script execution
    uint256 duration = 1209600; // Two weeks of seconds
    uint256 minimumPledgeAmount = 50 ether;

    event DelegateDeployed(uint256 _projectID, address _delegate, address _owner);

    function run() external returns (uint256 projectID) {
        // Store the deployed JB contracts depending on which network (Mainnet or Goerli) is called for
        HelperConfig helperConfig = new HelperConfig();
        (address _controller, address _paymentTerminalStore3_1_1, address _ethPaymentTerminal3_1_1) =
            helperConfig.activeNetworkConfig();
        contracts.controller = IJBController3_1(_controller);
        contracts.paymentTerminalStore = IJBSingleTokenPaymentTerminalStore3_1_1(_paymentTerminalStore3_1_1);
        contracts.ethPaymentTerminal = JBETHPaymentTerminal3_1_1(_ethPaymentTerminal3_1_1);

        _terminals.push(contracts.ethPaymentTerminal);

        string memory ipfsCID = "QmZpzHK5tuNwVkm2EyJp2tVraD6xSJqdF2TE39hzinr9Bs"; // Project's metadata file hash and codec from IPFS (placeholder)

        vm.startBroadcast();
        // Launch the JB project and deploy the DAC delegate.
        projectID = launchProjectFor(owner, ipfsCID, cycleTarget, startTime, duration, minimumPledgeAmount);
        vm.stopBroadcast();
    }

    /// @notice Launches a new project with the DAC delegate (DominantJuice.sol) attached.
    /// @param _owner The address to set as the owner of the project. The project's ERC-721 will be owned by this address.
    /// @param _ipfsCID The CID obtained from IPFS for uploading project's metadata (name, logo, description, etc).
    /// @param _cycleTarget Funding target for the dominant assurance campaign.
    /// @param _startTime The timestamp that the campaign cycle is desired to start.
    /// @param _duration The duration of the campaign cycle in seconds.
    /// @param _minimumPledgeAmount Minimum amount that payers can pledge.
    /// @return _projectID The ID of the newly configured project.
    function launchProjectFor(
        address payable _owner,
        string memory _ipfsCID,
        uint256 _cycleTarget,
        uint256 _startTime,
        uint256 _duration,
        uint256 _minimumPledgeAmount
    ) public returns (uint256 _projectID) {
        require(_owner != address(0), "Invalid address");

        // Get the project ID, optimistically knowing it will be one greater than the current count.
        IJBProjects projects = contracts.controller.projects();
        _projectID = projects.count() + 1;

        /// Deploy the dominant assurance escrow delegate w/ the calculated project ID and store the instance.
        DominantJuice delegate =
        new DominantJuice(_owner, _projectID, _cycleTarget, _minimumPledgeAmount, contracts.controller, contracts.paymentTerminalStore);

        emit DelegateDeployed(_projectID, address(delegate), _owner);

        // ***Set project Launch variables***

        JBProjectMetadata memory _projectMetadata = JBProjectMetadata({content: _ipfsCID, domain: 0});

        JBFundingCycleData memory _cycleData = JBFundingCycleData({
            duration: _duration,
            weight: 1000000 * 10 ** 18, // This is the amount of JB tokens that get issued to pledgers per ether. Can be changed on JB site.
            discountRate: 0, // Not relevant for t0wn's initial campaign.
            ballot: IJBFundingCycleBallot(address(0))
        });

        // This exact configuration will allow for pledger payments, no token redemptions/transfers/burns, and will
        // use the deployed DAC as the Data Source for the first cycle of the project.
        JBFundingCycleMetadata memory _cycleMetadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false, pauseTransfers: true}), // Not relevant for t0wn's initial campaign.
            reservedRate: 0, // Not relevant for t0wn's initial campaign.
            redemptionRate: 0,
            ballotRedemptionRate: 0, // Not relevant for t0wn's initial campaign.
            pausePay: false,
            pauseDistributions: true,
            pauseRedeem: true,
            pauseBurn: true,
            allowMinting: false, // Not relevant for t0wn's initial campaign.
            allowTerminalMigration: false, // Not relevant for t0wn's initial campaign.
            allowControllerMigration: false, // Not relevant for t0wn's initial campaign.
            holdFees: false, // Not relevant for t0wn's initial campaign.
            preferClaimedTokenOverride: false, // Not relevant for t0wn's initial campaign.
            useTotalOverflowForRedemptions: false, // We want all overflow to go towards the campaign funds.
            useDataSourceForPay: true, // We want to use the DAC as the DataSource. This is a very crucial parameter.
            useDataSourceForRedeem: false, // This needs to be false for the initial cycle and will be changed depending on campaign outcome.
            dataSource: address(delegate),
            metadata: 0
        });

        // Call the JB controller to launch the project.
        contracts.controller.launchProjectFor(
            _owner,
            _projectMetadata,
            _cycleData,
            _cycleMetadata,
            _startTime,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );
    }
}
