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

//import {UD60x18, ud, add, pow, powu, div, mul, wrap, unwrap} from "@prb/math/UD60x18.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../src/test/ABDKMath64x64.sol";

// Will do a general clean up and remove all the "PASSINGS', console.logs, etc before audit.
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
    JBFundingCycle _cycle;
    JBFundingCycleMetadata _metadata;

    // The target contract
    DominantJuice dominantJuice;

    // Dominant Assurance Contract (DAC) users and addresses
    address payable admin = payable(makeAddr("admin"));
    address payable campaignManager = payable(makeAddr("campaignManager"));
    address payable public pledger1 = payable(makeAddr("pledger1"));
    address payable public pledger2 = payable(makeAddr("pledger2"));
    address payable public pledger3 = payable(makeAddr("pledger3"));
    address payable public rando = payable(makeAddr("rando"));
    address public ethToken = makeAddr("ethToken");

    // DAC constants
    uint256 public constant STARTING_BALANCE = 10000 ether;
    uint256 public constant TOTAL_REFUND_BONUS = 10 ether;
    uint256 public constant CYCLE_TARGET = 1300 ether;
    uint256 public constant MIN_PLEDGE_AMOUNT = 45 ether;
    uint256 public constant CYCLE_DURATION = 20 days;
    bytes32 constant campaignManagerRole = keccak256("CAMPAIGN_MANAGER_ROLE");
    uint256 rateOfDecay = 0.99e18;

    // DAC Variables
    uint256 public projectID = 5;
    uint256 public cycleExpiryDate; // Timestamp of 1728001, since block.timestamp starts at 1

    // Events
    event RefundBonusDeposited(address _campaignManager, uint256 indexed _totalRefundBonus);
    event PledgeMade(address, uint256);
    event CycleHasClosed(bool indexed, bool indexed);
    event CycleRefundBonusWithdrawal(address indexed, uint256 indexed);
    event CreatorWithdrawal(address, uint256);
    event Test(string, uint256); // Will remove before audit.

    function setUp() external {
        vm.deal(campaignManager, STARTING_BALANCE);
        vm.deal(admin, STARTING_BALANCE);
        vm.deal(pledger1, STARTING_BALANCE);
        vm.deal(pledger2, STARTING_BALANCE);
        vm.deal(pledger3, STARTING_BALANCE);
        vm.deal(rando, STARTING_BALANCE);
        vm.deal(address(ethPaymentTerminal), STARTING_BALANCE);

        vm.etch(address(controller), "I'm the operator with my pocket calculator");
        vm.etch(address(directory), "I'm the operator with my pocket calculator");
        vm.etch(address(fundAccessConstraintsStore), "I'm the operator with my pocket calculator");
        vm.etch(address(paymentTerminalStore), "I'm the operator with my pocket calculator");
        vm.etch(address(ethPaymentTerminal), "I'm the operator with my pocket calculator");

        // Deploy the target contract.
        mockExternalCallsForConstructor();
        vm.startPrank(admin);
        dominantJuice = new DominantJuice(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);

        // Get cycleExpiryDate for use in tests
        DominantJuice.Campaign memory campaign = dominantJuice.getCampaignInfo();
        cycleExpiryDate = campaign.cycleExpiryDate;

        // Adming grants Campaign Manager role
        dominantJuice.grantRole(campaignManagerRole, campaignManager);
        vm.stopPrank();
    }

    /**
     * List of Helper Functions (Helper section is at end of this contract body):
     * - mockExternalCallsForConstructor(): mocks all external calls needed in the constructor
     * - bonusDeposited(): pranks the campaign manager to deposit refund bonus into contract
     * - payParamsDataStruct(): creates memory struct for payParams() calls with base value as 100 ether.
     * - didPayDataStruct(): creates memory struct for didPay() calls with base value as 100 ether.
     * - pledge(): makes a pledge via the JB payment terminal to the contract instance in setUp() for
     * the input pledger with the input amount.
     * - dominantJuiceTesterSetup(): deploys a tester instance of dominantJuice with a delayed start.
     * Refund bonus is also deposited. This additional contract instance exposes the target contract's
     * internal _getPledgerAndTotalWeights().
     * - pledgeToTester(): makes a pledge to the local contract instance for the input pledger with the input amount.
     * - successfulCycleHasExpired(): Mocks 3 pledgers pledging over target amount and advances time past cycleExpiryDate
     * - failedCycleHasExpired(): Mocks 3 pledgers pledging under target amount and advances time past cycleExpiryDate
     * - redeemParamsDataStruct(): creates memory struct with projectID for redeemParams() calls for the input pledger.
     * - didRedeemDataStruct(): creates memory struct with projectID for didRedeem() calls for the input pledger.
     * - redeem(): sends a redemption through payment Terminal for the input pledger/redeemer.
     */

    ///////////////////////////////////////
    // Constructor and Grant Role Tests
    ///////////////////////////////////////

    // PASSING
    function test_constructor_storesAllVariablesAndContracts() public {
        mockExternalCallsForConstructor();

        DominantJuiceTestHelper dominantJuice_constructorTest =
            new DominantJuiceTestHelper(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);

        DominantJuice.Campaign memory campaign = dominantJuice_constructorTest.getCampaignInfo();
        uint256 projectId = campaign.projectId;
        uint256 cycleTarget = campaign.cycleTarget;
        uint256 startDate = campaign.cycleStart;
        uint256 expiryDate = campaign.cycleExpiryDate;
        uint256 minimumPledgeAmount = campaign.minimumPledgeAmount;
        uint256 totalRefundBonus = campaign.totalRefundBonus;
        uint256 startingDate = _cycle.start;
        uint256 endDate = _cycle.start + _cycle.duration;

        DominantJuice.JBContracts memory contracts = dominantJuice_constructorTest.exposed_getJBContracts();

        assertEq(projectID, projectId);
        assertEq(CYCLE_TARGET, cycleTarget);
        assertEq(startingDate, startDate);
        assertEq(endDate, expiryDate);
        assertEq(MIN_PLEDGE_AMOUNT, minimumPledgeAmount);
        assertEq(0, totalRefundBonus); // Since bonus has not been deposited yet.
        assertEq(address(controller), address(contracts.controller));
        assertEq(address(directory), address(contracts.directory));
        assertEq(address(fundAccessConstraintsStore), address(contracts.fundAccessConstraintsStore));
        assertEq(address(ethPaymentTerminal), address(contracts.paymentTerminal));
    }

    // PASSING
    function test_grantRole_assignsRoles() public {
        assertTrue(dominantJuice.hasRole(campaignManagerRole, campaignManager));
        assertTrue(dominantJuice.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    //////////////////////////////////
    // supportsInterface() Test
    //////////////////////////////////

    // PASSING
    function test_supportsInterface_supportsAllInheritedInterfaces() public {
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

        bool accessControlBool = dominantJuice.supportsInterface(type(IAccessControl).interfaceId);
        assertTrue(accessControlBool);

        bool IERC165Bool = dominantJuice.supportsInterface(type(IERC165).interfaceId);
        assertTrue(IERC165Bool);
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

    function testFuzz_depositRefundBonus_revertsWhenNoCalls(address _notManager) public {
        // Forge can't expectRevert() off partial error messages. Since address
        // would change each try, it is used here without a parameter.
        vm.assume(_notManager != campaignManager);

        vm.prank(_notManager);
        vm.expectRevert();
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();
    }

    // PASSING - Happy Path
    function testFuzz_depositRefundBonus_allowsManagerDepositAndEmitsEvent(uint256 _bonus) public {
        // assume realistic values
        _bonus = bound(_bonus, 1, 1000 ether);

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit RefundBonusDeposited(campaignManager, _bonus);

        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: _bonus}();

        assertEq(_bonus, dominantJuice.getBalance());
    }

    // PASSING
    function test_depositRefundBonus_revertsWhenCalledTwice() public {
        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();

        // Campaign Manager makes a second deposit.
        vm.prank(campaignManager);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.BonusAlreadyDeposited.selector, TOTAL_REFUND_BONUS));
        dominantJuice.depositRefundBonus{value: 20 ether}();

        assertEq(TOTAL_REFUND_BONUS, dominantJuice.getBalance());
    }

    /////////////////////////
    // payParams() Tests
    /////////////////////////

    // All payParams() tests use same JBPayParamsData struct with 100 ether as amount.value

    // PASSING
    function test_payParams_revertsIfCycleHasNotStarted() public {
        // Use a new deployment with a cycle start that is 2 days after "now."
        (DominantJuice dominantJuice_start,) = dominantJuiceTesterSetup();
        JBPayParamsData memory payParamsData = payParamsDataStruct();

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(paymentTerminalStore));
        vm.expectRevert(DominantJuice.CycleHasNotStarted.selector);
        dominantJuice_start.payParams(payParamsData);
    }

    // PASSING
    function testFuzz_payParams_revertsIfNoBonusDeposit(address _random) public {
        JBPayParamsData memory payParamsData = payParamsDataStruct();

        vm.prank(_random);
        vm.expectRevert(DominantJuice.RefundBonusNotDeposited.selector);
        dominantJuice.payParams(payParamsData);
    }

    // PASSING
    function test_payParams_revertsWhenCycleHasExpired() public {
        bonusDeposited();
        vm.warp(CYCLE_DURATION + 1);
        JBPayParamsData memory payParamsData = payParamsDataStruct();

        vm.prank(address(paymentTerminalStore));
        vm.expectRevert(DominantJuice.CycleHasExpired.selector);
        dominantJuice.payParams(payParamsData);
    }

    // PASSING - In reality, payParams() will be called by the JB Payment Terminal Store, but mocking a
    // direct call is a good check for unit testing purposes.
    function testFuzz_payParams_revertsWhenBelowMinPledge(uint256 _value) public {
        bonusDeposited();

        JBPayParamsData memory payParamsData = payParamsDataStruct();
        vm.assume(_value < MIN_PLEDGE_AMOUNT);
        payParamsData.amount.value = _value;

        vm.prank(rando);
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.AmountIsBelowMinimumPledge.selector, MIN_PLEDGE_AMOUNT));
        dominantJuice.payParams(payParamsData);
    }

    // PASSING - Happy Path
    function test_payParams_returnsMemoryVariables() public {
        bonusDeposited();

        JBPayParamsData memory payParamsData = payParamsDataStruct();
        payParamsData.payer = pledger1;
        payParamsData.memo = "juice";
        // value is an element in the amount variable's JBTokenAmount struct.
        payParamsData.amount.value = MIN_PLEDGE_AMOUNT;

        // Pledger1 calls payParams() directly.
        vm.prank(pledger1);
        (uint256 _weight, string memory _memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations) =
            dominantJuice.payParams(payParamsData);
        assertEq(payParamsData.weight, _weight);
        assertEq(payParamsData.memo, _memo);
        assertEq(0, delegateAllocations[0].amount);

        // Assert that there are no contract state changes when payParams() is called directly:
        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        assertEq(0, status.totalPledged);
        assertEq(0, status.percentOfGoal);
        assertFalse(status.isTargetMet);
        assertFalse(status.hasCycleExpired);
        assertEq(TOTAL_REFUND_BONUS, dominantJuice.getBalance());
    }

    // PASSING - Happy Path with JB Payment Terminal Store calling
    function test_payParams_executesUpToCycleClose() public {
        bonusDeposited();
        vm.warp(CYCLE_DURATION - 1);

        JBPayParamsData memory payParamsData = payParamsDataStruct();
        payParamsData.amount.value = MIN_PLEDGE_AMOUNT;
        payParamsData.weight = 1984;

        vm.prank(address(paymentTerminalStore));
        dominantJuice.payParams(payParamsData);

        // Extra confirm that call executes past time check.
        (uint256 _weight,,) = dominantJuice.payParams(payParamsData);
        assertEq(payParamsData.weight, _weight);
    }

    // payParams() function is non-payable, the parent function that calls it is nonReentrant, and
    // there are only statements and logic to satisfy Juicebox architecture, thus not many unit tests
    // here. This function can be called directly, but nothing would happen. The only way to pledge
    // correctly is by calling `JBPayoutRedemptionPaymentTerminal3_1_1.pay()`.

    ///////////////////////
    // didPay() Tests
    ///////////////////////

    // PASSING
    function testFuzz_didPay_revertsIfPaymentSent(uint256 _amount) public {
        bonusDeposited();
        _amount = bound(_amount, 1, STARTING_BALANCE);

        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);
        // Change value from base 100 ether to _amount
        didPayData.amount.value = _amount;

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(DominantJuice.PledgeThroughJuiceboxSiteOnly.selector);
        dominantJuice.didPay{value: _amount}(didPayData);
    }

    // PASSING
    function testFuzz_didPay_revertsIfNotPaymentTerminal(address _random) public {
        bonusDeposited();
        vm.assume(_random != address(ethPaymentTerminal));

        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(_random);

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
        vm.expectRevert(DominantJuice.CallerMustBeJBPaymentTerminal.selector);
        dominantJuice.didPay(didPayData);
    }

    function test_didPay_revertsIfCycleHasNotStarted() public {
        // Use a new deployment with a cycle start that is 2 days after "now."
        (DominantJuice dominantJuice_start,) = dominantJuiceTesterSetup();
        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(DominantJuice.CycleHasNotStarted.selector);
        dominantJuice_start.didPay(didPayData);
    }

    // PASSING
    function test_didPay_revertsIfNoBonusDeposit() public {
        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(DominantJuice.RefundBonusNotDeposited.selector);
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function test_didPay_revertsWhenCycleHasExpired() public {
        bonusDeposited();
        vm.warp(CYCLE_DURATION + 1);

        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(DominantJuice.CycleHasExpired.selector);
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function test_didPay_revertsWithEmptyDataStruct() public {
        bonusDeposited();
        JBDidPayData3_1_1 memory didPayData; // empty struct

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        // Call should revert when terminal calls with empty JBDidPayData struct (e.g. no project ID)
        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(DominantJuice.IncorrectProjectID.selector);
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function test_didPay_revertsOnWrongProjectId() public {
        bonusDeposited();

        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);
        didPayData.projectId = 50000; // not a correct projectId

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.IncorrectProjectID.selector));
        dominantJuice.didPay(didPayData);
    }

    // PASSING
    function testFuzz_didPay_revertsWhenBelowMinPledge(uint256 _value) public {
        bonusDeposited();

        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);
        vm.assume(_value < MIN_PLEDGE_AMOUNT);
        didPayData.amount.value = _value;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.AmountIsBelowMinimumPledge.selector, MIN_PLEDGE_AMOUNT));
        dominantJuice.didPay(didPayData);
    }

    // PASSING - Happy path
    function test_didPay_singlePledger_campaignUpdates() public {
        bonusDeposited();

        JBDidPayData3_1_1 memory didPayData = didPayDataStruct(pledger1);
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
        vm.expectCall(address(controller), abi.encodeCall(controller.currentFundingCycleOf, (projectID)));

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit PledgeMade(pledger1, MIN_PLEDGE_AMOUNT);

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didPay(didPayData);

        // Assert payment has no effect on contract funds.
        assertEq(TOTAL_REFUND_BONUS, dominantJuice.getBalance());

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        assertEq(MIN_PLEDGE_AMOUNT, status.totalPledged);
        uint256 percent = (100 * status.totalPledged) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal);
        assertEq(false, status.isTargetMet);
        assertEq(false, status.hasCycleExpired);
        assertEq(false, status.hasCreatorWithdrawnAllFunds);
    }

    // PASSING - Happy path
    function testFuzz_didPay_singlePledger(uint256 _value) public {
        bonusDeposited();

        _value = bound(_value, MIN_PLEDGE_AMOUNT, STARTING_BALANCE);
        // See Test Helpers section for mockCalls and didPay() call.
        pledge(pledger1, _value);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        assertEq(_value, status.totalPledged);
        uint256 percent = (100 * status.totalPledged) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal);
    }

    // PASSING
    function test_didPay_singlePledgerMultiplePledges_weights() public {
        (DominantJuiceTestHelper dominantJuice_singlePledger, JBFundingCycle memory cycleData) =
            dominantJuiceTesterSetup();

        vm.warp(2 days + 1);
        pledgeToTester(dominantJuice_singlePledger, cycleData, pledger1, 115 ether);

        (uint256 pledgerW1, uint256 totalW1) = dominantJuice_singlePledger.exposed_getPledgerAndTotalWeights(pledger1);

        vm.warp(1 weeks);
        // This pledge's weight should be much less than 1st pledge since made days later.
        pledgeToTester(dominantJuice_singlePledger, cycleData, pledger1, 115 ether);

        DominantJuice.FundingStatus memory status = dominantJuice_singlePledger.getCycleFundingStatus();

        (uint256 pledgerW2,) = dominantJuice_singlePledger.exposed_getPledgerAndTotalWeights(pledger1);

        assertEq(230 ether, status.totalPledged);
        uint256 percent = (100 * status.totalPledged) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal);
        assertEq(false, status.isTargetMet);
        assertEq(false, status.hasCycleExpired);
        assertEq(false, status.hasCreatorWithdrawnAllFunds);
        assertEq(pledgerW1, totalW1);
        assertGt(pledgerW2, pledgerW1);
        // assert that 1st pledge is greater than 2nd pledge, which is pledgerWeight after 2nd pledge minus 1st pledgeWeight
        assertGt(pledgerW1, pledgerW2 - pledgerW1);
    }

    // PASSING
    function test_didPay_twoPledgers_weights() public {
        // Deploy and use test harness for pledger weight testing
        (DominantJuiceTestHelper dominantJuice_twoPledgers, JBFundingCycle memory cycle) = dominantJuiceTesterSetup();

        // Pledger 1 pledges 100 ether at the 4th hour of the cycle.
        vm.warp(2 days + (4 * 60 * 60) + 1);
        uint256 hourOfPledge1 = (block.timestamp - cycle.start) / 3600;
        console.log(hourOfPledge1);

        JBDidPayData3_1_1 memory didPayData_p1 = didPayDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(cycle, _metadata)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice_twoPledgers.didPay(didPayData_p1);

        (uint256 pledger1W, uint256 totalW1) = dominantJuice_twoPledgers.exposed_getPledgerAndTotalWeights(pledger1);

        // Multiply 0.99 * 100 to avoid decimals. Then divide by the factored out 100^4 at end to get final result.
        uint256 timeFactor1 = 99 ** hourOfPledge1;
        uint256 calculatedWeight1 = timeFactor1 * 100 ether / (100 ** 4);
        console.log("calculatedWeight1", calculatedWeight1);

        assertEq(calculatedWeight1, pledger1W);

        // Pledger 2 pledges 100 ether at the 5th hour of the cycle.
        vm.warp(2 days + (5 * 60 * 60) + 1);
        uint256 hourOfPledge2 = (block.timestamp - cycle.start) / 3600;
        console.log(hourOfPledge2);

        JBDidPayData3_1_1 memory didPayData_p2 = didPayDataStruct(pledger2);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(cycle, _metadata)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice_twoPledgers.didPay(didPayData_p2);

        (uint256 pledger2W, uint256 totalW2) = dominantJuice_twoPledgers.exposed_getPledgerAndTotalWeights(pledger2);

        // Multiply 0.99 * 100 to avoid decimals. Then divide by the factored out 100^5 at end to get final result.
        uint256 timeFactor2 = 99 ** hourOfPledge2;
        uint256 calculatedWeight2 = timeFactor2 * 100 ether / (100 ** 5);
        console.log("calculatedWeight2", calculatedWeight2);

        console.log("pledger2W", pledger2W);
        console.log("totalW2", totalW2);
        assertEq(pledger2W, totalW2 - totalW1);
        assertGt(pledger1W, pledger2W);
    }

    // PASSING - Happy path
    function test_didPay_multiplePledgers_campaignUpdates() public {
        bonusDeposited();

        vm.warp(3600); // warp 1 hour
        pledge(pledger1, MIN_PLEDGE_AMOUNT);

        vm.warp(86400); // warp 1 day
        pledge(pledger2, MIN_PLEDGE_AMOUNT * 3);

        vm.warp(604800); // warp 1 week
        pledge(pledger3, MIN_PLEDGE_AMOUNT);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        assertEq(MIN_PLEDGE_AMOUNT * 5, status.totalPledged);
        uint256 percent = (100 * MIN_PLEDGE_AMOUNT * 5) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal);
        assertEq(false, status.isTargetMet);
    }

    // PASSING - Three pledgers pledge same amount at different times.
    function test_didPay_multiplePledgersSameAmountDiffTimes_weights() public {
        (DominantJuiceTestHelper dominantJuice_multipledger, JBFundingCycle memory cycleData) =
            dominantJuiceTesterSetup();

        vm.warp(2 days + 1);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger1, MIN_PLEDGE_AMOUNT);

        (uint256 pledger1W,) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger1);

        vm.warp(block.timestamp + 1 days);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger2, MIN_PLEDGE_AMOUNT);

        (uint256 pledger2W, uint256 totalW2) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger2);

        vm.warp(block.timestamp + 1 weeks);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger3, MIN_PLEDGE_AMOUNT);

        (uint256 pledger3W, uint256 totalW3) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger3);

        // Test weights with ABDKLibrary here once pow() value resutls are figured out?

        assertLt(pledger2W, pledger1W); // pledger2W is less since pledged later
        assertLt(pledger3W, pledger1W); // pledger3W is less since pledged much later
        assertEq(pledger1W + pledger2W, totalW2); // 1st and 2nd pledger weights equal total weight
        assertEq(pledger1W + pledger2W + pledger3W, totalW3); // All three pledges equal total weight
    }

    // PASSING - Two pledgers pledge same amount at same time. Third pledger pledges later.
    function test_didPay_simultaneousPledgersSameAmount_weights() public {
        (DominantJuiceTestHelper dominantJuice_multipledger, JBFundingCycle memory cycleData) =
            dominantJuiceTesterSetup();

        vm.warp(3 days);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger1, MIN_PLEDGE_AMOUNT);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger2, MIN_PLEDGE_AMOUNT);

        (uint256 pledger1W1,) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger1);
        (uint256 pledger2W,) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger2);

        vm.warp(block.timestamp + 3 days);

        pledgeToTester(dominantJuice_multipledger, cycleData, pledger3, MIN_PLEDGE_AMOUNT);

        (uint256 pledger3W,) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger3);
        (uint256 pledger1W2,) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger1);

        assertEq(pledger1W1, pledger2W); // Pledger 1 and pledger 2 should have same weight
        assertLt(pledger3W, pledger2W); // Pledger 3's weight should be less since pledged later
        assertEq(pledger1W1, pledger1W2); // Pledger 1's weight should not change from other pledgers pledge's.
    }

    // PASSING
    function testFuzz_didPay_simultaneousPledgersDiffAmounts(uint256 _pledger2Amount) public {
        (DominantJuiceTestHelper dominantJuice_multipledger, JBFundingCycle memory cycleData) =
            dominantJuiceTesterSetup();

        vm.warp(10 days);
        _pledger2Amount = bound(_pledger2Amount, 90 ether, 110 ether);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger2, _pledger2Amount);
        pledgeToTester(dominantJuice_multipledger, cycleData, pledger3, 100 ether);

        (uint256 pledger2W,) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger2);
        (uint256 pledger3W, uint256 totalW) = dominantJuice_multipledger.exposed_getPledgerAndTotalWeights(pledger3);

        if (_pledger2Amount < 100 ether) {
            assertLt(pledger2W, pledger3W);
        } else {
            assertGe(pledger2W, pledger3W);
        }

        assertEq(pledger2W + pledger3W, totalW); // total weight should always be sum of both weights
    }

    // PASSING - Pledge of campaign funding target is made at final second: 480 hours after start.
    // This will more than likely use the largest numbers that are run through the contract math logic.
    function test_didPay_noMathOverflow() public {
        bonusDeposited();
        vm.warp(20 days - 1); // 1 second before cycle close.
        pledge(pledger1, CYCLE_TARGET);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();

        assertEq(CYCLE_TARGET, status.totalPledged);
        uint256 percent = (100 * status.totalPledged) / CYCLE_TARGET;
        assertEq(percent, status.percentOfGoal);
        console.log(percent); // 100%
    }

    ////////////////////////////////
    // redeemParams() Tests
    ////////////////////////////////

    // PASSING
    function testFuzz_redeemParams_revertsDuringCycle(uint256 _seconds) public {
        bonusDeposited();
        JBRedeemParamsData memory redeemParamsData = redeemParamsDataStruct(pledger2);

        // Pledger2 pledges. Advance time but still be in cycle window.
        pledge(pledger2, 200 ether);
        vm.assume(_seconds < cycleExpiryDate - block.timestamp);
        vm.warp(_seconds);

        vm.prank(address(paymentTerminalStore));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, cycleExpiryDate));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfSuccessfulCycle() public {
        bonusDeposited();
        // See Test Helpers section for explanation of this function:
        successfulCycleHasExpired();
        JBRedeemParamsData memory redeemParamsData = redeemParamsDataStruct(pledger2);

        // Pledger calls to redeem.
        vm.prank(address(paymentTerminalStore));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.NoRefundsForSuccessfulCycle.selector));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfNotPledger() public {
        bonusDeposited();
        failedCycleHasExpired();

        vm.warp(cycleExpiryDate + 100);
        JBRedeemParamsData memory redeemParamsData = redeemParamsDataStruct(rando);

        vm.prank(rando); // direct call
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.MustBePledger.selector));
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING
    function test_redeemParams_revertsIfAlreadyWithdrawn() public {
        bonusDeposited();
        failedCycleHasExpired();
        JBRedeemParamsData memory redeemParamsData = redeemParamsDataStruct(pledger1);

        assertFalse(dominantJuice.getPledgerRefundStatus(pledger1));

        // Pledger1 calls redeem
        redeem(pledger1);

        assertTrue(dominantJuice.getPledgerRefundStatus(pledger1));

        vm.prank(address(paymentTerminalStore)); // 2nd call
        vm.expectRevert(DominantJuice.AlreadyWithdrawnRefund.selector);
        dominantJuice.redeemParams(redeemParamsData);
    }

    // PASSING - Happy Path
    function test_redeemParams_returnsMemoryVariables() public {
        bonusDeposited();
        failedCycleHasExpired();

        JBRedeemParamsData memory redeemParamsData = redeemParamsDataStruct(pledger1);
        redeemParamsData.reclaimAmount.value = 1;
        redeemParamsData.memo = "juice";

        vm.prank(address(paymentTerminalStore));
        (uint256 _reclaimAmount, string memory _memo, JBRedemptionDelegateAllocation3_1_1[] memory delegateAllocations)
        = dominantJuice.redeemParams(redeemParamsData);
        assertEq(redeemParamsData.reclaimAmount.value, _reclaimAmount);
        assertEq(redeemParamsData.memo, _memo);
        assertEq(0, delegateAllocations[0].amount);
    }

    //////////////////////////
    // didRedeem() Tests
    //////////////////////////

    // PASSING
    function testFuzz_didRedeem_revertsIfPaymentSent(uint256 _amount) public {
        bonusDeposited();
        failedCycleHasExpired();

        _amount = bound(_amount, 1, 2000 ether);
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger1);

        vm.prank(address(ethPaymentTerminal));
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.PledgeThroughJuiceboxSiteOnly.selector));
        dominantJuice.didRedeem{value: _amount}(didRedeemData);
    }

    // PASSING
    function testFuzz_didRedeem_revertsIfNotPaymentTerminal(address _random) public {
        bonusDeposited();
        failedCycleHasExpired();

        vm.assume(_random != address(ethPaymentTerminal));
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(_random);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(_random))),
            abi.encode(false)
        );
        vm.expectCall(
            address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, IJBPaymentTerminal(_random)))
        );

        vm.prank(_random); // non-paymentTerminal calling
        vm.expectRevert(abi.encodeWithSelector(DominantJuice.CallerMustBeJBPaymentTerminal.selector));
        dominantJuice.didRedeem(didRedeemData);
    }

    // PASSING
    function testFuzz_didRedeem_revertsDuringCycle(uint256 _seconds) public {
        bonusDeposited();
        // pledger3 pledges. Advance time but still be in cycle window.
        pledge(pledger3, 200 ether);

        vm.assume(_seconds < cycleExpiryDate - block.timestamp);
        vm.warp(_seconds);
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger3);

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
    function test_didRedeem_revertsIfSuccessfulCycle() public {
        bonusDeposited();
        successfulCycleHasExpired();
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger2);

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
    function testFuzz_didRedeem_revertsOnWrongProjectId(uint256 _projectID) public {
        bonusDeposited();
        failedCycleHasExpired();

        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger2);
        vm.assume(_projectID != projectID);
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

    // PASSING - Test in case Juicebox architecture goes wonky.
    function test_didRedeem_revertsIfNotPledger() public {
        bonusDeposited();
        failedCycleHasExpired();

        // Insert non-pledging address in data struct
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(rando);

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
    function test_didRedeem_revertsIfAlreadyWithdrawn() public {
        bonusDeposited();
        failedCycleHasExpired();
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger1);

        // Pledger1 redeems through JB
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
    function test_didRedeem_revertsIfFailedToSendEther() public {
        bonusDeposited();

        // Deploy tester contract to act as a pledger/redeemer. Pledge to main contract instance. Advance
        // time and call didRedeem() on main contract with tester as pledger/holder, which should revert since
        // tester contract does not have fallback or receive functions.
        DominantJuiceTestHelper dominantJuice_sender =
            new DominantJuiceTestHelper(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);
        pledge(address(dominantJuice_sender), 45 ether);
        vm.warp(cycleExpiryDate);

        vm.expectRevert("Failed to send refund bonus.");
        redeem(address(dominantJuice_sender));
    }

    // PASSING
    function test_didRedeem_happyPath() public {
        bonusDeposited();
        pledge(pledger1, MIN_PLEDGE_AMOUNT);
        vm.warp(cycleExpiryDate + 100);
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.expectCall(address(directory), abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)));

        // If only one pledger, they should get the entire refund bonus
        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit CycleRefundBonusWithdrawal(pledger1, TOTAL_REFUND_BONUS);

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData);

        assertEq(true, dominantJuice.getPledgerRefundStatus(pledger1));
        assertEq(0, dominantJuice.getBalance());
        // The unit test shouldn't cover outside state, but this was just an additional sanity assert.
        // Since pledger1 pays through the JB architecture, it doesn't subtract from pledger1's balance.
        assertEq(STARTING_BALANCE + TOTAL_REFUND_BONUS, pledger1.balance);
    }

    // PASSING
    function testFuzz_didRedeem_amountsUpToCycleTarget(uint256 _pledgeAmount) public {
        bonusDeposited();

        // Pledger1 pledges up to and excluding cycleTarget amount and time advances past expiry date.
        _pledgeAmount = bound(_pledgeAmount, MIN_PLEDGE_AMOUNT, CYCLE_TARGET - 1);
        pledge(pledger1, _pledgeAmount);
        vm.warp(cycleExpiryDate + 100);
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData);

        assertTrue(dominantJuice.getPledgerRefundStatus(pledger1));
        assertEq(0, dominantJuice.getBalance());
        assertFalse(dominantJuice.isTargetMet());
    }

    // PASSING
    function test_didRedeem_simultaneousPledgersSameAmount() public {
        bonusDeposited();

        vm.warp(4 days); // Two pledges "at same time"
        pledge(pledger1, 100 ether);
        pledge(pledger2, 100 ether);

        vm.warp(cycleExpiryDate + 100); // Cycle expires
        JBDidRedeemData3_1_1 memory didRedeemData_p1 = didRedeemDataStruct(pledger1);
        JBDidRedeemData3_1_1 memory didRedeemData_p2 = didRedeemDataStruct(pledger2);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p1);

        // Should withdraw same refund bonus amount.
        uint256 pledger1RefundBonus = TOTAL_REFUND_BONUS / 2;
        assertEq(pledger1RefundBonus, dominantJuice.getBalance());

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p2);

        assertEq(0, dominantJuice.getBalance());
        // Extra assert. Pledger 2 should have original balance plus share of refund bonus.
        uint256 pledger2RefundBonus = TOTAL_REFUND_BONUS / 2;
        assertEq(STARTING_BALANCE + pledger2RefundBonus, pledger2.balance);
    }

    // PASSING
    function test_didRedeem_multiplePledgers_OnePledgerMultiplePledges() public {
        bonusDeposited();

        pledge(pledger1, 100 ether);
        pledge(pledger2, 200 ether);
        pledge(pledger1, 200 ether);

        vm.warp(cycleExpiryDate + 100);
        JBDidRedeemData3_1_1 memory didRedeemData = didRedeemDataStruct(pledger1);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData);

        assertTrue(dominantJuice.getPledgerRefundStatus(pledger1));
        // Since pledger 1 has pledged 3/5ths of the ether at same time, pledger 1 should
        // receive 3/5ths of the bonus. So 2/5ths of the bonus is left: (2/5) * 10 ether = 4 ether.
        assertEq(4 ether, dominantJuice.getBalance());
    }

    // PASSING
    function test_didRedeem_multiplePledgersSameAmountDiffTimes() public {
        bonusDeposited();

        pledge(pledger1, 100 ether);
        vm.warp(4 days);
        pledge(pledger2, 100 ether);

        vm.warp(cycleExpiryDate + 100);
        JBDidRedeemData3_1_1 memory didRedeemData_p1 = didRedeemDataStruct(pledger1);
        JBDidRedeemData3_1_1 memory didRedeemData_p2 = didRedeemDataStruct(pledger2);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p1);

        // Funds withdrawn are pledger 1's refund bonus.
        uint256 pledger1RefundBonus = TOTAL_REFUND_BONUS - dominantJuice.getBalance();

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p2);

        uint256 pledger2RefundBonus = TOTAL_REFUND_BONUS - pledger1RefundBonus;

        // Pledger 1 should redeem a bunch more than pledger 2
        assertGt(pledger1RefundBonus, pledger2RefundBonus);
    }

    // PASSING
    function test_didRedeem_simultaneousPledgersDiffAmounts() public {
        bonusDeposited();

        vm.warp(4 days);
        pledge(pledger1, 100 ether);
        pledge(pledger2, 300 ether);

        vm.warp(cycleExpiryDate + 100);
        JBDidRedeemData3_1_1 memory didRedeemData_p1 = didRedeemDataStruct(pledger1);
        JBDidRedeemData3_1_1 memory didRedeemData_p2 = didRedeemDataStruct(pledger2);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p1);

        // Since pledger 1's pledge is 1/4 of total pledges, should withdraw 1/4th of totalRefundBonus = 2.5 ETH
        assertEq(7.5 ether, dominantJuice.getBalance());

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p2);

        // Extra assert. Pledger 2 should get original pledge plus 7.5 ETH
        assertEq(STARTING_BALANCE + 7.5 ether, pledger2.balance);
    }

    // PASSING
    function testFuzz_didRedeem_multiplePledgersDiffTimes(uint256 _pledger3Amount) public {
        bonusDeposited();
        // Pledger2 pledges half the CYCLE_TARGET in first hour.
        pledge(pledger2, MIN_PLEDGE_AMOUNT);

        // 0.99 ^ 140 = ~0.244, so at the 140th hour, pledger3 can pledge any amount between
        // MIN_PLEDGE_AMOUNT and MIN_PLEDGE_AMOUNT * 4, and pledger2 will always have more weight
        // and should always get a bigger refund bonus.
        vm.warp((140 * 60 * 60) + 1); // 140 hours of seconds
        _pledger3Amount = bound(_pledger3Amount, MIN_PLEDGE_AMOUNT, (MIN_PLEDGE_AMOUNT * 4));
        pledge(pledger3, _pledger3Amount);

        vm.warp(cycleExpiryDate + 100);
        JBDidRedeemData3_1_1 memory didRedeemData_p2 = didRedeemDataStruct(pledger2);
        JBDidRedeemData3_1_1 memory didRedeemData_p3 = didRedeemDataStruct(pledger3);

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p2);

        uint256 pledger2Bonus = TOTAL_REFUND_BONUS - dominantJuice.getBalance();
        uint256 pledger3Bonus = TOTAL_REFUND_BONUS - pledger2Bonus;

        assertGt(pledger2Bonus, pledger3Bonus);

        vm.prank(address(ethPaymentTerminal));
        dominantJuice.didRedeem(didRedeemData_p3);

        // Extra assert using pledger 3 funds.
        assertApproxEqAbs(STARTING_BALANCE + pledger3Bonus, pledger3.balance, 10); // 10 wei precision error
    }

    //////////////////////////////
    // creatorWithdraw() Tests
    //////////////////////////////

    // PASSING
    function test_creatorWithdraw_revertsForNonOwner() public {
        bonusDeposited();
        successfulCycleHasExpired();

        vm.prank(rando);
        vm.expectRevert(
            "AccessControl: account 0x8e24d86be44ab9006bd1277bddc948ecebbfbf6c is missing role 0x5022544358ee0bece556b72ae8983c7f24341bd5b9483ce8a19bff5efbb2de92"
        );
        dominantJuice.creatorWithdraw(rando, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function test_creatorWithdraw_revertsBeforeUnlock() public {
        bonusDeposited();

        uint256 lockPeriod = 14 * 24 * 60 * 60;
        vm.warp(cycleExpiryDate + lockPeriod); // This is one second before lockPeriod is over.

        vm.prank(campaignManager);
        vm.expectRevert("Cycle must be expired and successful, or it must be past the lock period.");
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function test_creatorWithdraw_revertsIfGoalNotMet() public {
        bonusDeposited();
        failedCycleHasExpired();

        vm.prank(campaignManager);
        vm.expectRevert("Cycle must be expired and successful, or it must be past the lock period.");
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);
    }

    // PASSING
    function testFuzz_creatorWithdraw_revertsOnOverdraw(uint256 _amount) public {
        bonusDeposited();
        successfulCycleHasExpired();

        vm.assume(_amount > dominantJuice.getBalance());

        vm.prank(campaignManager);
        vm.expectRevert(DominantJuice.InsufficientFunds.selector);
        dominantJuice.creatorWithdraw(campaignManager, _amount);
    }

    // PASSING
    function test_creatorWithdraw_revertsIfFailedToSendEther() public {
        // Deploy contract and grant it campaign manager role. Mock a successful cycle and advance time.
        // creatorWithdraw() should revert since contract does not have fallback or receive functions.
        DominantJuiceTestHelper dominantJuice_manager =
            new DominantJuiceTestHelper(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);

        vm.prank(admin);
        dominantJuice.grantRole(campaignManagerRole, address(dominantJuice_manager));

        bonusDeposited();
        successfulCycleHasExpired();

        address payable managerContract = payable(address(dominantJuice_manager));
        vm.prank(managerContract);
        vm.expectRevert("Failed to withdraw cycle funds.");
        dominantJuice.creatorWithdraw(managerContract, TOTAL_REFUND_BONUS);
    }

    // PASSING - Happy Path
    function test_creatorWithdraw_withdrawsBonus() public {
        bonusDeposited();
        successfulCycleHasExpired();

        assertTrue(dominantJuice.isTargetMet());

        vm.expectEmit(true, true, true, true, address(dominantJuice));
        emit CreatorWithdrawal(campaignManager, TOTAL_REFUND_BONUS);

        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();
        assertEq(true, status.hasCreatorWithdrawnAllFunds);
        assertEq(0, dominantJuice.getBalance());
        assertEq(STARTING_BALANCE, campaignManager.balance);
    }

    // PASSING - Happy Path
    function test_creatorWithdraw_sendsFundsToDifferentAddress() public {
        bonusDeposited();
        successfulCycleHasExpired();

        vm.prank(campaignManager);
        dominantJuice.creatorWithdraw(rando, TOTAL_REFUND_BONUS);

        assertEq(0, dominantJuice.getBalance());
        assertEq(STARTING_BALANCE + TOTAL_REFUND_BONUS, rando.balance);
    }

    // PASSING
    function testFuzz_creatorWithdraw_withdrawsInTwoTransactions(uint256 _amount) public {
        vm.assume(_amount < TOTAL_REFUND_BONUS);
        bonusDeposited();
        successfulCycleHasExpired();

        vm.startPrank(campaignManager);
        dominantJuice.creatorWithdraw(pledger1, _amount);

        assertEq(TOTAL_REFUND_BONUS - _amount, dominantJuice.getBalance());

        dominantJuice.creatorWithdraw(campaignManager, TOTAL_REFUND_BONUS - _amount);
        vm.stopPrank();

        assertEq(0, dominantJuice.getBalance());
    }

    // PASSING - Happy Path
    function testFuzz_creatorWithdraw_creatorCanCallAfterUnlock(uint256 _seconds) public {
        bonusDeposited();
        failedCycleHasExpired();

        uint256 lockPeriod = 14 * 24 * 60 * 60;
        vm.assume(_seconds > cycleExpiryDate + lockPeriod);
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
    function test_getBalance() public {
        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: 126 ether}();

        uint256 balance = dominantJuice.getBalance();
        assertEq(balance, 126 ether);
    }

    // PASSING
    function test_isTargetMet_tracksTotalPledgesCorrectly() public {
        bonusDeposited(); // CYCLE_TARGET == 1300 ether
        pledge(pledger1, 1299 ether);

        bool isMet = dominantJuice.isTargetMet();
        assertEq(isMet, false);

        // Pledger 2 pledges min amount to meet goal
        pledge(pledger2, 45 ether);

        bool isTargetMet = dominantJuice.isTargetMet();
        assertEq(isTargetMet, true);
    }

    // PASSING
    function test_hasCycleExpired() public {
        vm.warp(cycleExpiryDate - 60);
        assertFalse(dominantJuice.hasCycleExpired());

        vm.warp(cycleExpiryDate + 60);
        assertTrue(dominantJuice.hasCycleExpired());
    }

    // PASSING
    function testFuzz_getCycleFundingStatus_tracksPledgeAmounts(uint256 _amount) public {
        bonusDeposited();

        _amount = bound(_amount, MIN_PLEDGE_AMOUNT, CYCLE_TARGET - 1);
        pledge(pledger1, _amount);

        DominantJuice.FundingStatus memory status = dominantJuice.getCycleFundingStatus();
        DominantJuice.Campaign memory campaign = dominantJuice.getCampaignInfo();

        assertEq(_amount, status.totalPledged);
        uint256 calculatedPercent = ((100 * _amount) / campaign.cycleTarget);
        assertEq(calculatedPercent, status.percentOfGoal);
        assertEq(false, status.isTargetMet);
    }

    // PASSING
    function test_getCycleFundingStatus_FullCreatorWithdrawal() public {
        bonusDeposited();
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
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1); // Default empty
        _terminals[0] = ethPaymentTerminal;

        // Mock return struct values from controller.currentFundingCycleOf() call with test temporal values.
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

    function bonusDeposited() public {
        vm.prank(campaignManager);
        dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}();
    }

    function payParamsDataStruct() public pure returns (JBPayParamsData memory) {
        JBPayParamsData memory payParams;
        payParams.amount.value = 100 ether;
        payParams.weight = 1984;

        return payParams;
    }

    function didPayDataStruct(address _payer) public view returns (JBDidPayData3_1_1 memory) {
        JBDidPayData3_1_1 memory didPayData;
        didPayData.payer = _payer;
        didPayData.projectId = projectID;
        didPayData.amount.value = 100 ether;

        return didPayData;
    }

    function pledge(address _pledger, uint256 _value) public {
        JBDidPayData3_1_1 memory didPayData_pledger;
        didPayData_pledger.projectId = projectID;
        didPayData_pledger.payer = _pledger;
        didPayData_pledger.amount.value = _value;

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

    function dominantJuiceTesterSetup() public returns (DominantJuiceTestHelper, JBFundingCycle memory) {
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1); // Default empty
        _terminals[0] = ethPaymentTerminal;
        JBFundingCycle memory _fundingCycle;

        // Mock return struct values from the controller.currentFundingCycleOf() call with the test temporal values.
        _fundingCycle.start = block.timestamp + 2 days;
        _fundingCycle.duration = CYCLE_DURATION;

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
            abi.encode(_fundingCycle, _metadata)
        );

        vm.startPrank(admin);
        DominantJuiceTestHelper dominantJuice_pledge =
            new DominantJuiceTestHelper(projectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, controller, paymentTerminalStore);
        dominantJuice_pledge.grantRole(campaignManagerRole, campaignManager);
        vm.stopPrank();
        vm.prank(campaignManager);
        dominantJuice_pledge.depositRefundBonus{value: TOTAL_REFUND_BONUS}();

        return (dominantJuice_pledge, _fundingCycle);
    }

    function pledgeToTester(
        DominantJuiceTestHelper _tester,
        JBFundingCycle memory _cycleData,
        address _pledger,
        uint256 _value
    ) public {
        JBFundingCycleMetadata memory metadata;
        JBDidPayData3_1_1 memory didPayData_pledger;
        didPayData_pledger.projectId = projectID;
        didPayData_pledger.payer = _pledger;
        didPayData_pledger.amount.value = _value;

        vm.mockCall(
            address(directory),
            abi.encodeCall(directory.isTerminalOf, (projectID, ethPaymentTerminal)),
            abi.encode(true)
        );
        vm.mockCall(
            address(controller),
            abi.encodeCall(controller.currentFundingCycleOf, (projectID)),
            abi.encode(_cycleData, metadata)
        );

        vm.prank(address(ethPaymentTerminal));
        _tester.didPay(didPayData_pledger);
        vm.clearMockedCalls();
    }

    // Use ABDKMath library to test pledgerWeight and confirm PRBMath library's results.
    // Currently can't get pow() to return correct values or not revert.
    // function pledgeWeightCalculator_ABDK(uint256 _amount, uint256 _time) public returns (uint256) {
    //     int128 rate = ABDKMath64x64.divu(99, 100);
    //     //int128 rate = ABDKMath64x64.fromUInt(rateOfDecay);
    //     //int128 rate = ABDKMath64x64.fromUInt(20);
    //     emit Test("fff", 0);
    //     uint256 tempAmount = _amount / 1e6;

    //     int128 weightFactor = ABDKMath64x64.pow(rate, _time);
    //     console.log("weightFactor", ABDKMath64x64.toUInt(weightFactor));
    //     emit Test("1", 0);
    //     int128 pledgeAmount = ABDKMath64x64.fromUInt(tempAmount);
    //     console.log("pledgeAmount", ABDKMath64x64.toUInt(pledgeAmount));
    //     emit Test("2", 0);
    //     int128 pledgeWeight64x64 = ABDKMath64x64.mul(weightFactor, pledgeAmount);
    //     uint64 pledgeWeightTemp = ABDKMath64x64.toUInt(pledgeWeight64x64);
    //     console.log("pledgeWeightTemp", pledgeWeightTemp);
    //     uint256 pledgeWeight = uint256(pledgeWeightTemp) * 1e6;
    //     console.log("pledgeWeightFinal", pledgeWeight);

    //     return pledgeWeight;
    // }

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

    function redeemParamsDataStruct(address _holder) public view returns (JBRedeemParamsData memory) {
        JBRedeemParamsData memory redeemParams;
        redeemParams.holder = _holder;
        redeemParams.projectId = projectID;

        return redeemParams;
    }

    function didRedeemDataStruct(address _holder) public view returns (JBDidRedeemData3_1_1 memory) {
        JBDidRedeemData3_1_1 memory didRedeemData;
        didRedeemData.holder = _holder;
        didRedeemData.projectId = projectID;

        return didRedeemData;
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

contract DominantJuiceTestHelper is DominantJuice, Test {
    constructor(
        uint256 _projectId,
        uint256 _cycleTarget,
        uint256 _minimumPledgeAmount,
        IJBController3_1 _controller,
        IJBSingleTokenPaymentTerminalStore3_1_1 _paymentTerminalStore
    ) DominantJuice(_projectId, _cycleTarget, _minimumPledgeAmount, _controller, _paymentTerminalStore) {}

    function setup() external {
        vm.deal(address(this), 100 ether);
    }

    function exposed_getPledgerAndTotalWeights(address _pledger) external view returns (uint256, uint256) {
        return _getPledgerAndTotalWeights(_pledger);
    }

    function exposed_getJBContracts() external view returns (JBContracts memory) {
        return _getJBContracts();
    }
}
