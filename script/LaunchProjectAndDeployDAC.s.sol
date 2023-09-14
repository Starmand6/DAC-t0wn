// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {JBETHPaymentTerminal3_1_2} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_2.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";

// Script to launch a new JB project and deploy a dominant assurance contract (DAC) using the new project parameters
contract LaunchProjectAndDeployDAC is Script {
    // Juicebox contracts
    struct Contracts {
        IJBController3_1 controller; // Controller that configures funding cycles
        IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore3_1_1; // Stores all payment terminals
        JBETHPaymentTerminal3_1_2 jbETHPaymentTerminal3_1_2; // Default ETH payment terminal
    }

    Contracts contracts;

    // JB Project Launch struct parameters (in storage to avoid stack too deep errors)
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _cycleData;
    JBFundingCycleMetadata _cycleMetadata;
    IJBPaymentTerminal[] _terminals; // default empty
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty

    event DelegateDeployed(uint256 _projectID, address _delegate, address _owner);

    function run(
        address payable _owner,
        uint256 _cycleTarget,
        uint256 _startTime,
        uint256 _duration,
        uint256 _minPledgeAmount,
        string memory _ipfsCID // Project's metadata file hash and codec from IPFS
    ) external returns (uint256 projectID) {
        // Store the deployed JB contracts depending on which network (Mainnet or Goerli) is called for
        HelperConfig helperConfig = new HelperConfig();
        (address _controller, address _paymentTerminalStore3_1_1, address _ethPaymentTerminal3_1_2) =
            helperConfig.activeNetworkConfig();
        contracts.controller = IJBController3_1(_controller);
        contracts.paymentTerminalStore3_1_1 = IJBSingleTokenPaymentTerminalStore3_1_1(_paymentTerminalStore3_1_1);
        contracts.jbETHPaymentTerminal3_1_2 = JBETHPaymentTerminal3_1_2(_ethPaymentTerminal3_1_2);

        _terminals.push(contracts.jbETHPaymentTerminal3_1_2);

        vm.startBroadcast();
        console.log("Launching Juicebox project and deploying DAC / DominantJuice...");
        // Launch the JB project and deploy the DAC delegate.
        projectID = launchProjectFor(_owner, _ipfsCID, _cycleTarget, _startTime, _duration, _minPledgeAmount);
        console.log("Juicebox project launched with ID: ", projectID);
        vm.stopBroadcast();
    }

    /// @notice Launches a new project with the DAC delegate (DominantJuice.sol) attached.
    /// @param _owner The address to set as the owner of the project. The project's ERC-721 will be owned by this address.
    /// @param _ipfsCID The CID obtained from IPFS for uploading project's metadata (name, logo, description, etc).
    /// @param _cycleTarget Funding target for the dominant assurance campaign.
    /// @param _startTime The campaign cycle will start at this timestamp.
    /// @param _duration The duration of the campaign cycle in seconds.
    /// @param _minimumPledgeAmount Minimum amount that pledgers can pledge.
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

        console.log(msg.sender);

        // Need to precalculate the address the DAC/delegate will be deployed at.
        // Add 1 because calling controller increases nonce before the contract creation call.
        address delegateAddress = computeCreateAddress(_owner, vm.getNonce(_owner) + 1);
        console.log("Computed Nonce: ", vm.getNonce(_owner));
        console.log("Precalculated address for the DAC: ", delegateAddress);

        // ***Set project Launch variables***

        _projectMetadata = JBProjectMetadata({content: _ipfsCID, domain: 0});

        _cycleData = JBFundingCycleData({
            duration: _duration,
            weight: 1000000 * 10 ** 18, // This is the amount of JB tokens that get issued to pledgers per ether. Can be changed on JB site.
            discountRate: 0, // Not relevant for t0wn's initial campaign.
            ballot: IJBFundingCycleBallot(address(0))
        });

        // This exact configuration will allow for pledger payments, will pause token redemptions/transfers/burns, and will
        // use the deployed DAC as the Data Source for the first cycle of the project.
        _cycleMetadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false, pauseTransfers: true}),
            reservedRate: 0, // Not relevant for t0wn's initial campaign
            redemptionRate: 0, // No redemptions in first cycle
            ballotRedemptionRate: 0, // Not relevant for t0wn's initial campaign
            pausePay: false, // Allow pledges/payments to project
            pauseDistributions: true, // Pause all token movements
            pauseRedeem: true, // Pause all token movements
            pauseBurn: true, // Pause all token movements
            allowMinting: false, // Not relevant for t0wn's initial campaign
            allowTerminalMigration: false, // Not relevant for t0wn's initial campaign
            allowControllerMigration: false, // Not relevant for t0wn's initial campaign
            holdFees: false, // Not relevant for t0wn's initial campaign
            preferClaimedTokenOverride: false, // Not relevant for t0wn's initial campaign
            useTotalOverflowForRedemptions: false, // All overflow should go towards the campaign funds.
            useDataSourceForPay: true, // Use the DAC as the DataSource. This is a very crucial parameter.
            useDataSourceForRedeem: false, // As a safety fallback, this is false for the initial cycle and will be changed toward end of cycle #1, depending on campaign outcome.
            dataSource: delegateAddress, // Address of DominantJuice.sol - the DAC/delegate/dataSource.
            metadata: 0 // 0 by default
        });

        console.log("Calling the JB controller to launch the project");
        // Call the JB controller to launch the project.
        _projectID = contracts.controller.launchProjectFor(
            _owner, // deployer provided
            _projectMetadata, // deployer provided
            _cycleData, // deployer provided
            _cycleMetadata, // deployer provided
            _startTime, // deployer provided
            _groupedSplits, // empty
            _fundAccessConstraints, // empty
            _terminals, // [0] == _jbETHPaymentTerminal3_1_2
            "" // memo is empty as a default
        );

        console.log("Deploying DAC...");
        /// Deploy the dominant assurance escrow delegate w/ the project ID and store the instance.
        DominantJuice delegate = new DominantJuice(_projectID, _cycleTarget, _minimumPledgeAmount, contracts.controller);

        console.log("Deployed DAC address:", address(delegate));

        emit DelegateDeployed(_projectID, address(delegate), _owner);
        console.log("Event emitted");
    }
}
