// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {DelegateProjectDeployer} from "../../src/DelegateProjectDeployer.sol";
import {DominantJuice} from "../../src/DominantJuice.sol";
import {DeployDeployer} from "../../script/DeployDeployer.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBSingleTokenPaymentTerminal} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol";
import {JBDidPayData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData3_1_1.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";

// Data struct imports for launchProjectFor():
import {JBProjectMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBProjectMetadata.sol";
import {JBFundingCycleData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleData.sol";
import {JBFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBGroupedSplits} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGroupedSplits.sol";
import {JBTokenAmount} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol";
import {JBFundAccessConstraints} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundAccessConstraints.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBGlobalFundingCycleMetadata.sol";

// All 41 tests passing on forked url. No mocks, so "forge test" on local Anvil network does not work.
// Run "forge test --fork-url $GOERLI_RPC_URL --fork-block-number 9289741 -vvv". Juicebox upgraded their contracts
// to v3-1-1 in the middle of this project. To be safe, use 9289741 or after for the block number.

contract DominantJuiceTest_Unit is Test {
    // Contracts and Structs for JB functions: launchProjectFor(), pay(), redeemTokensOf()
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleMetadata _metadata;
    JBFundingCycleMetadata _metadataFailedCampaign;
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty

    // JB Architecture contracts
    IJBController3_1 public controller;
    IJBDirectory public directory;
    IJBOperatorStore public operatorStore;
    IJBSingleTokenPaymentTerminalStore3_1_1 public paymentTerminalStore3_1_1;
    JBETHPaymentTerminal3_1_1 public ethPaymentTerminal3_1_1;

    DelegateProjectDeployer delegateProjectDeployer;
    DominantJuice dominantJuice;

    // Dominant Assurance variables and constants
    address payable owner;
    address payable public earlyPledger1 = payable(makeAddr("earlyPledger1"));
    address payable public earlyPledger2 = payable(makeAddr("earlyPledger2"));
    address payable public pledger = payable(makeAddr("pledger"));
    uint256 public successfulProjectID;
    uint256 public failedProjectID;
    uint256 public constant STARTING_USER_BALANCE = 1 ether; // 1e18 wei
    uint256 public constant TOTAL_REFUND_BONUS = 10000 gwei; // 0.00001 ether, 1e13 wei
    uint256 public constant CYCLE_TARGET = 100000 gwei; // 0.0001 ether, 1e14 wei
    uint256 public constant CYCLE_DURATION = 20 days;
    uint256 public constant MIN_PLEDGE_AMOUNT = 1000 gwei; // 0.000001 ether, 1e12 wei
    uint256 public cycleExpiryDate;
    uint32 public constant MAX_EARLY_PLEDGERS = 2;
    address public ETH_TOKEN = 0x000000000000000000000000000000000000EEEe;

    // Events
    event RefundBonusDeposited(address owner, uint256 indexed totalRefundBonus);
    event CycleHasClosed(bool indexed, bool indexed);
    event CycleRefundBonusWithdrawal(address indexed, uint256 indexed);
    event OwnerWithdrawal(address, uint256);

    function setUp() external {
        DeployDeployer deployDeployer = new DeployDeployer();
        (controller, operatorStore, paymentTerminalStore3_1_1, ethPaymentTerminal3_1_1, delegateProjectDeployer) =
            deployDeployer.run();
        directory = controller.directory();
        owner = payable(dominantJuice.owner());
        vm.deal(owner, STARTING_USER_BALANCE);
        vm.deal(earlyPledger1, STARTING_USER_BALANCE);
        vm.deal(earlyPledger2, STARTING_USER_BALANCE);
        vm.deal(pledger, STARTING_USER_BALANCE);

        // JB Project Launch variables:
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _data = JBFundingCycleData({
            duration: CYCLE_DURATION,
            weight: 1000000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
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

        // Reconfiguring cycle 2 to allow redemptions for failed campaign.
        _metadataFailedCampaign = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false, pauseTransfers: true}),
            reservedRate: 0, // 0%
            redemptionRate: 100, // 0% in cycle 1. If failed campaign, change to 100% for cycle 2.
            ballotRedemptionRate: 0,
            pausePay: false, // Change to true for cycle 2
            pauseDistributions: true, // if successful cycle, change to false for cycle 2.
            pauseRedeem: false, // if failed cycle, change to false in cycle 2
            pauseBurn: false, // if failed cycle, change to false in cycle 2
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: true,
            useDataSourceForRedeem: true, // if failed campaign, must be changed to true in cycle 2
            dataSource: address(dominantJuice),
            metadata: 0
        });

        _terminals.push(ethPaymentTerminal3_1_1);

        successfulProjectID = controller.launchProjectFor(
            msg.sender,
            _projectMetadata,
            _data,
            _metadata,
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        failedProjectID = controller.launchProjectFor(
            msg.sender,
            _projectMetadata,
            _data,
            _metadata,
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );
    }

    // function testJBFunctionsWithExistingProject() public {
    //     (JBFundingCycle memory data,) = controller.currentFundingCycleOf(PROJECT_1_ID);
    //     assertEq(data.duration, 86400);

    //     uint256 overflow = paymentTerminalStore.currentOverflowOf(goerliETHTerminal3_1, PROJECT_1_ID);
    //     assertEq(overflow, 1e14);
    // }

    // function testProjectLaunch() public {
    //     (JBFundingCycle memory fundingCycle,) = controller.currentFundingCycleOf(successfulProjectID);
    //     uint256 rate = fundingCycle.discountRate;
    //     assertEq(rate, 0);
    // }

    ///////////////////////////////////
    // initialize() Tests //
    //////////////////////////////////

    // Does not let anyone else but owner call
    // function testInitializeRevertsWithNonOwner() public {
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     dominantJuice.initialize(successfulProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    // }

    // // populates correct cycleExpiry and cycleTarget info.
    // function testInitializeStoresCycleVariables() public {
    //     vm.prank(owner);
    //     dominantJuice.initialize(successfulProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    //     uint256 cycleEnd = dominantJuice.cycleExpiryDate();
    //     (JBFundingCycle memory projectCycleData,) = controller.currentFundingCycleOf(successfulProjectID);
    //     uint256 endDate = projectCycleData.start + CYCLE_DURATION;
    //     assertEq(cycleEnd, endDate);
    //     uint256 target = dominantJuice.cycleTarget();
    //     assertEq(target, CYCLE_TARGET);
    // }

    // // Correctly stores min Pledge and max early pledger variables.
    // function testInitializeStoresPledgerVariables() public {
    //     vm.prank(owner);
    //     dominantJuice.initialize(successfulProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    //     assertEq(dominantJuice.minimumPledgeAmount(), MIN_PLEDGE_AMOUNT);
    //     assertEq(dominantJuice.maxEarlyPledgers(), MAX_EARLY_PLEDGERS);
    // }

    // // does not let owner call function twice
    // function testInitializingTwice() public {
    //     vm.startPrank(owner);
    //     dominantJuice.initialize(successfulProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    //     vm.expectRevert();
    //     dominantJuice.initialize(5, 1e14, 3e18, 20);
    //     vm.stopPrank();
    // }

    // ///////////////////////////////////
    // // depositRefundBonus() Tests //
    // //////////////////////////////////

    // // reverts if initialize() has not been called yet
    // function testDepositRevertsBeforeInitialization() public {
    //     vm.prank(owner);
    //     vm.expectRevert(DominantJuice.DataSourceNotInitialized.selector);
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    // }

    // // reverts if msg.value does not equal input
    // function testDepositAndInputMisMatch() public {
    //     vm.startPrank(owner);
    //     dominantJuice.initialize(5, 1e14, 3e18, 20);
    //     vm.expectRevert();
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(MIN_PLEDGE_AMOUNT);
    //     vm.stopPrank();
    // }

    // // reverts if not owner
    // function testDepositRevertsWithNonOwner() public {
    //     vm.prank(owner);
    //     dominantJuice.initialize(5, 1e14, 3e18, 20);
    //     vm.expectRevert();
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    // }

    // // allows owner to deposit correct refund bonus
    // function testDepositByOwner() public {
    //     vm.startPrank(owner);
    //     dominantJuice.initialize(5, 1e14, 3e18, 20);
    //     dominantJuice.depositRefundBonus{value: 2}(2);
    //     vm.stopPrank();
    //     uint256 balance = dominantJuice.getBalance();
    //     assertEq(balance, 2);
    // }

    // // emits a RefundBonusDeposited event
    // function testDepositEmitsEvent() public {
    //     vm.startPrank(owner);
    //     dominantJuice.initialize(successfulProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    //     vm.expectEmit(false, true, false, false, address(dominantJuice));
    //     emit RefundBonusDeposited(owner, TOTAL_REFUND_BONUS);
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    //     vm.stopPrank();
    // }

    // ///////////////////////////////////
    // // payParams() Tests //
    // //////////////////////////////////

    // function testPayParamsRevertsBeforeInit() public {
    //     // IJBPaymentTerminal[] memory terminals = directory.terminalsOf(successfulProjectID);
    //     vm.expectRevert(DominantJuice.DataSourceNotInitialized.selector);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger1, 0, false, "", new bytes(0)
    //     );
    // }

    // function testPayParamsFromTerminalRevertsBeforeInit() public {
    //     vm.prank(earlyPledger1);
    //     vm.expectRevert(DominantJuice.DataSourceNotInitialized.selector);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger1, 0, false, "", new bytes(0)
    //     );
    // }

    // // payParams() function is non-payable, and the parent function that calls it is nonReentrant,
    // // thus not many tests here.

    // ///////////////////////////////////
    // // didPay() Tests //
    // //////////////////////////////////

    // modifier ownerHasDepositedBonus() {
    //     vm.startPrank(owner);
    //     dominantJuice.initialize(successfulProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    //     cycleExpiryDate = dominantJuice.cycleExpiryDate();
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    //     vm.stopPrank();
    //     assertEq(dominantJuice.getBalance(), TOTAL_REFUND_BONUS);
    //     _;
    // }

    // modifier oneEarlyPledgerPaid() {
    //     vm.prank(earlyPledger1);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger1, 0, false, "", new bytes(0)
    //     );
    //     _;
    // }

    // // assigns early pledger status correctly
    // function testDidPayAssignsEarlyPledger() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     bool isEarly = dominantJuice.getEarlyPledgerStatus(earlyPledger1);
    //     assertEq(isEarly, true);
    // }

    // // increases num early pledgers correctly
    // function testDidPayIncreasesNumEarlyPledger() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     uint256 numEarlyPledgers = dominantJuice.numEarlyPledgers();
    //     assertEq(numEarlyPledgers, 1);
    // }

    // // records amount in amount mapping
    // function testDidPayStoresEarlyPledgerAmount() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     uint256 pledgedAmount = dominantJuice.getPledgerAmount(earlyPledger1);
    //     assertEq(pledgedAmount, MIN_PLEDGE_AMOUNT);
    // }

    // // adds to totalAmountPledged
    // function testDidPaysUpdatesFundingVariables() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     (uint256 totalAmount, uint256 percent, bool targetMet, bool creatorWithdrawn) =
    //         dominantJuice.getCycleFundingStatus();
    //     assertEq(totalAmount, MIN_PLEDGE_AMOUNT);
    //     assertEq(percent, 1); // (100 * 1e12) /
    //     assertEq(targetMet, false);
    //     assertEq(creatorWithdrawn, false);
    // }

    // function testDidPayStopsAssigningEarlies() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     vm.prank(earlyPledger2);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger2, 0, false, "", new bytes(0)
    //     );
    //     vm.prank(pledger);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, pledger, 0, false, "", new bytes(0)
    //     );
    //     bool isEarly = dominantJuice.getEarlyPledgerStatus(pledger);
    //     assertEq(isEarly, false);
    // }

    // ///////////////////////////////////
    // // relayCycleResults() Tests //
    // //////////////////////////////////

    // function testRelayRevertsWhenCycleIsActive() public ownerHasDepositedBonus {
    //     vm.expectRevert(abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, cycleExpiryDate));
    //     vm.prank(owner);
    //     dominantJuice.relayCycleResults();
    // }

    // modifier successfulCycleHasExpired() {
    //     vm.prank(earlyPledger1);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger1, 0, false, "", new bytes(0)
    //     );
    //     vm.prank(earlyPledger2);
    //     ethPaymentTerminal3_1_1.pay{value: CYCLE_TARGET}(
    //         successfulProjectID, CYCLE_TARGET, ETH_TOKEN, earlyPledger2, 0, false, "", new bytes(0)
    //     );
    //     vm.prank(pledger);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, pledger, 0, false, "", new bytes(0)
    //     );
    //     vm.warp(block.timestamp + CYCLE_DURATION + 100);
    //     _;
    // }

    // modifier depositedBonusAndFailedCycleHasExpired() {
    //     vm.startPrank(owner);
    //     dominantJuice.initialize(failedProjectID, CYCLE_TARGET, MIN_PLEDGE_AMOUNT, MAX_EARLY_PLEDGERS);
    //     dominantJuice.depositRefundBonus{value: TOTAL_REFUND_BONUS}(TOTAL_REFUND_BONUS);
    //     vm.stopPrank();
    //     vm.prank(earlyPledger1);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger1, 0, false, "", new bytes(0)
    //     );
    //     vm.prank(earlyPledger2);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger2, 0, false, "", new bytes(0)
    //     );
    //     vm.prank(pledger);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, pledger, 0, false, "", new bytes(0)
    //     );

    //     vm.warp(block.timestamp + 100);
    //     vm.prank(owner);
    //     controller.reconfigureFundingCyclesOf(
    //         failedProjectID, _data, _metadataFailedCampaign, block.timestamp, _groupedSplits, _fundAccessConstraints, ""
    //     );
    //     vm.warp(block.timestamp + CYCLE_DURATION + 100);
    //     _;
    // }

    // // Sets correct isCycleExpired boolean
    // function testRelaySetsCycleExpiredBoolean() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     vm.prank(owner);
    //     dominantJuice.relayCycleResults();
    //     bool expired = dominantJuice.isCycleExpired();
    //     assertEq(expired, true);
    // }

    // // cannot be called twice
    // function testRelayCannotBeCalledTwice() public depositedBonusAndFailedCycleHasExpired {
    //     vm.prank(owner);
    //     dominantJuice.relayCycleResults();
    //     vm.expectRevert(DominantJuice.FunctionCanOnlyBeCalledOnce.selector);
    //     dominantJuice.relayCycleResults();
    // }

    // // sets correct cycle fund balance
    // function testRelaySetsCorrectBalance() public depositedBonusAndFailedCycleHasExpired {
    //     vm.prank(owner);
    //     dominantJuice.relayCycleResults();
    //     bool expired = dominantJuice.isCycleExpired();
    //     assertEq(expired, true);
    // }

    // // Calculates isTargetMet boolean correctly
    // function testRelaySetsTargetMetBoolean() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     vm.prank(owner);
    //     dominantJuice.relayCycleResults();
    //     bool isMet = dominantJuice.isTargetMet();
    //     assertEq(isMet, true);
    // }

    // // emits CycleHasClosed event
    // function testRelayEmitsEvent() public depositedBonusAndFailedCycleHasExpired {
    //     vm.prank(owner);
    //     vm.expectEmit(true, true, false, false, address(dominantJuice));
    //     emit CycleHasClosed(true, false);
    //     dominantJuice.relayCycleResults();
    // }

    // ///////////////////////////////////
    // // redeemParams() Tests //
    // //////////////////////////////////

    // // reverts if Cycle has not ended
    // function testRedeemRevertsDuringCycle() public ownerHasDepositedBonus {
    //     vm.startPrank(earlyPledger2);
    //     ethPaymentTerminal3_1_1.pay{value: MIN_PLEDGE_AMOUNT}(
    //         successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, earlyPledger2, 0, false, "", new bytes(0)
    //     );

    //     //vm.warp(block.timestamp + CYCLE_DURATION + 1);
    //     //vm.expectRevert(abi.encodeWithSelector(DominantJuice.CycleHasNotEndedYet.selector, cycleExpiryDate));
    //     // This will give an error from the Juicebox architecture. Need to find specific error and add.
    //     vm.expectRevert();
    //     ethPaymentTerminal3_1_1.redeemTokensOf(
    //         earlyPledger2, successfulProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 0, earlyPledger2, "", new bytes(0)
    //     );
    //     vm.stopPrank();
    // }

    // // NEED TO COME BACK TO
    // // reverts if not early pledger
    // function testRedeemSkipsRefundForRegPledgers() public depositedBonusAndFailedCycleHasExpired {
    //     uint256 balanceBefore = dominantJuice.getBalance();
    //     dominantJuice.relayCycleResults();
    //     vm.prank(pledger);
    //     ethPaymentTerminal3_1_1.redeemTokensOf(
    //         pledger, failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 1, pledger, "", new bytes(0)
    //     );
    //     uint256 balanceAfter = dominantJuice.getBalance();
    //     assertEq(balanceBefore, balanceAfter);
    // }

    // // reverts if earlyPledger has already withdrawn refund
    // function testRedeemRevertsIfAlreadyWithdrawn() public depositedBonusAndFailedCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     vm.startPrank(earlyPledger2);
    //     ethPaymentTerminal3_1_1.redeemTokensOf(
    //         earlyPledger2, failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 1, earlyPledger2, "", new bytes(0)
    //     );
    //     vm.expectRevert(DominantJuice.AlreadyWithdrawnRefund.selector);
    //     ethPaymentTerminal3_1_1.redeemTokensOf(
    //         earlyPledger2, failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 1, earlyPledger2, "", new bytes(0)
    //     );
    //     vm.stopPrank();
    // }

    // // calculates refund bonus correctly
    // function testRedeemCalculatesCorrectRefundBonus() public depositedBonusAndFailedCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     vm.prank(earlyPledger1);
    //     ethPaymentTerminal3_1_1.redeemTokensOf(
    //         earlyPledger1, failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 1, earlyPledger1, "", new bytes(0)
    //     );
    //     uint256 numEarlyPledgers = dominantJuice.numEarlyPledgers();
    //     uint256 bonus = dominantJuice.earlyPledgerRefundBonus();
    //     assertEq(bonus, TOTAL_REFUND_BONUS / numEarlyPledgers);
    // }

    // // sends refund bonus to pledger
    // function testRedeemRefundsEarlyPledger() public depositedBonusAndFailedCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     uint256 pledgerBalanceBefore = earlyPledger1.balance;
    //     vm.prank(earlyPledger1);
    //     uint256 reclaimed = ethPaymentTerminal3_1_1.redeemTokensOf(
    //         earlyPledger1, failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 1, earlyPledger1, "", new bytes(0)
    //     );
    //     uint256 pledgerBalanceAfter = earlyPledger1.balance;
    //     uint256 balanceChange = pledgerBalanceAfter - reclaimed - pledgerBalanceBefore;
    //     uint256 refundBonus = dominantJuice.earlyRefundBonusCalc();
    //     assertEq(balanceChange, refundBonus);
    // }

    // // emits event
    // function testRedeemEmitsEvent() public depositedBonusAndFailedCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     uint256 refund = dominantJuice.earlyRefundBonusCalc();
    //     vm.expectEmit(true, true, false, false, address(dominantJuice));
    //     emit CycleRefundBonusWithdrawal(earlyPledger1, refund);
    //     vm.prank(earlyPledger1);
    //     ethPaymentTerminal3_1_1.redeemTokensOf(
    //         earlyPledger1, failedProjectID, MIN_PLEDGE_AMOUNT, ETH_TOKEN, 1, earlyPledger1, "", new bytes(0)
    //     );
    // }

    // ///////////////////////////////////
    // // creatorWithdraw() Tests //
    // //////////////////////////////////

    // // revert if Cycle has not expired
    // function testCreatorWithdrawRevertsDuringCycle() public ownerHasDepositedBonus {
    //     vm.expectRevert("Cycle must be expired and successful to call this function.");
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(owner, TOTAL_REFUND_BONUS);
    // }

    // // reverts if goal has not been met.
    // function testCreatorWithdrawRevertsIfGoalNotMet() public depositedBonusAndFailedCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     vm.expectRevert("Cycle must be expired and successful to call this function.");
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(owner, TOTAL_REFUND_BONUS);
    // }

    // // reverts if not contract owner
    // function testCreatorWithdrawRevertsForPledger() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     vm.expectRevert("Ownable: caller is not the owner");
    //     vm.prank(earlyPledger2);
    //     dominantJuice.creatorWithdraw(earlyPledger2, TOTAL_REFUND_BONUS);
    // }

    // // reverts if input amount is more than balance
    // function testCreatorWithdrawRevertsOnOverdraw() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     uint256 overdrawAmount = dominantJuice.getBalance() + 1 ether;
    //     vm.expectRevert(DominantJuice.InsufficientFunds.selector);
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(owner, overdrawAmount);
    // }

    // function testCreatorWithdrawSendsCorrectAmount() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     uint256 balanceBefore = owner.balance;
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(owner, 100 gwei);
    //     uint256 balanceAfter = owner.balance;
    //     uint256 diff = balanceAfter - balanceBefore;
    //     assertEq(diff, 100 gwei);
    // }

    // function testCreatorWithdrawSendsFundsToDifferentAddress()
    //     public
    //     ownerHasDepositedBonus
    //     successfulCycleHasExpired
    // {
    //     dominantJuice.relayCycleResults();
    //     uint256 pledgerFundsBefore = pledger.balance;
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(pledger, TOTAL_REFUND_BONUS);
    //     uint256 pledgerFundsAfter = pledger.balance;
    //     uint256 pledgerFunds = pledgerFundsAfter - pledgerFundsBefore;
    //     assertEq(pledgerFunds, TOTAL_REFUND_BONUS);
    // }

    // // emits event
    // function testCreatorWithdrawEmitsEvent() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     vm.expectEmit(false, false, false, false, address(dominantJuice));
    //     emit OwnerWithdrawal(owner, TOTAL_REFUND_BONUS);
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(owner, TOTAL_REFUND_BONUS);
    // }

    // // if zero balance, change hasCreatorWithdrawnAllFunds to true.
    // function testCreatorWithdrawChangesBoolean() public ownerHasDepositedBonus successfulCycleHasExpired {
    //     dominantJuice.relayCycleResults();
    //     vm.prank(owner);
    //     dominantJuice.creatorWithdraw(owner, TOTAL_REFUND_BONUS);
    //     (,,, bool ownerHasWithdrawn) = dominantJuice.getCycleFundingStatus();
    //     assertEq(ownerHasWithdrawn, true);
    // }

    // ///////////////////////////////////
    // // Getters Tests //
    // //////////////////////////////////

    // // earlyRefundBonusCalc(): calculates refund bonus, getter and a function helper
    // function testEarlyRefundBonusCalc_ulatesCorrectly() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     uint256 individualBonus = dominantJuice.earlyRefundBonusCalc();
    //     assertEq(individualBonus, TOTAL_REFUND_BONUS);
    // }

    // // getCycleFundingStatus(): gets percent of funding goal, total amount pledged, isTargetMet and hasCreatorWithdrawnAllFunds.
    // function testGetCycleFundingStatusGetsCorrectly() public ownerHasDepositedBonus oneEarlyPledgerPaid {
    //     (uint256 totalAmount, uint256 percent, bool targetMet, bool creatorWithdrawn) =
    //         dominantJuice.getCycleFundingStatus();
    //     assertEq(totalAmount, MIN_PLEDGE_AMOUNT);
    //     assertEq(percent, 1); // (100 * 1e12) / 1e14
    //     assertEq(targetMet, false);
    //     assertEq(creatorWithdrawn, false);
    // }
}
