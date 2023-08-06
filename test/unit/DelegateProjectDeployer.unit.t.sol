// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DelegateProjectDeployer} from "../../src/DelegateProjectDeployer.sol";
import {DominantJuice} from "../../src/DominantJuice.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBProjects} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {LaunchProjectData} from "../../src/structs/LaunchProjectData.sol";
//import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";
//import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
//import {LaunchFundingCyclesData} from "./structs/LaunchFundingCyclesData.sol";
//import {ReconfigureFundingCyclesData} from "./structs/ReconfigureFundingCyclesData.sol";

contract DelegateDeployerTest_Unit is Test {
    using stdStorage for StdStorage;

    // The target instance and contract
    DelegateProjectDeployer public delegateProjectDeployer;
    address public deployerAddress;

    // Test helper contract for internal/private functions and variables if needed
    // TestDelegateDeployer testDelegateDeployer;

    // Juicebox addresses and interfaces
    IJBOperatorStore operatorStore = IJBOperatorStore(makeAddr("operatoreStore"));
    address paymentTerminalStoreAddr = makeAddr("paymentTerminalStore");
    IJBController3_1 controller = IJBController3_1(makeAddr("controller")); // Controller that configures & tracks funding cycles
    IJBProjects projects = IJBProjects(makeAddr("projects"));
    IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore =
        IJBSingleTokenPaymentTerminalStore3_1_1(makeAddr("paymentTerminalStore")); // Stores all payment terminals
    JBETHPaymentTerminal3_1_1 paymentTerminal = JBETHPaymentTerminal3_1_1(makeAddr("paymentTerminal")); // Default ETH payment terminal

    // launchProjetFor() parameters / data structs
    IJBPaymentTerminal[] _terminals; // default empty
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    JBProjectMetadata _projectMetadata;
    JBFundingCycleMetadata _launchProjectData;
    JBFundingCycleData _cycleData;

    // Dominant Assurance variables and constants
    DominantJuice public delegate;
    address public delegateAddr;
    address payable delegateOwner = payable(makeAddr("delegateOwner"));
    address payable projectOwner = payable(makeAddr("projectOwner"));
    uint256 public projectID;
    uint256 public constant TOTAL_REFUND_BONUS = 10000 gwei; // 0.00001 ether, 1e13 wei
    uint256 public constant CYCLE_TARGET = 100000 gwei; // 0.0001 ether, 1e14 wei
    uint256 public constant CYCLE_DURATION = 30 minutes;
    uint256 public constant MIN_PLEDGE_AMOUNT = 1000 gwei; // 0.000001 ether, 1e12 wei
    mapping(uint256 => address) public delegateOfProject;

    // For reconfigureFundingCyclesOf() tests to help avoid stack too deep errors
    uint256 reconfigureID = 8;
    uint256 configurationNumber = 6;
    address storedDelegate;

    event DelegateDeployed(uint256 projectId, address delegate, address owner);
    event OwnershipTransferred(address, address);

    function setUp() external {
        vm.etch(address(controller), "The snozzberries taste like snozzberries");
        vm.etch(address(projects), "The snozzberries taste like snozzberries");
        vm.etch(address(operatorStore), "The snozzberries taste like snozzberries");
        vm.etch(address(paymentTerminalStore), "The snozzberries taste like snozzberries");
        vm.etch(address(paymentTerminal), "The snozzberries taste like snozzberries");

        vm.deal(projectOwner, 10 ether);

        // Instantiate delegateProjectDeployer and pre-computed delegate address
        delegateProjectDeployer =
        new DelegateProjectDeployer(address(controller), address(operatorStore), address(paymentTerminalStore), address(paymentTerminal));
        deployerAddress = address(delegateProjectDeployer);
        // This util gets the next deterministic contract address that will be deployed for the given deployer address and deployer nonce.
        delegateAddr = computeCreateAddress(deployerAddress, 1);
        vm.etch(address(delegateAddr), "The snozzberries taste like snozzberries");
        delegate = DominantJuice(delegateAddr);

        // Readying launchProjectFor() data structs
        _projectMetadata = JBProjectMetadata({content: "QmZpzHK5tuNwVkm2EyJp2tVraD6xSJqdF2TE39hzinr9Bs", domain: 0});

        _cycleData = JBFundingCycleData({
            duration: CYCLE_DURATION,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _launchProjectData = JBFundingCycleMetadata({
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
            dataSource: delegateAddr,
            metadata: 0
        });

        _terminals.push(paymentTerminal);

        // For reconfigureCyclesOf() tests
        storedDelegate = makeAddr("storedDelegate");
        stdstore.target(address(delegateProjectDeployer)).sig("delegateOfProject(uint256)").with_key(reconfigureID)
            .checked_write(storedDelegate);
        stdstore.target(deployerAddress).sig("projectOwner(uint256)").with_key(reconfigureID).checked_write(
            projectOwner
        );
    }

    //////////////////////////
    // launchProjectFor Tests
    //////////////////////////

    // PASSING
    function test_launchProjectFor_revertsWhenZeroAddress() public {
        vm.expectRevert("Invalid address");
        delegateProjectDeployer.launchProjectFor(
            address(0), "", CYCLE_TARGET, block.timestamp, CYCLE_DURATION, MIN_PLEDGE_AMOUNT
        );
    }

    // Not passing. See below 2 tests.
    function test_launchProjectFor_happyPath() public {
        // Gets projectID
        uint256 currentCount = 100;
        vm.mockCall(address(controller), abi.encodeCall(controller.projects, ()), abi.encode(projects));
        vm.expectCall(address(controller), abi.encodeCall(controller.projects, ()));
        vm.mockCall(address(projects), abi.encodeCall(projects.count, ()), abi.encode(currentCount));
        vm.expectCall(address(projects), abi.encodeCall(projects.count, ()));
        projectID = currentCount + 1;

        //delegate = new DominantJuice();

        // call delegate to transfer ownership
        //vm.mockCall(delegateAddr, abi.encodeCall(delegate.transferOwnership, (projectOwner)), "");
        //vm.expectCall(delegateAddr, abi.encodeCall(delegate.transferOwnership, (projectOwner)));

        vm.mockCall(
            address(controller),
            abi.encodeCall(
                controller.launchProjectFor,
                (
                    projectOwner,
                    _projectMetadata,
                    _cycleData,
                    _launchProjectData,
                    block.timestamp,
                    _groupedSplits,
                    _fundAccessConstraints,
                    _terminals,
                    ""
                )
            ),
            abi.encode(projectID)
        );
        vm.expectCall(
            address(controller),
            abi.encodeCall(
                controller.launchProjectFor,
                (
                    projectOwner,
                    _projectMetadata,
                    _cycleData,
                    _launchProjectData,
                    block.timestamp,
                    _groupedSplits,
                    _fundAccessConstraints,
                    _terminals,
                    ""
                )
            )
        );

        // initializes delegate
        vm.mockCall(
            delegateAddr,
            abi.encodeCall(
                delegate.initialize, (projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore)
            ),
            abi.encode()
        );
        vm.expectCall(
            delegateAddr,
            abi.encodeCall(
                delegate.initialize, (projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore)
            )
        );

        vm.expectEmit(true, true, true, true, delegateAddr);
        emit DelegateDeployed(projectID, delegateAddr, projectOwner);

        vm.prank(projectOwner);
        uint256 _projectID = delegateProjectDeployer.launchProjectFor(
            projectOwner, "", CYCLE_TARGET, block.timestamp, CYCLE_DURATION, MIN_PLEDGE_AMOUNT
        );

        // Asserts
        assertEq(delegateAddr, delegateProjectDeployer.delegateOfProject(projectID));
        assertEq(projectOwner, delegateProjectDeployer.projectOwner(projectID));
        assertEq(projectID, _projectID);
    }

    //////////////////////////
    // deployDelegateFor Tests
    //////////////////////////

    // Traces show new delegate is only 40 bytes of code and calls it "Unknown"
    function test_deployDelegateFor_happyPath() public {
        uint256 _projectID = 4;

        // Mock call to delegate address to transfer ownership
        vm.mockCall(delegateAddr, abi.encodeCall(delegate.transferOwnership, (projectOwner)), "");
        vm.expectCall(delegateAddr, abi.encodeCall(delegate.transferOwnership, (projectOwner)));

        vm.expectEmit(true, true, true, true, address(delegateAddr));
        emit OwnershipTransferred(address(0), deployerAddress);

        vm.expectEmit(true, true, true, true, address(delegateAddr));
        emit OwnershipTransferred(deployerAddress, projectOwner);

        vm.expectEmit(true, true, true, true, deployerAddress);
        emit DelegateDeployed(_projectID, delegateAddr, projectOwner);

        vm.prank(projectOwner);
        DominantJuice _delegate = delegateProjectDeployer.deployDelegateFor(projectOwner, _projectID);
        assertEq(address(_delegate), delegateAddr);
        assertEq(address(_delegate), delegateProjectDeployer.delegateOfProject(_projectID));
        assertEq(projectOwner, _delegate.owner());
        //console.log(address(_delegate), delegateAddr);
    }

    // Traces show new delegate is 10,000+ bytes of code and calls it "DominantJuice"
    function test_onlyDelegateDeployment() public {
        vm.prank(projectOwner);
        DominantJuice _delegateInstance = new DominantJuice();
        _delegateInstance;
    }

    // PASSING
    function test_deployDelegateFor_revertsIfOwnerIsZeroAddress() public {
        vm.expectRevert("Invalid address");
        delegateProjectDeployer.deployDelegateFor(address(0), 4);
    }

    ///////////////////////////////////
    // reconfigureFundingCyclesOf Tests
    ///////////////////////////////////

    // PASSING
    function testFuzz_reconfigureFundingCyclesOf_revertsWhenNotOwner(address _notOwner) public {
        vm.assume(_notOwner != projectOwner);
        uint256 projId = 4;
        stdstore.target(deployerAddress).sig("projectOwner(uint256)").with_key(projId).checked_write(projectOwner);
        vm.expectRevert("Caller is not project owner.");
        vm.prank(_notOwner);
        delegateProjectDeployer.reconfigureFundingCyclesOf(projId, 1);
    }

    // PASSING
    function testFuzz_reconfigureFundingCyclesOf_revertsResultGt2(uint8 _result) public {
        vm.assume(_result > 2);
        uint256 projId = 4;
        stdstore.target(deployerAddress).sig("projectOwner(uint256)").with_key(projId).checked_write(projectOwner);
        vm.expectRevert("Input must be 0 (freeze), 1 (success), or 2 (fail)");
        vm.prank(projectOwner);
        delegateProjectDeployer.reconfigureFundingCyclesOf(projId, _result);
    }

    // Not passing. happy path, returns configuration number
    function test_reconfigureFundingCyclesOf_tooCloseToCallHappyPath() public {
        //_result = bound(_result, 0, 2);
        //uint8 result = uint8(_result);

        // Input parameter is 0 for "too close to call" scenario.
        JBFundingCycleMetadata memory _fcMetadata = fundingCycleMetadataHelper(0);

        // Mock that projectOwner has already given reconfiguration permissions to the deployer.
        vm.mockCall(
            address(operatorStore),
            abi.encodeCall(operatorStore.hasPermission, (deployerAddress, projectOwner, 0, 1)),
            abi.encode(true)
        );

        vm.mockCall(
            address(controller),
            abi.encodeCall(
                controller.reconfigureFundingCyclesOf,
                (reconfigureID, _cycleData, _fcMetadata, block.timestamp, _groupedSplits, _fundAccessConstraints, "")
            ),
            abi.encode(configurationNumber)
        );
        vm.expectCall(
            address(controller),
            abi.encodeCall(
                controller.reconfigureFundingCyclesOf,
                (reconfigureID, _cycleData, _fcMetadata, block.timestamp, _groupedSplits, _fundAccessConstraints, "")
            )
        );

        vm.prank(projectOwner);
        uint256 _configurationNumber = delegateProjectDeployer.reconfigureFundingCyclesOf(reconfigureID, 0);
        assertEq(configurationNumber, _configurationNumber);
    }

    // Not a test
    function fundingCycleMetadataHelper(uint8 _result) public view returns (JBFundingCycleMetadata memory) {
        uint256 _cycleDuration;
        bool _pauseTransfers;
        uint256 _redemptionRate;
        bool _pauseDistributions;
        bool _pauseRedeem;
        bool _pauseBurn;
        bool _useDataSourceForRedeem;

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

        JBFundingCycleMetadata memory _jbFCMetadata = JBFundingCycleMetadata({
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
            dataSource: storedDelegate,
            metadata: 0
        });
        return _jbFCMetadata;
    }

    /////////////////////////////
    // Getter and Edge Case Tests
    /////////////////////////////

    // PASSING
    function test_getDelegateOfProject(uint256 _projectID) public {
        assertEq(storedDelegate, delegateProjectDeployer.getDelegateOfProject(_projectID));
    }
}

// contract TestDelegateDeployer is DelegateProjectDeployer, Test {
// }
