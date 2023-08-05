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

    // Test helper contract for internal/private functions and variables
    // TestDelegateDeployer testDelegateDeployer;

    // Juicebox addresses and interfaces
    address operatorStoreAddr = makeAddr("operatoreStore");
    address paymentTerminalStoreAddr = makeAddr("paymentTerminalStore");
    IJBController3_1 controller = IJBController3_1(makeAddr("controller")); // Controller that configures funding cycles
    IJBProjects projects = IJBProjects(makeAddr("projects"));
    IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore =
        IJBSingleTokenPaymentTerminalStore3_1_1(makeAddr("paymentTerminalStore")); // Stores all payment terminals
    JBETHPaymentTerminal3_1_1 paymentTerminal = JBETHPaymentTerminal3_1_1(makeAddr("paymentTerminal")); // Default ETH payment terminal

    // Project Launch parameters / data structs
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

    event DelegateDeployed(uint256 projectId, address delegate, address owner);
    event OwnershipTransferred(address, address);

    function setUp() external {
        vm.etch(address(controller), "The snozzberries taste like snozzberries");
        vm.etch(address(projects), "The snozzberries taste like snozzberries");
        vm.etch(operatorStoreAddr, "The snozzberries taste like snozzberries");
        vm.etch(address(paymentTerminalStore), "The snozzberries taste like snozzberries");
        vm.etch(address(paymentTerminal), "The snozzberries taste like snozzberries");

        // Instantiate delegateProjectDeployer and pre-computed delegate address
        delegateProjectDeployer =
        new DelegateProjectDeployer(address(controller), operatorStoreAddr, address(paymentTerminalStore), address(paymentTerminal));
        deployerAddress = address(delegateProjectDeployer);
        // This util gets the next deterministic contract address that will be deployed for the given deployer address and deployer nonce.
        delegateAddr = computeCreateAddress(deployerAddress, 1);
        vm.etch(address(delegateAddr), "The snozzberries taste like snozzberries");
        delegate = DominantJuice(delegateAddr);

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
    }

    //////////////////////////
    // launchProjectFor Tests
    //////////////////////////

    function test_launchProjectFor_happyPath() public {
        // gets projectID
        //address projects = makeAddr("projects");
        uint256 currentCount = 100;
        vm.mockCall(address(controller), abi.encodeCall(controller.projects, ()), abi.encode(projects));
        vm.expectCall(address(controller), abi.encodeCall(controller.projects, ()));
        vm.mockCall(address(projects), abi.encodeCall(projects.count, ()), abi.encode(currentCount));
        vm.expectCall(address(projects), abi.encodeCall(projects.count, ()));
        //projectID = currentCount + 1;

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
        emit DelegateDeployed(currentCount + 1, delegateAddr, projectOwner);

        delegateProjectDeployer.launchProjectFor(
            projectOwner, "", CYCLE_TARGET, block.timestamp, CYCLE_DURATION, MIN_PLEDGE_AMOUNT
        );

        // Asserts
        // assertEq(delegateAddr, delegateProjectDeployer.delegateOfProject(projectID));
        // assertEq(projectOwner, delegateProjectDeployer.projectOwner(projectID));

        // returns projectID
    }

    function test_launchProjectFor_MOCK() public {
        // gets projectID
        //address projects = makeAddr("projects");
        vm.mockCall(address(controller), abi.encodeCall(controller.projects, ()), abi.encode(projects));
        vm.expectCall(address(controller), abi.encodeCall(controller.projects, ()));
        vm.mockCall(address(projects), abi.encodeCall(projects.count, ()), abi.encode(100));
        vm.expectCall(address(projects), abi.encodeCall(projects.count, ()));
        projectID = 100 + 1;

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
        // vm.mockCall(
        //     delegateAddr,
        //     abi.encodeCall(
        //         dac.initialize, (projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore)
        //     ),
        //     abi.encode(100)
        // );
        // vm.expectCall(
        //     delegateAddr,
        //     abi.encodeCall(
        //         dac.initialize, (projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore)
        //     )
        // );

        // vm.expectEmit(true, true, true, true, address(delegateAddr));
        // emit DelegateDeployed(projectID, projectOwner);

        projectID = delegateProjectDeployer.launchProjectFor(
            msg.sender, "", CYCLE_TARGET, block.timestamp, CYCLE_DURATION, MIN_PLEDGE_AMOUNT
        );

        //address delegateAddr = delegateProjectDeployer.delegateOfProject(projectID);
        //DominantJuice dac = DominantJuice(delegateAddr);

        //vm.mockCall(delegateAddr, abi.encodeCall(dac.transferOwnership, (delegateOwner)), "");
        //vm.expectCall(delegateAddr, abi.encodeCall(dac.transferOwnership, (delegateOwner)));

        // Asserts
        assertEq(delegateAddr, delegateProjectDeployer.delegateOfProject(projectID));
        assertEq(projectOwner, delegateProjectDeployer.projectOwner(projectID));

        // returns projectID
    }

    function test_MOCK() public {
        projectID = delegateProjectDeployer.launchProjectFor(
            msg.sender, "", CYCLE_TARGET, block.timestamp, CYCLE_DURATION, MIN_PLEDGE_AMOUNT
        );
    }

    //////////////////////////
    // deployDelegateFor Tests
    //////////////////////////

    function test_deployDelegateFor_happyPath() public {
        // vm.assume(_owner != address(0));
        // vm.assume(_projectID != 0);
        uint256 _projectID = 4;
        //address _delegateAddr = computeCreateAddress(deployerAddress, 2); // deployed once in setup(), so nonce = 2.
        //vm.etch(_delegateAddr, "The snozzberries taste like snozzberries");
        DominantJuice _delegateInstance = new DominantJuice();

        // mockCall to delegate address to transfer ownership
        vm.mockCall(delegateAddr, abi.encodeCall(_delegateInstance.transferOwnership, (projectOwner)), "");
        vm.expectCall(delegateAddr, abi.encodeCall(_delegateInstance.transferOwnership, (projectOwner)));

        vm.expectEmit(true, true, true, true, address(delegateAddr));
        emit OwnershipTransferred(address(0), deployerAddress);

        vm.expectEmit(true, true, true, true, address(delegateAddr));
        emit OwnershipTransferred(deployerAddress, projectOwner);

        vm.expectEmit(true, true, true, true, deployerAddress);
        emit DelegateDeployed(_projectID, delegateAddr, projectOwner);

        DominantJuice _delegate = delegateProjectDeployer.deployDelegateFor(projectOwner, _projectID);
        //delegateProjectDeployer.deployDelegateFor(projectOwner, _projectID);
        assertEq(address(_delegate), delegateAddr);
        assertEq(address(_delegate), delegateProjectDeployer.delegateOfProject(_projectID));
        //assertEq(_owner, _delegate.owner());
        //console.log(address(_delegate), delegateAddr);
    }

    // PASSING
    function test_deployDelegateFor_revertsIfOwnerIsZeroAddress() public {
        vm.expectRevert("Invalid address");
        delegateProjectDeployer.deployDelegateFor(address(0), 4);
    }

    //////////////////////////
    // reconfigureFundingCyclesOf Tests
    //////////////////////////

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

    // Happy Path, returns configuration number
    function test_reconfigureFundingCyclesOf_happyPaths(uint256 _result) public {
        _result = bound(_result, 0, 2);
        uint8 result = uint8(_result);
        uint256 projId = 4;
        stdstore.target(deployerAddress).sig("projectOwner(uint256)").with_key(projId).checked_write(projectOwner);

        //vm.mockCall(address(controller), abi.encodeCall(controller.reconfigureFundingCyclesOf, ()), abi.encode(---));
        //vm.expectCall(address(controller), abi.encodeCall(controller.reconfigureFundingCyclesOf, ()));

        vm.startPrank(projectOwner);
        if (result == 0) {
            delegateProjectDeployer.reconfigureFundingCyclesOf(projId, result);
            //assertEq()
        }

        vm.stopPrank();
    }

    // need to save delegate address and make it programmable in this function

    //////////////////////////
    // Edge Case Tests
    //////////////////////////

    //////////////////////////
    // Getter and Misc. Tests
    //////////////////////////

    // PASSING
    function test_getDelegateOfProject(uint256 _projectID) public {
        address storedDelegate = makeAddr("storedDelegate");
        stdstore.target(address(delegateProjectDeployer)).sig("delegateOfProject(uint256)").with_key(_projectID)
            .checked_write(storedDelegate);
        assertEq(storedDelegate, delegateProjectDeployer.getDelegateOfProject(_projectID));
    }
}

// contract TestDelegateDeployer is DelegateProjectDeployer, Test {
//     function projectOwner(uint256 _ID) external returns (address) {
//         return DelegateProjectDeployer.projectOwner(_ID);
//     }
// }

// calls deployDelegateFor and deploys delegate
// DominantJuice _delegate = new DominantJuice();
//address delegateAddr = makeAddr(_delegate);
// address delegateAddr = makeAddr("delegateAddr");
// DominantJuice dac = DominantJuice(delegateAddr);

// console.log(address(this));
