// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {DominantJuice} from "../../src/DominantJuice.sol";
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
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract DominantJuiceTest_Unit is Test, AccessControl {
    using stdStorage for StdStorage;

    // Juicebox (JB) Contracts
    IJBController3_1 public controller = IJBController3_1(makeAddr("controller"));
    IJBDirectory public directory = IJBDirectory(makeAddr("directory"));
    IJBFundAccessConstraintsStore public fundAccessConstraintsStore =
        IJBFundAccessConstraintsStore(makeAddr("fundAccessConstraintsStore"));
    IJBSingleTokenPaymentTerminalStore3_1_1 public paymentTerminalStore =
        IJBSingleTokenPaymentTerminalStore3_1_1(makeAddr("paymentTerminalStore"));
    IJBSingleTokenPaymentTerminal ethPaymentTerminal = IJBSingleTokenPaymentTerminal(makeAddr("ethPaymentTerminal"));

    // Data structs for JB functions: launchProjectFor(), pay(), redeemTokensOf()
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

    // Dominant Assurance Contract (DAC) users and addresses
    address payable admin = payable(makeAddr("admin"));
    address payable campaignManager = payable(makeAddr("campaignManager"));
    address payable public pledger1 = payable(makeAddr("pledger1"));
    address payable public pledger2 = payable(makeAddr("pledger2"));
    address payable public pledger3 = payable(makeAddr("pledger3"));
    address payable public rando = payable(makeAddr("rando"));
    address public ethToken = makeAddr("ethToken");

    // DAC constants
    uint256 public constant STARTING_BALANCE = 10000 ether; // 10000e18 wei
    uint256 public constant TOTAL_REFUND_BONUS = 10 ether; // 0.00001 ether, 1e13 wei
    uint256 public constant CYCLE_TARGET = 1300 ether; // 0.0001 ether, 1e14 wei
    uint256 public constant MIN_PLEDGE_AMOUNT = 45 ether; // 0.000001 ether, 1e12 wei
    uint256 public constant CYCLE_DURATION = 20 days;
    bytes32 constant campaignManagerRole = keccak256("CAMPAIGN_MANAGER_ROLE");
    UD60x18 rateOfDecay = ud(0.99e18);

    // DAC Variables
    uint256 public projectID = 5;
    uint256 public cycleExpiryDate;

    // Events
    event RefundBonusDeposited(address _campaignManager, uint256 indexed _totalRefundBonus);
    event PledgeMade(address, uint256);
    event CycleHasClosed(bool indexed, bool indexed);
    event CycleRefundBonusWithdrawal(address indexed, uint256 indexed);
    event CreatorWithdrawal(address, uint256);

    function setUp() external {
        vm.deal(campaignManager, STARTING_BALANCE);
        vm.deal(admin, STARTING_BALANCE);
        vm.deal(pledger1, STARTING_BALANCE);
        vm.deal(pledger2, STARTING_BALANCE);
        vm.deal(pledger3, STARTING_BALANCE);
        vm.deal(rando, STARTING_BALANCE);

        vm.etch(address(controller), "I'm the operator with my pocket calculator");
        vm.etch(address(directory), "I'm the operator with my pocket calculator");
        vm.etch(address(fundAccessConstraintsStore), "I'm the operator with my pocket calculator");
        vm.etch(address(paymentTerminalStore), "I'm the operator with my pocket calculator");
        vm.etch(address(ethPaymentTerminal), "I'm the operator with my pocket calculator");

        _terminals.push(ethPaymentTerminal);

        // Deploy the target contract.
        mockExternalCallsForConstructor();
        vm.prank(admin);
        dominantJuice =
        new DominantJuice(campaignManager, projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);

        // Get cycleExpiryDate for use in tests
        DominantJuice.Campaign memory campaign = dominantJuice.getCampaignInfo();
        cycleExpiryDate = campaign.cycleExpiryDate;
    }

    /**
     * List of Helper Functions (Helper section is at end of this contract body):
     * - mockExternalCallsForConstructor(): mocks all external calls needed in the constructor
     * - pledge(): makes a pledge for the input pledger with the input amount.
     * - successfulCycleHasExpired(): Mocks 3 pledgers pledging over target amount and advances time past cycleExpiryDate
     * - failedCycleHasExpired(): Mocks 3 pledgers pledging under target amount and advances time past cycleExpiryDate
     * - redeem(): requests a redemption for the input redeemer.
     */

    //////////////////////////////////
    // supportsInterface() Test
    //////////////////////////////////

    // PASSING
    function test_supportsInterface_happyPathForAllThree() public {
        // Interface IDs from Juicebox docs: https://docs.juicebox.money/dev/build/namespace/
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

    ///////////////////////////
    // Constructor Tests
    ///////////////////////////

    // PASSING
    function test_constructor_storesAllVariablesAndContracts() public {
        mockExternalCallsForConstructor();

        DominantJuice dominantJuice_constructorTest =
        new DominantJuice(campaignManager, projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);

        DominantJuice.Campaign memory campaign = dominantJuice_constructorTest.getCampaignInfo();
        uint256 projectId = campaign.projectId;
        uint256 cycleTarget = campaign.cycleTarget;
        uint256 expiryDate = campaign.cycleExpiryDate;
        uint256 minimumPledgeAmount = campaign.minimumPledgeAmount;
        uint256 totalRefundBonus = campaign.totalRefundBonus;

        uint256 endDate = _cycle.start + _cycle.duration;

        assertEq(projectID, projectId);
        assertEq(CYCLE_TARGET, cycleTarget);
        assertEq(endDate, expiryDate);
        assertEq(MIN_PLEDGE_AMOUNT, minimumPledgeAmount);
        assertEq(0, totalRefundBonus); // Since has not been deposited yet.
        assertEq(address(controller), address(dominantJuice_constructorTest.controller()));
        assertEq(address(directory), address(dominantJuice_constructorTest.directory()));
        assertEq(
            address(fundAccessConstraintsStore), address(dominantJuice_constructorTest.fundAccessConstraintsStore())
        );
        assertEq(address(ethPaymentTerminal), address(dominantJuice_constructorTest.paymentTerminal()));
    }

    // PASSING
    function test_constructor_grantsRoles() public {
        assertTrue(dominantJuice.hasRole(campaignManagerRole, campaignManager));
        assertTrue(dominantJuice.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    ///////////////////////////////////
    // depositRefundBonus() Tests
    ///////////////////////////////////

    // PASSING
    function test_depositRefundBonus_revertsForNotCampaignManager() public {
        vm.prank(rando); // rando account address: 0x8e24d86be44ab9006bd1277bddc948ecebbfbf6c
        vm.expectRevert(
            "AccessControl: account 0x8e24d86be44ab9006bd1277bddc948ecebbfbf6c is missing role 0x5022544358ee0bece556b72ae8983c7f24341bd5b9483ce8a19bff5efbb2de92"
        );
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();
    }

    // PASSING
    function test_depositRefundBonus_revertsWhenAdminCalls() public {
        vm.prank(admin); // admin account address: 0xaa10a84ce7d9ae517a52c6d5ca153b369af99ecf
        vm.expectRevert(
            "AccessControl: account 0xaa10a84ce7d9ae517a52c6d5ca153b369af99ecf is missing role 0x5022544358ee0bece556b72ae8983c7f24341bd5b9483ce8a19bff5efbb2de92"
        );
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();
    }

    // Maybe add a reverting fuzz test with string concatenation for the error message.

    // PASSING
    function testFuzz_depositRefundBonus_allowsOwnerDepositAndEmitsEvent(uint256 _bonus) public {
        // assume realistic values
        _bonus = bound(_bonus, 1, 10000 ether);
        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit RefundBonusDeposited(campaignManager, _bonus);

        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: _bonus}();

        uint256 balance = dominantJuice.getBalance();
        assertEq(balance, _bonus);
    }

    // PASSING
    function test_depositRefundBonus_revertsWhenCalledTwice() public {
        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();

        vm.expectRevert(abi.encodeWithSelector(DominantJuice.BonusAlreadyDeposited.selector, TOTAL_REFUND_BONUS));
        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();

        uint256 balance = dominantJuice.getBalance();
        assertEq(balance, TOTAL_REFUND_BONUS);
    }

    /////////////////////////
    // payParams() Tests
    /////////////////////////

    // PASSING
    function test_payParams_revertsIfNoBonusDeposit(address _random) public {
        vm.prank(_random);
        vm.expectRevert(DominantJuice.RefundBonusNotDeposited.selector);
        dominantJuice.payParams(payParamsData);
    }

    modifier bonusDeposited() {
        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();
        _;
    }

    // PASSING
    function test_payParams_revertsWhenCycleHasExpired() public bonusDeposited {
        didPayData.projectId = projectID;
        // vm.mockCall(
        //     address(directory),
        //     abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
        //     abi.encode(true)
        // );
        vm.warp(CYCLE_DURATION + 60);
        vm.expectRevert(DominantJuice.CycleHasExpired.selector);
        vm.prank(address(ethPaymentTerminal));
        dominantJuice.payParams(payParamsData);
    }

    // PASSING
    function testFuzz_payParams_revertsWhenPaymentIsBelowMinPledge(uint256 _value) public bonusDeposited {
        // In reality, payParams() will be called by the JB Payment Terminal Store, but mocking a direct call is
        // a good check for unit testing purposes.
        vm.assume(_value < MIN_PLEDGE_AMOUNT);
        payParamsData.amount.value = _value;

        vm.expectRevert(abi.encodeWithSelector(DominantJuice.AmountIsBelowMinimumPledge.selector, MIN_PLEDGE_AMOUNT));
        vm.prank(rando);
        dominantJuice.payParams(payParamsData);
    }

    // PASSING - (unimplemented feature error)
    function test_payParams_happyPathReturnsMemoryVariables() public bonusDeposited {
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

        // Assert that there are no major contract changes when payParams is called directly:
        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        assertEq(0, status.totalPledged);
        assertEq(0, status.percentOfGoal);
        assertFalse(status.isTargetMet);
        assertFalse(status.hasCycleExpired);
        assertEq(TOTAL_REFUND_BONUS, dominantJuice.getBalance());
        (uint256 pledgerW, uint256 totalW) = dominantJuice.getPledgerAndTotalWeights(pledger1);
        assertEq(0, pledgerW);
        assertEq(0, totalW);
    }

    // payParams() function is non-payable, the parent function that calls it is nonReentrant, and there are only if
    // statements and logic to satisfy Juicebox architecture, thus not many unit tests here. This function can be
    // called directly, but nothing would happen. The only way to pledge correctly is by calling
    // `JBPayoutRedemptionPaymentTerminal3_1_1.pay()`.

    ///////////////////////
    // didPay() Tests
    ///////////////////////

    // PASSING
    function test_didPay_revertsIfPaymentSent(uint256 _amount) public {
        _amount = bound(_amount, 1, 2000 ether);
        didPayData.projectId = projectID;

        vm.expectRevert("Pledges should be made through JB website.");
        vm.prank(rando);
        dominantJuice.didPay{value: _amount}(didPayData);
    }

    // PASSING - call reverts when terminal calls with empty JBDidPayData struct (e.g. no project ID)
    function test_didPay_revertsWithEmptyDataStruct() public {
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.expectRevert(DominantJuice.IncorrectProjectID.selector);
        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function testFuzz_didPay_revertsIfNotPaymentTerminal(address _random) public {
        vm.assume(_random != address(ethPaymentTerminal));
        // Need to mock terminal check call to directory.
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(_random))),
            abi.encode(false)
        );
        vm.expectCall(
            address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(_random)))
        );

        vm.prank(_random); // non-paymentTerminal calling
        vm.expectRevert("Caller must be a JB Payment Terminal.");
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function test_didPay_revertsOnWrongProjectId() public {
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        didPayData.projectId = 50000; // not a correct projectId
        vm.prank(address(ethPaymentTerminal)); // Payment terminal calling
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.IncorrectProjectID.selector));
        dominantJuice.didPay(didPayData); // Wrong projectId
    }

    // PASSING
    function test_didPay_happyPathSinglePledger(uint256 _value) public bonusDeposited {
        _value = bound(_value, MIN_PLEDGE_AMOUNT, STARTING_BALANCE);

        didPayData.payer = pledger1;
        didPayData.projectId = projectID;
        didPayData.amount = JBTokenAmount(ethToken, MIN_PLEDGE_AMOUNT, 18, 2000);
        didPayData.amount.value = MIN_PLEDGE_AMOUNT;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.expectCall(address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)));
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(_cycle, _metadata)
        );

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit PledgeMade(pledger1, MIN_PLEDGE_AMOUNT);

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData);

        // Assert payment has no effect on contract funds.
        assertEq(TOTAL_REFUND_BONUS, dominantJuice.getBalance());

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();
        (uint256 pledgerW, uint256 totalW) = dominantJuice.getPledgerAndTotalWeights(pledger1);

        assertEq(MIN_PLEDGE_AMOUNT, status.totalPledged);
        uint256 percent = (100 * status.totalPledged) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal);
        assertEq(false, status.isTargetMet);
        assertEq(false, status.hasCycleExpired);
        assertEq(false, status.hasCreatorWithdrawnAllFunds);
        assertEq(pledgerW, totalW);
    }

    function testFuzz_didPay_multiplePledgers() public bonusDeposited {
        vm.warp(3600); // warp 1 hour
        pledge(pledger1, MIN_PLEDGE_AMOUNT);

        vm.warp(86400); // warp 1 day
        uint256 hourOfPledge = (block.timestamp - _cycle.start) / 3600;
        pledge(pledger2, MIN_PLEDGE_AMOUNT * 3);

        vm.warp(604800); // warp 1 week
        pledge(pledger3, MIN_PLEDGE_AMOUNT);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();
        (uint256 pledger1W, uint256 total1W) = dominantJuice.getPledgerAndTotalWeights(pledger1);
        (uint256 pledger2W,) = dominantJuice.getPledgerAndTotalWeights(pledger2);
        (uint256 pledger3W, uint256 total3W) = dominantJuice.getPledgerAndTotalWeights(pledger3);

        assertEq(MIN_PLEDGE_AMOUNT * 5, status.totalPledged);
        uint256 percent = (100 * status.totalPledged) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal); // Should be 5% (5 * min pledge)
        assertEq(false, status.isTargetMet);

        uint256 pledger2calculatedW = unwrap(rateOfDecay.powu(hourOfPledge)) * MIN_PLEDGE_AMOUNT * 3;
        uint256 calculatedTotalWeight = pledger1W + pledger2W + pledger3W;

        assertEq(pledger2calculatedW / 1e18, pledger2W); // Why is this off by a factor of 1e18?
        assertEq(calculatedTotalWeight, total3W);
        assertLt(pledger3W, pledger1W); // pledger3W is less since pledged much later
        assertEq(total1W, total3W); // Getter calls happen after pledges, so total weight doesn't change.
    }

    function test_didPay_simultaneousPledgersHaveSameWeight() public bonusDeposited {
        pledge(pledger2, MIN_PLEDGE_AMOUNT);
        pledge(pledger3, MIN_PLEDGE_AMOUNT);
        vm.warp(3601);
        pledge(pledger1, MIN_PLEDGE_AMOUNT);

        (uint256 pledger1W,) = dominantJuice.getPledgerAndTotalWeights(pledger1);
        (uint256 pledger2W,) = dominantJuice.getPledgerAndTotalWeights(pledger2);
        (uint256 pledger3W,) = dominantJuice.getPledgerAndTotalWeights(pledger3);

        assertEq(pledger2W, pledger3W);
        assertLt(pledger1W, pledger2W); // Pledger1 should have less weight since pledged 1 hour later
    }

    function testFuzz_didPay_simultaneousPledgersDiffAmounts(uint256 _pledger2Amount) public bonusDeposited {
        vm.warp(10 days);
        _pledger2Amount = bound(_pledger2Amount, 90 ether, 110 ether);
        pledge(pledger2, _pledger2Amount);
        pledge(pledger3, 100 ether);

        (uint256 pledger2W,) = dominantJuice.getPledgerAndTotalWeights(pledger2);
        (uint256 pledger3W, uint256 totalW) = dominantJuice.getPledgerAndTotalWeights(pledger3);

        if (_pledger2Amount < 100 ether) {
            assertLt(pledger2W, pledger3W);
        } else {
            assertGe(pledger2W, pledger3W);
        }

        assertEq(pledger2W + pledger3W, totalW); // total weight should always be sum of both weights
    }

    // More didPay fuzz testing with multiple pledgers

    ////////////////////////////////
    // redeemParams() Tests
    ////////////////////////////////

    // PASSING
    function testFuzz_redeemParams_revertsDuringCycle(uint256 _seconds) public bonusDeposited {
        // pledger2 pledges. Advance time but still be in cycle window.
        pledge(pledger2, 200 ether);
        vm.assume(_seconds < cycleExpiryDate - block.timestamp);
        vm.warp(_seconds);

        vm.prank(pledger2);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, cycleExpiryDate));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfSuccessfulCycle() public bonusDeposited {
        // See Test Helpers section for explanation of this function:
        successfulCycleHasExpired();

        // Pledger calls to redeem.
        vm.prank(pledger2);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.NoRefundsForSuccessfulCycle.selector));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfNotPledger() public bonusDeposited {
        failedCycleHasExpired();

        redeemParamsData.holder = rando; // Satisfy data struct parameter
        vm.warp(cycleExpiryDate + 100);

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.MustBePledger.selector));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfAlreadyWithdrawn() public bonusDeposited {
        failedCycleHasExpired();
        redeemParamsData.holder = pledger1;

        // Pledger1 calls redeem
        redeem(pledger1);

        vm.expectRevert(DominantJuice.AlreadyWithdrawnRefund.selector);
        vm.prank(pledger1);
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING (unimplemented feature error)
    function test_redeemParams_returnsMemoryVariables() public bonusDeposited {
        failedCycleHasExpired();

        redeemParamsData.holder = pledger1;
        redeemParamsData.reclaimAmount.value = 1;
        redeemParamsData.memo = "juice";

        // Error: Unimplemented feature (/solidity/libsolidity/codegen/ArrayUtils.cpp:228):
        // Copying of type struct JBRedemptionDelegateAllocation3_1_1 memory[] memory to storage not yet supported.
        // delegateAllocations = new JBRedemptionDelegateAllocation3_1_1[](1);
        // delegateAllocations[0] = JBRedemptionDelegateAllocation3_1_1(dominantJuice, 0, "");

        (uint256 _reclaimAmount, string memory _memo,) = dominantJuice.redeemParams(redeemParamsData);
        assertEq(redeemParamsData.reclaimAmount.value, _reclaimAmount);
        assertEq(redeemParamsData.memo, _memo);
    }

    //////////////////////////
    // didRedeem() Tests
    //////////////////////////

    // PASSING
    function testFuzz_didRedeem_revertsIfPaymentSent(uint256 _amount) public {
        _amount = bound(_amount, 1, 2000 ether);
        //didRedeemData.projectId = projectID;

        vm.expectRevert("Pledges should be made through JB website.");
        vm.prank(rando);
        dominantJuice.didRedeem{value: MIN_PLEDGE_AMOUNT}(didRedeemData);
    }

    // PASSING
    function testFuzz_didRedeem_revertsIfNotPaymentTerminal(address _random) public {
        vm.assume(_random != address(ethPaymentTerminal));
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(_random))),
            abi.encode(false)
        );
        vm.expectCall(
            address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(_random)))
        );
        vm.prank(_random); // non-paymentTerminal calling
        vm.expectRevert("Caller must be a JB Payment Terminal.");
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function testFuzz_didRedeem_revertsDuringCycle(uint256 _seconds) public bonusDeposited {
        // pledger3 pledges. Advance time but still be in cycle window.
        pledge(pledger3, 200 ether);

        //vm.assume(_seconds != 0);
        vm.assume(_seconds < cycleExpiryDate - block.timestamp);
        vm.warp(_seconds);
        didRedeemData.holder = pledger3;
        didRedeemData.projectId = projectID;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, cycleExpiryDate));
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function test_didRedeem_revertsIfSuccessfulCycle() public bonusDeposited {
        successfulCycleHasExpired();
        didRedeemData.holder = pledger2;
        didRedeemData.projectId = projectID;

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
    function test_didRedeem_revertsOnWrongProjectId(uint256 _projectID) public {
        vm.assume(_projectID != projectID);
        vm.warp(cycleExpiryDate + 100);

        didRedeemData.projectId = _projectID; // not correct projectId
        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal)); // Payment terminal calling
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.IncorrectProjectID.selector));
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    // Test in case Juicebox architecture goes wonky.
    function test_didRedeem_revertsIfNotPledger() public bonusDeposited {
        failedCycleHasExpired();
        vm.warp(cycleExpiryDate + 100);

        didRedeemData.holder = rando;
        didRedeemData.projectId = projectID;

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
    // Test in case Juicebox architecture goes wonky.
    function test_didRedeem_revertsIfAlreadyWithdrawn() public bonusDeposited {
        failedCycleHasExpired();
        didRedeemData.holder = pledger1;
        didRedeemData.projectId = projectID;

        // Pledger1 redeems
        redeem(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        // Pledger1 tries to redeem again via JB.
        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(DominantJuice.AlreadyWithdrawnRefund.selector);
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function testFuzz_didRedeem_happyPath(uint256 _pledgeAmount) public bonusDeposited {
        // Pledger1 pledges up to and excluding cycleTarget amount and time advances past expiry date.
        _pledgeAmount = bound(_pledgeAmount, MIN_PLEDGE_AMOUNT, CYCLE_TARGET - 1);
        pledge(pledger1, _pledgeAmount);
        vm.warp(cycleExpiryDate + 100);

        didRedeemData.holder = pledger1;
        didRedeemData.projectId = projectID;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.expectCall(address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)));

        (uint256 pledgerWeight, uint256 totalWeight) = dominantJuice.getPledgerAndTotalWeights(pledger1);
        DominantJuice.Campaign memory campaign = dominantJuice.getCampaignInfo();

        uint256 pledgerRefundBonus = (pledgerWeight / totalWeight) * campaign.totalRefundBonus;

        if (dominantJuice.getBalance() < pledgerRefundBonus) {
            vm.expectRevert(abi.encodeWithSelector(DominantJuice.InsufficientFunds.selector));
        }

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit CycleRefundBonusWithdrawal(pledger1, pledgerRefundBonus);

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData);

        assertEq(true, dominantJuice.getPledgerRefundStatus(pledger1));
        assertEq(0, dominantJuice.getBalance());
        assertEq(pledgerRefundBonus, TOTAL_REFUND_BONUS);
        // Since pledger1 pays through the JB architecture, it doesn't subtract from pledger1's balance.
        // The unit test shouldn't cover outside state, but this was just an additional sanity assert.
        assertEq(STARTING_BALANCE + pledgerRefundBonus, pledger1.balance);
    }

    // Add more didRedeem fuzz tests with multiple redeemers

    // EDGE CASE - contract has less balance than it should. How to mock?

    //////////////////////////////
    // creatorWithdraw() Tests
    //////////////////////////////

    function test_creatorWithdraw_revertsForNonOwner() public bonusDeposited {
        // vm.assume(_notOwner != campaignManager && _notOwner != address(0));
        successfulCycleHasExpired();

        vm.expectRevert(
            "AccessControl: account 0x8e24d86be44ab9006bd1277bddc948ecebbfbf6c is missing role 0x5022544358ee0bece556b72ae8983c7f24341bd5b9483ce8a19bff5efbb2de92"
        );
        vm.prank(rando);
        dominantJuice.creatorWithdraw(rando, TOTAL_REFUND_BONUS);
    }

    function testFuzz_creatorWithdraw_revertsBeforeUnlock(uint256 _seconds) public bonusDeposited {
        vm.assume(_seconds < cycleExpiryDate + 1209600);
        vm.warp(_seconds);

        vm.expectRevert("Cycle must be expired and successful, or it must be passed the lock period.");
        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);
    }

    function test_creatorWithdraw_revertsIfGoalNotMet() public bonusDeposited {
        failedCycleHasExpired();

        vm.expectRevert("Cycle must be expired and successful, or it must be passed the lock period.");
        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);
    }

    function testFuzz_creatorWithdraw_revertsOnOverdraw(uint256 _amount) public bonusDeposited {
        successfulCycleHasExpired();

        vm.assume(_amount > dominantJuice.getBalance());
        vm.expectRevert(DominantJuice.InsufficientFunds.selector);
        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, _amount);
    }

    function testFuzz_creatorWithdraw_happyPath(uint256 _amount) public bonusDeposited {
        vm.assume(_amount <= TOTAL_REFUND_BONUS);
        successfulCycleHasExpired();

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit CreatorWithdrawal(campaignManager, _amount);

        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, _amount);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        if (dominantJuice.getBalance() == 0) {
            assertEq(true, status.hasCreatorWithdrawnAllFunds);
        } else {
            assertEq(false, status.hasCreatorWithdrawnAllFunds);
        }

        assertEq(TOTAL_REFUND_BONUS - _amount, dominantJuice.getBalance());
        assertEq(STARTING_BALANCE - TOTAL_REFUND_BONUS + _amount, campaignManager.balance);
    }

    function test_creatorWithdraw_sendsFundsToDifferentAddress() public bonusDeposited {
        successfulCycleHasExpired();

        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(rando, TOTAL_REFUND_BONUS);

        assertEq(0, dominantJuice.getBalance());
        assertEq(rando.balance, STARTING_BALANCE + TOTAL_REFUND_BONUS);
    }

    function testFuzz_creatorWithdraw_creatorCanCallAfterUnlock(uint256 _seconds) public bonusDeposited {
        successfulCycleHasExpired();

        vm.assume(_seconds >= cycleExpiryDate + 1209600);
        vm.warp(_seconds);

        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);

        assertEq(0, dominantJuice.getBalance());
        assertEq(campaignManager.balance, STARTING_BALANCE); // Since receiving bonus back, should have initial balance.
    }

    ////////////////////
    // Getter Tests
    ////////////////////

    // PASSING
    function test_getBalance() public bonusDeposited {
        uint256 balance = dominantJuice.getBalance();
        assertEq(balance, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function testFuzz_isTargetMet_tracksTotalPledgesCorrectly(uint256 _amount) public bonusDeposited {
        _amount = bound(_amount, 1298 ether, 1302 ether);

        pledge(pledger1, _amount);

        if (_amount < CYCLE_TARGET) {
            bool isMet = dominantJuice.isTargetMet();
            assertEq(isMet, false);
        } else {
            bool isMet = dominantJuice.isTargetMet();
            assertEq(isMet, true);
        }
    }

    // PASSING
    function testFuzz_hasCycleExpired(uint256 _seconds) public {
        _seconds = bound(_seconds, cycleExpiryDate - 300, cycleExpiryDate + 300);
        vm.warp(_seconds);

        if (block.timestamp >= cycleExpiryDate) {
            assertTrue(dominantJuice.hasCycleExpired());
        } else {
            assertFalse(dominantJuice.hasCycleExpired());
        }
    }

    // PASSING
    function testFuzz_getCycleFundingStatus_tracksPledgeAmountsCorrectly(uint256 _amount) public bonusDeposited {
        vm.assume(_amount < TOTAL_REFUND_BONUS);
        pledge(pledger1, _amount);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();
        DominantJuice.Campaign memory campaign = dominantJuice.getCampaignInfo();

        assertEq(_amount, status.totalPledged);
        uint256 calculatedPercent = ((100 * _amount) / campaign.cycleTarget);
        assertEq(calculatedPercent, status.percentOfGoal);
        assertEq(false, status.isTargetMet);
    }

    function test_getCycleFundingStatus_FullCreatorWithdrawal() public bonusDeposited {
        successfulCycleHasExpired();

        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();
        assertEq(true, status.hasCreatorWithdrawnAllFunds);
    }

    /////////////////////
    // Test Helpers
    /////////////////////

    function mockExternalCallsForConstructor() public {
        // Mock return struct values from the controller.currentFundingCycleOf() call with the test temporal values.
        _cycle.start = block.timestamp;
        _cycle.duration = CYCLE_DURATION;

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
    }

    function pledge(address _pledger, uint256 _value) public {
        JBDidPayData3_1_1 memory didPayData_pledger;
        didPayData_pledger.projectId = projectID;
        didPayData_pledger.payer = _pledger;
        didPayData_pledger.amount.value = _value;
        //JBTokenAmount memory amount = didPayData.amount;
        //amount.value = MIN_PLEDGE_AMOUNT;
        //uint256 paymentAmount = amount.value;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(_cycle, _metadata)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData_pledger);
        vm.clearMockedCalls();
    }

    function successfulCycleHasExpired() public {
        pledge(pledger1, 200 ether);
        pledge(pledger2, 200 ether);
        pledge(pledger3, 1000 ether);
        vm.warp(cycleExpiryDate + 100);
    }

    function failedCycleHasExpired() public {
        pledge(pledger1, 50 ether);
        pledge(pledger2, 100 ether);
        pledge(pledger3, 50 ether);
        vm.warp(cycleExpiryDate + 100);
    }

    function redeem(address _pledger) public {
        JBDidRedeemData3_1_1 memory didRedeemData_pledger;
        didRedeemData_pledger.projectId = projectID;
        didRedeemData_pledger.holder = _pledger;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(_cycle, _metadata)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_pledger);
        vm.clearMockedCalls();
    }
}
