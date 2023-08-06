// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {DominantJuice} from "../../src/DominantJuice.sol";
import {DelegateProjectDeployer} from "../../src/DelegateProjectDeployer.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {IJBFundAccessConstraintsStore} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundAccessConstraintsStore.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBSingleTokenPaymentTerminal} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBDidPayData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData3_1_1.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBDidRedeemData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData3_1_1.sol";
import {JBRedemptionDelegateAllocation3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import {JBPayDelegateAllocation3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";

// Imports for launchProjectFor():
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBTokenAmount} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";
import {UD60x18, ud, add, pow, powu, div, mul, wrap, unwrap} from "@prb/math/UD60x18.sol";

contract DominantJuiceTest_Unit is Test {
    using stdStorage for StdStorage;

    // Contracts and Structs for JB functions: launchProjectFor(), pay(), redeemTokensOf()
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _cycleData;
    JBFundingCycle _cycle;
    JBFundingCycleMetadata _metadata;
    JBFundingCycleMetadata _metadataFailedCampaign;
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty
    DominantJuice dominantJuice;
    JBDidPayData3_1_1 didPayData;
    JBPayParamsData payParamsData;
    JBRedeemParamsData redeemParamsData;
    JBDidRedeemData3_1_1 didRedeemData;
    JBPayDelegateAllocation3_1_1[] delegateAllocations;
    JBTokenAmount tokenStruct;
    IJBController3_1 public controller = IJBController3_1(makeAddr("controller"));
    IJBDirectory public directory = IJBDirectory(makeAddr("directory"));
    IJBFundAccessConstraintsStore public fundAccessConstraintsStore =
        IJBFundAccessConstraintsStore(makeAddr("fundAccessConstraintsStore"));
    IJBSingleTokenPaymentTerminalStore3_1_1 public paymentTerminalStore =
        IJBSingleTokenPaymentTerminalStore3_1_1(makeAddr("paymentTerminalStore"));
    IJBSingleTokenPaymentTerminal ethPaymentTerminal = IJBSingleTokenPaymentTerminal(makeAddr("ethPaymentTerminal"));

    // Dominant Assurance variables and constants
    address payable owner = payable(makeAddr("owner"));
    address payable public pledger1 = payable(makeAddr("pledger1"));
    address payable public pledger2 = payable(makeAddr("pledger2"));
    address payable public pledger3 = payable(makeAddr("pledger3"));
    address payable public rando = payable(makeAddr("rando"));
    uint256 public projectID;
    uint256 public constant STARTING_USER_BALANCE = 1 ether; // 1e18 wei
    uint256 public constant TOTAL_REFUND_BONUS = 10000 gwei; // 0.00001 ether, 1e13 wei
    uint256 public constant CYCLE_TARGET = 100000 gwei; // 0.0001 ether, 1e14 wei
    uint256 public constant CYCLE_DURATION = 20 days;
    uint256 public constant MIN_PLEDGE_AMOUNT = 1000 gwei; // 0.000001 ether, 1e12 wei
    uint256 public cycleExpiryDate;
    address public ethToken = 0x000000000000000000000000000000000000EEEe;

    // Events
    event RefundBonusDeposited(address owner, uint256 indexed totalRefundBonus);
    event CycleHasClosed(bool indexed, bool indexed);
    event CycleRefundBonusWithdrawal(address indexed, uint256 indexed);
    event OwnerWithdrawal(address, uint256);

    function setUp() external {
        // Deploy the target contract.
        vm.prank(owner);
        dominantJuice = new DominantJuice();

        vm.deal(owner, STARTING_USER_BALANCE);
        vm.deal(pledger1, STARTING_USER_BALANCE);
        vm.deal(pledger2, STARTING_USER_BALANCE);
        vm.deal(rando, STARTING_USER_BALANCE);

        vm.etch(address(controller), "I'm the operator with my pocket calculator");
        vm.etch(address(directory), "I'm the operator with my pocket calculator");
        vm.etch(address(fundAccessConstraintsStore), "I'm the operator with my pocket calculator");
        vm.etch(address(paymentTerminalStore), "I'm the operator with my pocket calculator");
        vm.etch(address(ethPaymentTerminal), "I'm the operator with my pocket calculator");

        // JB Project Launch variables:
        // _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _cycleData = JBFundingCycleData({
            duration: CYCLE_DURATION,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _cycle = JBFundingCycle({
            number: 1,
            configuration: 2,
            basedOn: 3,
            start: block.timestamp,
            duration: 3 weeks,
            weight: 200,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0)),
            metadata: 5
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

        _terminals.push(ethPaymentTerminal);

        projectID = 5;
    }

    //////////////////////////////////
    // supportsInterface() Test
    //////////////////////////////////

    // PASSING
    function test_supportsInterface_happyPathForAllThree() public {
        bytes4 dataSourceID = 0x71700c69;
        bool dataSourceBool = dominantJuice.supportsInterface(dataSourceID);
        assertTrue(dataSourceBool);
        bytes4 payDelegate3_1_1_ID = 0x6b204943;
        bool payDelegateBool = dominantJuice.supportsInterface(payDelegate3_1_1_ID);
        assertTrue(payDelegateBool);
        bytes4 redemptionDelegate3_1_1_ID = 0x0bf46e59;
        bool redemptionDelegateBool = dominantJuice.supportsInterface(redemptionDelegate3_1_1_ID);
        assertTrue(redemptionDelegateBool);
    }

    //////////////////////////////////
    // initialize() Tests
    //////////////////////////////////

    // PASSING
    function test_initialize_storesAllVariablesAndContracts() public {
        vm.mockCall(address(controller), abi.encodeCall(controller.directory, ()), abi.encode(directory));
        vm.expectCall(address(controller), abi.encodeCall(controller.directory, ()));
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.fundAccessConstraintsStore, ()),
            abi.encode(fundAccessConstraintsStore)
        );
        vm.expectCall(address(controller), abi.encodeCall(controller.fundAccessConstraintsStore, ()));
        vm.mockCall(address(directory), abi.encodeCall(directory.terminalsOf, (projectID)), abi.encode(_terminals));
        vm.expectCall(address(directory), abi.encodeCall(directory.terminalsOf, (projectID)));
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(_cycle, _metadata)
        );
        vm.expectCall(address(controller), abi.encodeCall(controller.currentFundingCycleOf, (projectID)));

        dominantJuice.initialize(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);
        assertEq(CYCLE_TARGET, dominantJuice.cycleTarget());
        assertEq(MIN_PLEDGE_AMOUNT, dominantJuice.minimumPledgeAmount());
        assertEq(projectID, dominantJuice.projectId());
        assertEq(address(controller), address(dominantJuice.controller()));
        assertEq(address(directory), address(dominantJuice.directory()));
        assertEq(address(fundAccessConstraintsStore), address(dominantJuice.fundAccessConstraintsStore()));
        assertEq(address(ethPaymentTerminal), address(dominantJuice.paymentTerminal()));
        uint256 endDate = _cycle.start + _cycle.duration;
        assertEq(endDate, dominantJuice.cycleExpiryDate());
    }

    // PASSING. Does not let anyone call function twice
    function test_initialize_revertsWhenCalledTwice(uint256 _projectID) public {
        vm.assume(_projectID != 0);
        stdstore.target(address(dominantJuice)).sig("projectId()").checked_write(_projectID);
        //dominantJuice.initialize(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);
        vm.expectRevert(DominantJuice.ContractAlreadyInitialized.selector);
        dominantJuice.initialize(8, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);
    }

    ///////////////////////////////////
    // depositRefundBonus() Tests //
    //////////////////////////////////

    modifier initialized() {
        uint256 expiryDate = block.timestamp + 3 weeks;
        stdstore.target(address(dominantJuice)).sig("cycleExpiryDate()").checked_write(expiryDate);

        vm.mockCall(address(controller), abi.encodeCall(controller.directory, ()), abi.encode(directory));
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.fundAccessConstraintsStore, ()),
            abi.encode(fundAccessConstraintsStore)
        );
        vm.mockCall(address(directory), abi.encodeCall(directory.terminalsOf, (projectID)), abi.encode(_terminals));
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(_cycle, _metadata)
        );

        dominantJuice.initialize(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);
        vm.clearMockedCalls();
        _;
    }

    // PASSING
    function test_deposit_revertsBeforeInitialization() public {
        vm.prank(owner);
        vm.expectRevert(DominantJuice.DataSourceNotInitialized.selector);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    }

    // PASSING
    function testFuzz_deposit_revertsOnDepositAndInputMismatch(uint256 input) public initialized {
        vm.assume(input != TOTAL_REFUND_BONUS);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.FundsMustMatchInputAmount.selector, input));
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(input);
    }

    // PASSING
    function test_deposit_revertsWithNonOwner() public initialized {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(rando);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    }

    // PASSING
    function test_deposit_allowsOwnerDepositAndEmitsEvent() public initialized {
        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit RefundBonusDeposited(owner, TOTAL_REFUND_BONUS);
        vm.prank(owner);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
        uint256 balance = dominantJuice.getBalance();
        assertEq(balance, TOTAL_REFUND_BONUS);
    }

    ///////////////////////////////////
    // payParams() Tests //
    //////////////////////////////////

    // PASSING
    function test_payParams_revertsBeforeInit() public {
        vm.expectRevert(DominantJuice.DataSourceNotInitialized.selector);
        dominantJuice.payParams(payParamsData);
    }

    modifier bonusDeposited() {
        vm.prank(owner);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
        _;
    }

    // PASSING
    function testFuzz_payParams_revertsWhenPaymentIsBelowMinPledge(uint256 value) public initialized bonusDeposited {
        vm.assume(value < MIN_PLEDGE_AMOUNT);
        payParamsData.amount.value = value;
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.AmountIsBelowMinimumPledge.selector, MIN_PLEDGE_AMOUNT));
        dominantJuice.payParams(payParamsData);
    }

    // PASSING (unimplemented feature error)
    function test_payParams_returnsMemoryVariables() public initialized bonusDeposited {
        payParamsData.payer = pledger1;
        payParamsData.weight = 1;
        payParamsData.memo = "juice";
        payParamsData.amount = JBTokenAmount(ethToken, MIN_PLEDGE_AMOUNT, 18, 1);

        // Error: Unimplemented feature (/solidity/libsolidity/codegen/ArrayUtils.cpp:228):
        // Copying of type struct JBPayDelegateAllocation3_1_1 memory[] memory to storage not yet supported.
        // delegateAllocations = new JBPayDelegateAllocation3_1_1[](1);
        // delegateAllocations[0] = JBPayDelegateAllocation3_1_1(dominantJuice, 0, "");

        (uint256 _weight, string memory _memo,) = dominantJuice.payParams(payParamsData);
        assertEq(payParamsData.weight, _weight);
        assertEq(payParamsData.memo, _memo);
        //assertEq(0, delegateAllocations[0].amount);
    }

    // payParams() function is non-payable, the parent function that calls it is nonReentrant, and
    // there is mostly only logic to satisfy Juicebox architecture, thus not many unit tests here.
    // The only way to access this function correctly is through the JB architecture.

    ///////////////////////////////////
    // didPay() Tests //
    //////////////////////////////////

    // PASSING
    function test_didPay_revertsIfPaymentSent() public initialized {
        vm.expectRevert(
            abi.encodeWithSelector(
                DominantJuice.InvalidPaymentEvent.selector, rando, didPayData.projectId, MIN_PLEDGE_AMOUNT
            )
        );
        vm.prank(rando);
        dominantJuice.didPay{value: MIN_PLEDGE_AMOUNT}(didPayData);
    }

    // PASSING
    function test_didPay_revertsIfNotPaymentTerminal() public initialized {
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(rando))),
            abi.encode(false)
        );
        vm.expectCall(
            address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(rando)))
        );
        vm.prank(rando); // non-paymentTerminal calling
        vm.expectRevert(
            abi.encodeWithSelector(DominantJuice.InvalidPaymentEvent.selector, rando, didPayData.projectId, 0)
        );
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function test_didPay_revertsOnWrongProjectId() public initialized {
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        didPayData.projectId = 50000; // not a correct projectId
        vm.prank(address(ethPaymentTerminal)); // Payment terminal calling
        vm.expectRevert(
            abi.encodeWithSelector(
                DominantJuice.InvalidPaymentEvent.selector, address(ethPaymentTerminal), didPayData.projectId, 0
            )
        );
        dominantJuice.didPay(didPayData); // Wrong projectId
    }

    // PASSING
    function test_didPay_revertsWhenCycleHasExpired() public initialized bonusDeposited {
        //cycleExpiryDate = block.timestamp + 3 weeks;
        //stdstore.target(address(dominantJuice)).sig("cycleExpiryDate()").checked_write(cycleExpiryDate);
        didPayData.projectId = projectID;
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.warp(dominantJuice.cycleExpiryDate() + 60);
        vm.expectRevert(DominantJuice.CycleHasExpired.selector);
        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function test_didPay_happyPath() public initialized bonusDeposited {
        didPayData.payer = pledger1;
        didPayData.projectId = 5;
        didPayData.amount = JBTokenAmount(ethToken, MIN_PLEDGE_AMOUNT, 18, 2000);
        didPayData.amount.value = MIN_PLEDGE_AMOUNT;
        //JBTokenAmount memory amount = didPayData.amount;
        //amount.value = MIN_PLEDGE_AMOUNT;
        //uint256 paymentAmount = amount.value;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.expectCall(address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)));
        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData);
        assertEq(MIN_PLEDGE_AMOUNT, dominantJuice.totalAmountPledged());
        assertEq(MIN_PLEDGE_AMOUNT, dominantJuice.getPledgerAmount(pledger1)); // Getter test
        assertEq(pledger1, dominantJuice.pledgers(0)); // pledgeOrder and index should be 0.
        assertEq(MIN_PLEDGE_AMOUNT, dominantJuice.orderToPledgerToAmount(0, pledger1));
        assertEq(1, dominantJuice.pledgeOrder()); // pledgeOrder should increment to 1 after payment

        // Test getBalance getter
        assertEq(TOTAL_REFUND_BONUS, dominantJuice.getBalance());

        // Test getCycleFundingStatus getter
        (uint256 totalAmount, uint256 percent, bool targetMet, bool creatorWithdrawn) =
            dominantJuice.getCycleFundingStatus();
        assertEq(totalAmount, MIN_PLEDGE_AMOUNT);
        assertEq(percent, 1); // (100 * 1e12 wei) / 1e14 wei
        assertEq(targetMet, false);
        assertEq(creatorWithdrawn, false);
    }

    ///////////////////////////////////
    // relayCycleResults() Tests //
    //////////////////////////////////

    // PASSING
    function testFuzz_relayCycle_revertsWhenCycleIsActive(uint256 timeAdvance) public initialized bonusDeposited {
        vm.assume(timeAdvance < 3 weeks);
        vm.warp(block.timestamp + timeAdvance);
        vm.expectRevert(
            abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, dominantJuice.cycleExpiryDate())
        );
        dominantJuice.relayCycleResults();
    }

    modifier successfulCycleHasExpired() {
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger2).checked_write(
            CYCLE_TARGET
        );
        stdstore.target(address(dominantJuice)).sig("totalAmountPledged()").checked_write(CYCLE_TARGET);
        vm.warp(dominantJuice.cycleExpiryDate() + 100);
        _;
    }

    modifier FailedCycleHasExpired() {
        uint256 pledger1Amount = 40000 gwei;
        uint256 pledger2Amount = 20000 gwei;
        uint256 pledger3Amount = 1000 gwei;
        uint256 totalPledgerAmount = pledger1Amount + pledger2Amount + pledger3Amount;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger1).checked_write(
            pledger1Amount
        );
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger2).checked_write(
            pledger2Amount
        );
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger3).checked_write(
            pledger3Amount
        );
        // stdstore.target(address(dominantJuice)).sig("pledgedAmount()").checked_write(CYCLE_TARGET);
        // stdstore.target(address(dominantJuice)).sig("orderToPledgerToAmount()").checked_write(CYCLE_TARGET);
        // stdstore.target(address(dominantJuice)).sig("orderToPledgerToAmount()").checked_write(CYCLE_TARGET);
        // stdstore.target(address(dominantJuice)).sig("orderToPledgerToAmount()").checked_write(CYCLE_TARGET);
        stdstore.target(address(dominantJuice)).sig("totalAmountPledged()").checked_write(totalPledgerAmount);
        vm.warp(dominantJuice.cycleExpiryDate() + 100);
        _;
    }

    // PASSING
    function test_relayCycle_revertsWhenCalledTwice() public FailedCycleHasExpired {
        dominantJuice.relayCycleResults();
        vm.expectRevert(DominantJuice.FunctionHasAlreadyBeenCalled.selector);
        dominantJuice.relayCycleResults();
    }

    // Sets fund balance, isCycleExpired and isTargetMet booleans, emits CycleHasClosed event
    function testFuzz_relayCycle_happyPath(uint256 _amount) public initialized bonusDeposited {
        //stdstore.target(address(dominantJuice)).sig("cycleTarget()").checked_write(CYCLE_TARGET);
        stdstore.target(address(dominantJuice)).sig("totalAmountPledged()").checked_write(_amount);
        vm.warp(dominantJuice.cycleExpiryDate() + 100);

        if (_amount < CYCLE_TARGET) {
            vm.expectEmit(true, true, true, true, address(dominantJuice));
            emit CycleHasClosed(true, false);
        } else {
            vm.expectEmit(true, true, true, true, address(dominantJuice));
            emit CycleHasClosed(true, true);
        }

        dominantJuice.relayCycleResults();

        bool expired = dominantJuice.isCycleExpired();
        assertEq(expired, true);

        if (_amount < CYCLE_TARGET) {
            bool isMet = dominantJuice.isTargetMet();
            assertEq(isMet, false);
        } else {
            bool isMet = dominantJuice.isTargetMet();
            assertEq(isMet, true);
        }
    }

    ///////////////////////////////////
    // redeemParams() Tests //
    //////////////////////////////////

    // PASSING
    function test_redeemParams_revertsIfNotPledger() public initialized bonusDeposited {
        vm.warp(dominantJuice.cycleExpiryDate() + 100);
        redeemParamsData.holder = rando;
        dominantJuice.relayCycleResults();
        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.MustBePledger.selector));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function testFuzz_redeemParams_revertsDuringCycle(uint256 _seconds) public initialized bonusDeposited {
        vm.assume(_seconds < dominantJuice.cycleExpiryDate() - block.timestamp);
        vm.warp(_seconds);
        redeemParamsData.holder = pledger2;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger2).checked_write(
            MIN_PLEDGE_AMOUNT
        );
        vm.prank(pledger2);
        vm.expectRevert(
            abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, dominantJuice.cycleExpiryDate())
        );
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfSuccessfulCycle() public initialized bonusDeposited successfulCycleHasExpired {
        redeemParamsData.holder = pledger2;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger2).checked_write(
            MIN_PLEDGE_AMOUNT
        );
        dominantJuice.relayCycleResults();
        vm.prank(pledger2);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.NoRefundsForSuccessfulCycle.selector));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfAlreadyWithdrawn() public initialized bonusDeposited FailedCycleHasExpired {
        dominantJuice.relayCycleResults();
        redeemParamsData.holder = pledger1;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger1).checked_write(
            MIN_PLEDGE_AMOUNT
        );
        stdstore.target(address(dominantJuice)).sig("hasBeenRefunded(address)").with_key(pledger1).checked_write(true);
        vm.expectRevert(DominantJuice.AlreadyWithdrawnRefund.selector);
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING (unimplemented feature error)
    function test_redeemParams_returnsMemoryVariables() public initialized bonusDeposited FailedCycleHasExpired {
        dominantJuice.relayCycleResults();
        tokenStruct = JBTokenAmount(ethToken, MIN_PLEDGE_AMOUNT, 18, 1);
        redeemParamsData.holder = pledger1;
        redeemParamsData.reclaimAmount.value = 1;
        redeemParamsData.memo = "juice";
        //redeemParamsData.amount = tokenStruct;

        // Error: Unimplemented feature (/solidity/libsolidity/codegen/ArrayUtils.cpp:228):
        // Copying of type struct JBPayDelegateAllocation3_1_1 memory[] memory to storage not yet supported.
        // delegateAllocations = new JBPayDelegateAllocation3_1_1[](1);
        // delegateAllocations[0] = JBPayDelegateAllocation3_1_1(dominantJuice, 0, "");

        (uint256 _reclaimAmount, string memory _memo,) = dominantJuice.redeemParams(redeemParamsData);
        assertEq(redeemParamsData.reclaimAmount.value, _reclaimAmount);
        assertEq(redeemParamsData.memo, _memo);
        //assertEq(0, delegateAllocations[0].amount);
    }

    ///////////////////////////////////
    // didRedeem() Tests //
    //////////////////////////////////

    // PASSING
    function test_didRedeem_revertsIfPaymentSent() public initialized {
        vm.expectRevert(
            abi.encodeWithSelector(
                DominantJuice.InvalidRedemptionEvent.selector, rando, didRedeemData.projectId, MIN_PLEDGE_AMOUNT
            )
        );
        vm.prank(rando);
        dominantJuice.didRedeem{value: MIN_PLEDGE_AMOUNT}(didRedeemData);
    }

    // PASSING
    function test_didRedeem_revertsIfNotPaymentTerminal() public initialized {
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(rando))),
            abi.encode(false)
        );
        vm.expectCall(
            address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(rando)))
        );
        vm.prank(rando); // non-paymentTerminal calling
        vm.expectRevert(
            abi.encodeWithSelector(DominantJuice.InvalidRedemptionEvent.selector, rando, didRedeemData.projectId, 0)
        );
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function test_didRedeem_revertsOnWrongProjectId() public initialized {
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        didRedeemData.projectId = 50000; // not a correct projectId
        vm.prank(address(ethPaymentTerminal)); // Payment terminal calling
        vm.expectRevert(
            abi.encodeWithSelector(
                DominantJuice.InvalidRedemptionEvent.selector, address(ethPaymentTerminal), didRedeemData.projectId, 0
            )
        );
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function test_didRedeem_revertsIfNotPledger() public initialized bonusDeposited FailedCycleHasExpired {
        didRedeemData.holder = rando;
        didRedeemData.projectId = projectID;
        dominantJuice.relayCycleResults();

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.MustBePledger.selector));
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function testFuzz_didRedeem_revertsDuringCycle(uint256 _seconds) public initialized bonusDeposited {
        vm.assume(_seconds != 0);
        vm.assume(_seconds < dominantJuice.cycleExpiryDate() - block.timestamp);
        vm.warp(_seconds);
        didRedeemData.holder = pledger2;
        didRedeemData.projectId = projectID;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger2).checked_write(
            MIN_PLEDGE_AMOUNT
        );

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(
            abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, dominantJuice.cycleExpiryDate())
        );
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function test_didRedeem_revertsIfSuccessfulCycle() public initialized bonusDeposited successfulCycleHasExpired {
        didRedeemData.holder = pledger2;
        didRedeemData.projectId = projectID;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger2).checked_write(
            MIN_PLEDGE_AMOUNT
        );
        dominantJuice.relayCycleResults();

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.NoRefundsForSuccessfulCycle.selector));
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function test_didRedeem_revertsIfAlreadyWithdrawn() public initialized bonusDeposited FailedCycleHasExpired {
        dominantJuice.relayCycleResults();
        didRedeemData.holder = pledger1;
        didRedeemData.projectId = projectID;
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(pledger1).checked_write(
            MIN_PLEDGE_AMOUNT
        );
        stdstore.target(address(dominantJuice)).sig("hasBeenRefunded(address)").with_key(pledger1).checked_write(true);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.AlreadyWithdrawnRefund.selector));
        dominantJuice.didRedeem(didRedeemData);
    }

    // TODO
    // calculates refund bonus correctly and sends to pledger
    function test_didRedeem_happyPath() public initialized bonusDeposited {
        pledger1Pays(MIN_PLEDGE_AMOUNT);
        vm.warp(dominantJuice.cycleExpiryDate() + 100);

        didRedeemData.holder = pledger1;
        didRedeemData.projectId = projectID;
        dominantJuice.relayCycleResults();

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.expectCall(address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)));

        uint256 pledgerRefundBonus = dominantJuice.calculateRefundBonus(pledger1);
        console.log(pledgerRefundBonus, "pledgerRefundBonus");

        if (dominantJuice.getBalance() < pledgerRefundBonus) {
            vm.expectRevert(abi.encodeWithSelector(DominantJuice.InsufficientFunds.selector));
        }

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit CycleRefundBonusWithdrawal(pledger1, pledgerRefundBonus);

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData);
        // Asserts
        assertEq(true, dominantJuice.hasBeenRefunded(pledger1));
        assertEq(0, dominantJuice.getBalance());
        // Since pledger1 pays through the JB architecture, it doesn't subtract from pledger1's balance.
        // The unit test shouldn't cover outside state, but this was just an additional sanity assert.
        assertEq(STARTING_USER_BALANCE + pledgerRefundBonus, pledger1.balance);
    }

    // EDGE CASE. Need to figure out how to mock.
    function test_didRedeem_revertsIfInsufficientFunds() public initialized bonusDeposited {
        pledger1Pays(20000 gwei);
        vm.warp(dominantJuice.cycleExpiryDate() + 100);
        dominantJuice.relayCycleResults();
        vm.mockCall(address(dominantJuice), abi.encodeCall(dominantJuice.getBalance, ()), abi.encode(100 gwei));
        stdstore.target(address(dominantJuice)).sig("getBalance()").checked_write(100 gwei);
        stdstore.target(address(dominantJuice)).sig("balance()").checked_write(100 gwei);
        didRedeemData.holder = pledger1;

        uint256 pledgerRefundBonus = dominantJuice.calculateRefundBonus(pledger1);
        console.log(pledgerRefundBonus, "pledgerRefundBonus");

        vm.expectRevert(abi.encodeWithSelector(DominantJuice.InsufficientFunds.selector));
        vm.prank(pledger1);
        dominantJuice.didRedeem(didRedeemData);
        // Asserts
        //assertEq(true, dominantJuice.hasBeenRefunded(pledger1));
        //assertEq(pledger1.balance, STARTING_USER_BALANCE - MIN_PLEDGE_AMOUNT + pledgerRefundBonus);
    }

    ///////////////////////////////////
    // creatorWithdraw() Tests //
    //////////////////////////////////

    // PASSING
    function test_creatorWithdraw_revertsDuringCycle() public initialized bonusDeposited {
        vm.expectRevert("Cycle must be expired and successful to call this function.");
        vm.prank(owner);
        dominantJuice.creatorWithdraw(owner, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function test_creatorWithdraw_revertsIfGoalNotMet() public initialized bonusDeposited FailedCycleHasExpired {
        dominantJuice.relayCycleResults();
        vm.expectRevert("Cycle must be expired and successful to call this function.");
        vm.prank(owner);
        dominantJuice.creatorWithdraw(owner, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function testFuzz_creatorWithdraw_revertsForNonOwner(address payable _notOwner)
        public
        initialized
        bonusDeposited
        successfulCycleHasExpired
    {
        vm.assume(_notOwner != owner && _notOwner != address(0));
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_notOwner);
        dominantJuice.creatorWithdraw(_notOwner, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function testFuzz_creatorWithdraw_revertsOnOverdraw(uint256 _amount)
        public
        initialized
        bonusDeposited
        successfulCycleHasExpired
    {
        vm.assume(_amount > dominantJuice.getBalance());
        dominantJuice.relayCycleResults();
        vm.expectRevert(DominantJuice.InsufficientFunds.selector);
        vm.prank(owner);
        dominantJuice.creatorWithdraw(owner, _amount);
    }

    // PASSING
    function testFuzz_creatorWithdraw_happyPath(uint256 _amount)
        public
        initialized
        bonusDeposited
        successfulCycleHasExpired
    {
        vm.assume(_amount <= dominantJuice.totalRefundBonus());
        dominantJuice.relayCycleResults();

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit OwnerWithdrawal(owner, _amount);
        vm.prank(owner);
        dominantJuice.creatorWithdraw(owner, _amount);

        if (dominantJuice.getBalance() == 0) {
            assertEq(true, dominantJuice.hasCreatorWithdrawnAllFunds());
            (,,, bool ownerHasWithdrawnAllFunds) = dominantJuice.getCycleFundingStatus();
            assertEq(ownerHasWithdrawnAllFunds, true);
        }

        assertEq(owner.balance, STARTING_USER_BALANCE - TOTAL_REFUND_BONUS + _amount);
    }

    // PASSING
    function test_creatorWithdraw_sendsFundsToDifferentAddress()
        public
        initialized
        bonusDeposited
        successfulCycleHasExpired
    {
        dominantJuice.relayCycleResults();
        vm.prank(owner);
        dominantJuice.creatorWithdraw(rando, TOTAL_REFUND_BONUS);
        assertEq(rando.balance, STARTING_USER_BALANCE + TOTAL_REFUND_BONUS);
    }

    ///////////////////////////////////
    // Getter Tests
    //////////////////////////////////

    // PASSING
    function test_calculateRefundBonus_revertsIfNonPledgerAddress(address _notPledger)
        public
        initialized
        bonusDeposited
    {
        vm.expectRevert("Address is not a pledger.");
        dominantJuice.calculateRefundBonus(_notPledger);
    }

    // PASSING: 3 pledgers
    function test_calculateRefundBonus_happyPath() public initialized bonusDeposited {
        // Simulate 3 pledgers pledging (and 11 pipers piping)
        JBDidPayData3_1_1 memory didPayData_pledger1;
        didPayData_pledger1.projectId = 5;
        didPayData_pledger1.payer = pledger1;
        didPayData_pledger1.amount.value = 20000 gwei;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger1);
        vm.clearMockedCalls();

        JBDidPayData3_1_1 memory didPayData_pledger2;
        didPayData_pledger2.projectId = 5;
        didPayData_pledger2.payer = pledger2;
        didPayData_pledger2.amount.value = 30000 gwei;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger2);
        vm.clearMockedCalls();

        JBDidPayData3_1_1 memory didPayData_pledger3;
        didPayData_pledger3.projectId = 5;
        didPayData_pledger3.payer = pledger3;
        didPayData_pledger3.amount.value = 1000 gwei;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger3);
        vm.clearMockedCalls();

        vm.warp(dominantJuice.cycleExpiryDate() + 60);
        dominantJuice.relayCycleResults();

        uint256 totalRefundsCalculated = dominantJuice.calculateRefundBonus(pledger1)
            + dominantJuice.calculateRefundBonus(pledger2) + dominantJuice.calculateRefundBonus(pledger3);
        uint256 diff = TOTAL_REFUND_BONUS - totalRefundsCalculated;
        console.log(diff);
        assertLe(diff, 100); // 100 is one 100 millionth of a % of error or 1x10e-8 %.
        assertLe(totalRefundsCalculated, TOTAL_REFUND_BONUS);
    }

    // PASSING: 3 pledgers, one fuzzed input amount.
    function testFuzz_calculateRefundBonus_happyPath(uint256 _amount) public initialized bonusDeposited {
        _amount = bound(_amount, MIN_PLEDGE_AMOUNT, CYCLE_TARGET - 50001 gwei);
        // Simulate 3 pledgers pledging (and 11 pipers piping)
        JBDidPayData3_1_1 memory didPayData_pledger1;
        didPayData_pledger1.projectId = 5;
        didPayData_pledger1.payer = pledger1;
        didPayData_pledger1.amount.value = 20000 gwei;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger1);
        vm.clearMockedCalls();

        JBDidPayData3_1_1 memory didPayData_pledger2;
        didPayData_pledger2.projectId = 5;
        didPayData_pledger2.payer = pledger2;
        didPayData_pledger2.amount.value = 30000 gwei;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger2);
        vm.clearMockedCalls();

        JBDidPayData3_1_1 memory didPayData_pledger3;
        didPayData_pledger3.projectId = 5;
        didPayData_pledger3.payer = pledger3;
        didPayData_pledger3.amount.value = _amount;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger3);
        vm.clearMockedCalls();

        vm.warp(dominantJuice.cycleExpiryDate() + 60);
        dominantJuice.relayCycleResults();

        uint256 totalRefundsCalculated = dominantJuice.calculateRefundBonus(pledger1)
            + dominantJuice.calculateRefundBonus(pledger2) + dominantJuice.calculateRefundBonus(pledger3);
        uint256 diff = TOTAL_REFUND_BONUS - totalRefundsCalculated;
        console.log(diff);
        assertLe(diff, 1000); // 1000 is one 10 millionth of a % of error or 1x10e-7 %.
        assertLe(totalRefundsCalculated, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function test_getBalance() public initialized bonusDeposited {
        uint256 balance = dominantJuice.getBalance();
        assertEq(balance, dominantJuice.totalRefundBonus());
    }

    // PASSING
    function test_getCycleFundingStatus_getsCorrectly(uint256 _amount) public initialized bonusDeposited {
        vm.assume(_amount < dominantJuice.totalRefundBonus());
        stdstore.target(address(dominantJuice)).sig("totalAmountPledged()").checked_write(_amount);
        (uint256 totalAmount, uint256 percent, bool targetMet, bool creatorWithdrawn) =
            dominantJuice.getCycleFundingStatus();
        assertEq(totalAmount, dominantJuice.totalAmountPledged());
        uint256 calculatedPercent = ((100 * dominantJuice.totalAmountPledged()) / dominantJuice.cycleTarget());
        assertEq(percent, calculatedPercent); // e.g. (100 * 1e12) / 1e14
        assertEq(targetMet, false);
        assertEq(creatorWithdrawn, false);
    }

    // PASSING
    function test_getPledgerAmount(address _address, uint256 _amount) public initialized bonusDeposited {
        stdstore.target(address(dominantJuice)).sig("pledgedAmount(address)").with_key(_address).checked_write(_amount);
        uint256 amount = dominantJuice.getPledgerAmount(_address);
        assertEq(amount, _amount);
    }

    ///////////////////////////////////
    // Test Helpers
    //////////////////////////////////

    function pledger1Pays(uint256 _value) public {
        JBDidPayData3_1_1 memory didPayData_pledger1;
        didPayData_pledger1.projectId = projectID;
        didPayData_pledger1.payer = pledger1;
        didPayData_pledger1.amount.value = _value;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger1);
        vm.clearMockedCalls();
    }
}

// To test the calculateRefundBonus function, I put in a bunch of Test events in DominantJuice.sol so I could
// see what was happening on each line. To keep the main .sol file clean, all of that is here to add back in,
// in case you want to test it that way.
// function calculateRefundBonus(address _pledger) public returns (uint256) {
//         require(pledgedAmount[_pledger] > 0, "Address is not a pledger.");

//         uint256 numPledgers = pledgers.length;
//         UD60x18 individualRefundBonus;
//         UD60x18 pledgeAmount_orderLoop;
//         UD60x18 pledgeAmount_amountLoop;

//         // Donations and order of pledges are weighted to benefit earlier, larger pledges
//         UD60x18 orderWeight;
//         UD60x18 sumOfOrderWeights;
//         // Memory array of normalized order weights (w-1s)
//         uint256[] memory orderWeightNormalized = new uint[](numPledgers);
//         UD60x18 sumOfAmountsXNormalizedOrderWeights;
//         // uint256 donationWeight;
//         // uint256 donationWeightNormalized;
//         // Represents the combined order and pledge amount weighting.
//         UD60x18 overallPledgeWeight;
//         emit Test("numPledgers", numPledgers);
//         emit Test("totalAmountPledged", totalAmountPledged);
//         // First, get the sum of pledge order weights to use in the normalizing loop
//         for (uint32 i = 0; i < numPledgers; i++) {
//             //UD60x18 i_ud = wrap(i + 1);
//             //emit Test("i_ud", unwrap(i_ud));
//             // Add 1 to i because rateOfDecay is being raised to the pledge ordereth power
//             sumOfOrderWeights = add(sumOfOrderWeights, rateOfDecay.powu(i + 1));
//             //sumOfOrderWeights += (rateOfDecay ** i) * 1 ether;
//             UD60x18 power = rateOfDecay.powu(4);
//             emit Test("rateOfDecay", unwrap(rateOfDecay));
//             emit Test("power", unwrap(power));
//             emit Test("sumOfOrderWeights", unwrap(sumOfOrderWeights));
//         }

//         // Refund Bonus calculation prep work:
//         for (uint32 j = 0; j < numPledgers; j++) {
//             //UD60x18 j_ud = wrap(j + 1);
//             // Earlier pledges are given more weight according to the exponential decay rate.
//             // Add 1 to j because rateOfDecay is being raised to the ordereth power.
//             orderWeight = rateOfDecay.powu(j + 1); // No decimals
//             //orderWeight = (rateOfDecay ** j) * 1 ether;
//             emit Test("orderWeight", unwrap(orderWeight));
//             // Order weights are normalized to compare each pledge to the total pledging data.
//             // Save in memory array for use in next for loop.
//             orderWeightNormalized[j] = unwrap(orderWeight / sumOfOrderWeights);
//             emit Test("orderWeightNormalized[j]", orderWeightNormalized[j]);
//             // Get the payment amount for each order
//             pledgeAmount_orderLoop = wrap(orderToPledgerToAmount[j][pledgers[j]]);
//             // Multiply payments by their respective normalized weight. Sum all products by
//             // looping (=sum(x*w_1)). Use in next for loop
//             sumOfAmountsXNormalizedOrderWeights =
//                 add(sumOfAmountsXNormalizedOrderWeights, mul(pledgeAmount_orderLoop, wrap(orderWeightNormalized[j])));
//             emit Test(
//                 "AmountXNormalizedOrderWeight", unwrap(mul(pledgeAmount_orderLoop, wrap(orderWeightNormalized[j])))
//             );
//             emit Test("sumOfAmountsXNormalizedOrderWeights", unwrap(sumOfAmountsXNormalizedOrderWeights));
//         }

//         // Next, give more weight to larger contribution amounts by multiplying each pledge amount with its
//         // orderWeightNormalized. Looping logic is for the possibility of repeat pledgers
//         for (uint32 k = 0; k < numPledgers; k++) {
//             if (pledgers[k] == _pledger) {
//                 pledgeAmount_amountLoop = wrap(orderToPledgerToAmount[k][_pledger]);
//                 overallPledgeWeight =
//                     mul(pledgeAmount_amountLoop, wrap(orderWeightNormalized[k])) / sumOfAmountsXNormalizedOrderWeights;
//                 emit Test("overallPledgeWeight", unwrap(overallPledgeWeight));
//                 // Multiply totalRefundBonus by overallWeight to get the individual refund. Loop again.
//                 // If pledger's address is found in the pledger array again, add to individual total.
//                 individualRefundBonus = add(individualRefundBonus, mul(overallPledgeWeight, wrap(totalRefundBonus)));
//                 emit Test("individualRefundBonus", unwrap(individualRefundBonus));
//             }
//         }
//         return unwrap(individualRefundBonus);
//     }

// DO NOT USE:
// function testFuzz_relayCycle_JBAndContractPledgeAmountsMatch(uint256 _amount) public initialized bonusDeposited {
//         stdstore.target(address(dominantJuice)).sig("totalAmountPledged()").checked_write(_amount);
//         vm.warp(dominantJuice.cycleExpiryDate() + 100);
//         uint256 amount_fromJB = _amount;

//         if (dominantJuice.totalAmountPledged() != amount_fromJB) {
//         stdstore.target(address(dominantJuice)).sig("totalAmountPledged()").checked_write(amount_fromJB);
//     }

//         vm.mockCall(
//             address(paymentTerminalStore),
//             abi.encodeCall(paymentTerminalStore.balanceOf, (ethPaymentTerminal, projectID)),
//             abi.encode(amount_fromJB)
//         );
//         vm.expectCall(
//             address(paymentTerminalStore),
//             abi.encodeCall(paymentTerminalStore.balanceOf, (ethPaymentTerminal, projectID))
//         );

//         if (_amount < CYCLE_TARGET) {
//             vm.expectEmit(true, true, true, true, address(dominantJuice));
//             emit CycleHasClosed(true, false);
//         } else {
//             vm.expectEmit(true, true, true, true, address(dominantJuice));
//             emit CycleHasClosed(true, true);
//         }

//         vm.prank(rando);
//         dominantJuice.relayCycleResults();

//         bool expired = dominantJuice.isCycleExpired();
//         assertEq(expired, true);

//         if (_amount < CYCLE_TARGET) {
//             bool isMet = dominantJuice.isTargetMet();
//             assertEq(isMet, false);
//         } else {
//             bool isMet = dominantJuice.isTargetMet();
//             assertEq(isMet, true);
//         }
//     }
