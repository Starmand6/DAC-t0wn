// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBFundingCycleDataSource3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource3_1_1.sol";
import {IJBFundingCycleStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleStore.sol";
import {IJBFundAccessConstraintsStore} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundAccessConstraintsStore.sol";
import {IJBPayDelegate3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate3_1_1.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBRedemptionDelegate3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBRedemptionDelegate3_1_1.sol";
import {IJBSingleTokenPaymentTerminal} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {JBDidPayData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData3_1_1.sol";
import {JBDidRedeemData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData3_1_1.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {JBPayDelegateAllocation3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation3_1_1.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBRedemptionDelegateAllocation3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import {JBTokenAmount} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UD60x18, ud, add, pow, powu, div, mul, wrap, unwrap} from "@prb/math/UD60x18.sol";

/**
 * @title Dominant Juice
 * @author Armand Daigle
 * @notice This contract is a JB Data Source, JB Pay Delegate, JB Redemption Delegate, and a Refund Bonus Escrow
 * implementation. Campaigns, interchangeable with cycles from here on, that use this implementation as a Data Source
 * will incorporate Alex Tabarrok's dominant assurance mechanism, which incentivize early pledgers with a campaign
 * creator-provided refund bonus that can be withdrawn from this contract after a failed campaign.
 * @dev This dominant assurance contract (DAC) uses the JB Data Source, Pay Delegate, and Pay Redemption interfaces and
 * extends the functionality of a Juicebox project. Once a JB project is created, the constructor stores project data
 * and the pertinent Juicebox architecture contracts. This contract is written for a single cycle campaign. If projects
 * want dominant assurance on more cycles, refactoring is required.
 */
contract DominantJuice is
    IJBFundingCycleDataSource3_1_1,
    IJBPayDelegate3_1_1,
    IJBRedemptionDelegate3_1_1,
    AccessControl
{
    bytes32 private constant CAMPAIGN_MANAGER_ROLE = keccak256("CAMPAIGN_MANAGER_ROLE");

    /// Juicebox Contracts
    IJBController3_1 public immutable controller;
    IJBDirectory public immutable directory; // directory of terminals and controllers for projects.
    IJBFundAccessConstraintsStore public immutable fundAccessConstraintsStore;
    IJBSingleTokenPaymentTerminalStore3_1_1 public immutable paymentTerminalStore;
    IJBSingleTokenPaymentTerminal public immutable paymentTerminal;

    /// Main Campaign Parameters
    struct Campaign {
        uint256 projectId;
        uint256 cycleTarget;
        uint256 cycleExpiryDate;
        uint256 minimumPledgeAmount;
        uint256 totalRefundBonus;
    }

    struct FundingStatus {
        uint256 totalPledged;
        uint256 percentOfGoal;
        bool isTargetMet;
        bool hasCycleExpired;
        bool hasCreatorWithdrawnAllFunds;
    }

    struct Pledgers {
        uint256 totalAmountPledged;
        UD60x18 totalPledgeWeight;
        mapping(address => UD60x18) pledgerWeight;
        mapping(address => bool) hasBeenRefunded;
    }

    /// State Variables
    Campaign private campaign;
    Pledgers private pledgers;
    UD60x18 private immutable rateOfDecay = ud(0.99e18);

    // Events for transparency to pledgers
    event RefundBonusDeposited(address, uint256 indexed);
    event PledgeMade(address, uint256);
    event CycleHasClosed(bool indexed, bool indexed);
    event CycleRefundBonusWithdrawal(address indexed, uint256 indexed);
    event CreatorWithdrawal(address, uint256);

    error BonusAlreadyDeposited(uint256 bonusAmount);
    error RefundBonusNotDeposited();
    error AmountIsBelowMinimumPledge(uint256 minAmount);
    error InvalidPaymentEvent(address caller, uint256 projectId, uint256 value);
    error CycleHasExpired();
    error IncorrectProjectID();
    error FunctionHasAlreadyBeenCalled();
    error MustBePledger();
    error CycleHasNotEndedYet(uint256 endTimestamp);
    error NoRefundsForSuccessfulCycle();
    error AlreadyWithdrawnRefund();
    error InvalidRedemptionEvent(address caller, uint256 projectId, uint256 value);
    error InsufficientFunds();

    // Make sure the caller is a terminal of the project, and that the call is being made
    // on behalf of an interaction with the correct project.
    modifier terminalCheck() {
        require(msg.value == 0, "Pledges should be made through JB website.");
        require(
            directory.isTerminalOf(campaign.projectId, IJBPaymentTerminal(msg.sender)),
            "Caller must be a JB Payment Terminal."
        );
        _;
    }

    modifier redeemCycleCheck() {
        // This is an insurance check, since project should have redemptions paused during 1st cycle.
        if (!hasCycleExpired()) revert CycleHasNotEndedYet(campaign.cycleExpiryDate);
        if (isTargetMet()) revert NoRefundsForSuccessfulCycle();
        _;
    }

    /// @param _projectId Obtained via Juicebox after project creation.
    constructor(
        address payable _campaignManager,
        uint256 _projectId,
        uint256 _cycleTarget,
        uint256 _minimumPledgeAmount,
        IJBController3_1 _controller,
        IJBSingleTokenPaymentTerminalStore3_1_1 _paymentTerminalStore
    ) {
        // Assign roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CAMPAIGN_MANAGER_ROLE, _campaignManager);

        // Store parameters of a project launched on the Juicebox platform.
        campaign.cycleTarget = _cycleTarget;
        campaign.minimumPledgeAmount = _minimumPledgeAmount;
        campaign.projectId = _projectId;

        // Store JB architecture contracts
        controller = _controller;
        paymentTerminalStore = _paymentTerminalStore;
        directory = controller.directory();
        fundAccessConstraintsStore = controller.fundAccessConstraintsStore();

        // Get the default ETH payment terminal of the project from the JB directory.
        paymentTerminal = IJBSingleTokenPaymentTerminal(address(directory.terminalsOf(campaign.projectId)[0]));

        // Destructure cycleData struct to access cycle start and duration timestamps
        (JBFundingCycle memory cycleData,) = controller.currentFundingCycleOf(campaign.projectId);
        campaign.cycleExpiryDate = cycleData.start + cycleData.duration;
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(IERC165, AccessControl)
        returns (bool)
    {
        return _interfaceId == type(IJBFundingCycleDataSource3_1_1).interfaceId
            || _interfaceId == type(IJBPayDelegate3_1_1).interfaceId
            || _interfaceId == type(IJBRedemptionDelegate3_1_1).interfaceId || super.supportsInterface(_interfaceId);
    }

    /**
     * @notice Project creator calls this function to deposit refund bonus before funding cycle start
     * to increase potential pledger confidence.
     * @dev Can only be called once by the campaign manager / project creator.
     */
    function depositRefundBonus() external payable onlyRole(CAMPAIGN_MANAGER_ROLE) {
        // Reverts if bonus has already been deposited.
        if (campaign.totalRefundBonus > 0) revert BonusAlreadyDeposited(campaign.totalRefundBonus);

        // Updates contract refund bonus variable.
        campaign.totalRefundBonus = msg.value;

        emit RefundBonusDeposited(msg.sender, campaign.totalRefundBonus);
    }

    /**
     * @notice This function is called when the project receives a payment through the JB platform.
     * @dev This function satisfies the `IJBFundingCycleDataSource` interface requirements and readies this contract
     * to receive a `didPay()` call. `JBPayoutRedemptionPaymentTerminal3_1_1.pay()` calls
     * `JBSingleTokenPaymentTerminalStore3_1_1.recordPaymentFrom()`, which calls this function.
     * @param _data JB project payment data. See https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
     * @return weight The weight that project tokens should get minted relative to. This is useful for optionally
     * customizing how many tokens are issued per payment.
     * @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
     * @return delegateAllocations Amount to be sent to delegates instead of adding to local balance. Useful for
     * auto-routing funds from a treasury as payment come in.
     */
    function payParams(JBPayParamsData calldata _data)
        external
        view
        virtual
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations)
    {
        // The if statements are the only changes from the payParams() template. This is also not a payable
        // function, so calls with msg.value will revert.
        if (getBalance() == 0) revert RefundBonusNotDeposited();
        if (hasCycleExpired()) revert CycleHasExpired();
        if (_data.amount.value < campaign.minimumPledgeAmount) {
            revert AmountIsBelowMinimumPledge(campaign.minimumPledgeAmount);
        }

        // Forward the default weight received from the protocol.
        weight = _data.weight;
        // Forward the default memo received from the payer.
        memo = _data.memo;
        // Add `this` contract as a Pay Delegate so that it receives a `didPay` call. Don't send funds to the delegate (keep in treasury).
        delegateAllocations = new JBPayDelegateAllocation3_1_1[](1);
        delegateAllocations[0] = JBPayDelegateAllocation3_1_1(this, 0, "");
    }

    /**
     * @notice Received hook from the payment terminal after a payment.
     * @dev Reverts if the calling contract is not one of the project's terminals. This is the final call in the
     * chain described in `payParams()`.
     * @param _data Standard Juicebox project payment data.
     * See https://docs.juicebox.money/dev/api/data-structures/jbdidpaydata3_1_1/.
     */
    function didPay(JBDidPayData3_1_1 calldata _data) external payable virtual override terminalCheck {
        if (_data.projectId != campaign.projectId) revert IncorrectProjectID();

        // Get payer address and amount paid from JB DidPay data struct
        address payer = _data.payer;
        JBTokenAmount memory amount = _data.amount;
        uint256 paymentAmount = amount.value;

        // Get time of pledge from campaign start.
        (JBFundingCycle memory cycleData,) = controller.currentFundingCycleOf(campaign.projectId);
        uint256 hourOfPledge = (block.timestamp - cycleData.start) / 3600;

        // Update storage variables
        pledgers.totalAmountPledged += paymentAmount;
        pledgers.pledgerWeight[payer] = mul(rateOfDecay.powu(hourOfPledge), wrap(paymentAmount));
        pledgers.totalPledgeWeight = add(pledgers.totalPledgeWeight, pledgers.pledgerWeight[payer]);

        emit PledgeMade(payer, paymentAmount);
    }

    /**
     * @notice This function gets called when the project's token holders redeem.
     * @dev This function satisfies the `IJBFundingCycleDataSource` interface requirements and readies this contract
     * to receive a `didRedeem()` call. `JBPayoutRedemptionPaymentTerminal3_1_1.redeemTokensOf()` calls
     * `JBSingleTokenPaymentTerminalStore3_1_1.recordRedemptionFor()`, which calls this function.
     * @param _data JB project redemption data. See https://docs.juicebox.money/dev/api/data-structures/jbredeemparamsdata/.
     * @return reclaimAmount Amount to be reclaimed from the treasury. This is useful for optionally customizing how much
     * funds from the treasury are disbursed per redemption.
     * @return memo A memo to be forwarded to the event. Useful for describing any new actions are being taken.
     * @return delegateAllocations Amount to be sent to delegates instead of being added to the beneficiary. Useful for
     * auto-routing funds from a treasury as redemptions are sought.
     */
    function redeemParams(JBRedeemParamsData calldata _data)
        external
        view
        virtual
        override
        redeemCycleCheck
        returns (
            uint256 reclaimAmount,
            string memory memo,
            JBRedemptionDelegateAllocation3_1_1[] memory delegateAllocations
        )
    {
        address payable redeemer = payable(_data.holder);

        // The if statements are the only changes from the redeemParams() template.
        if (unwrap(pledgers.pledgerWeight[redeemer]) == 0) revert MustBePledger();
        if (pledgers.hasBeenRefunded[redeemer]) revert AlreadyWithdrawnRefund();

        // Forward the default reclaimAmount received from the protocol.
        reclaimAmount = _data.reclaimAmount.value;
        // Forward the default memo received from the redeemer.
        memo = _data.memo;
        // Add `this` contract as a Redeem Delegate so that it receives a `didRedeem` call. Don't send any extra funds to the delegate.
        delegateAllocations = new JBRedemptionDelegateAllocation3_1_1[](1);
        delegateAllocations[0] = JBRedemptionDelegateAllocation3_1_1(this, 0, "");
    }

    /**
     * @notice Received hook from the payment terminal after a redemption. If cycle meets project target,
     * then this function cannot be called, since pauseRedemptions will be true. If the cycle fails to meet
     * its target, then this function will be callable for pledgers after the `cycleExpiryDate`.
     * @dev Reverts if the calling contract is not one of the project's terminals. This is the final call in the
     * call chain described in `redeemParams()`.
     * @param _data Standard Juicebox project redemption data.
     * See https://docs.juicebox.money/dev/api/data-structures/jbdidredeemdata3_1_1/.
     */
    function didRedeem(JBDidRedeemData3_1_1 calldata _data) external payable terminalCheck redeemCycleCheck {
        if (_data.projectId != campaign.projectId) revert IncorrectProjectID();

        address payable redeemer = payable(_data.holder);
        if (unwrap(pledgers.pledgerWeight[redeemer]) == 0) revert MustBePledger();
        if (pledgers.hasBeenRefunded[redeemer]) revert AlreadyWithdrawnRefund();

        // Calculates the refund bonus, using PRBMath, based on the time from cycle start and the size of the pledge
        uint256 pledgerRefundBonus = unwrap(
            mul(div(pledgers.pledgerWeight[redeemer], pledgers.totalPledgeWeight), wrap(campaign.totalRefundBonus))
        );

        // Sanity Check
        if (address(this).balance < pledgerRefundBonus) revert InsufficientFunds();

        // This redeeem function is now locked for the current redeeming address.
        pledgers.hasBeenRefunded[redeemer] = true;

        // Sending early pledger refund bonus.
        (bool sendSuccess,) = redeemer.call{value: pledgerRefundBonus}("");
        require(sendSuccess, "Failed to send refund bonus.");

        emit CycleRefundBonusWithdrawal(redeemer, pledgerRefundBonus);
    }

    /**
     * @notice This function is callable after cycleExpiryDate if goal is met. However, for
     * contingency, where a redeemer is unable to retrieve funds, after a locked period, the
     * Campaign Manager can withdraw funds for disbursement to remaining redeemers . The unlock
     * time is hardcoded for two weeks after the cycleExpiryDate to give pledgers confidence
     * that funds are programmatically guaranteed to remain in the contract for that time.
     * @param receivingAddress Campaign Manager must call this function but can withdraw funds to
     * another address if desired.
     */
    function creatorWithdraw(address payable receivingAddress, uint256 amount)
        external
        payable
        onlyRole(CAMPAIGN_MANAGER_ROLE)
    {
        uint256 unlockTime = campaign.cycleExpiryDate + 1209600; // Two weeks after expiry date
        require(
            (hasCycleExpired() && isTargetMet()) || ((block.timestamp > unlockTime) && !isTargetMet()),
            "Cycle must be expired and successful, or it must be passed the lock period."
        );
        if (amount > address(this).balance) revert InsufficientFunds();

        (bool success,) = receivingAddress.call{value: amount}("");
        require(success, "Failed to withdraw cycle funds.");

        emit CreatorWithdrawal(receivingAddress, amount);
    }

    /// Getters and Helpers

    function getCampaignInfo() public view returns (Campaign memory) {
        return campaign;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function isTargetMet() public view returns (bool) {
        if (pledgers.totalAmountPledged >= campaign.cycleTarget) return true;
        else return false;
    }

    function hasCycleExpired() public view returns (bool) {
        if (block.timestamp >= campaign.cycleExpiryDate) {
            return true;
        } else {
            return false;
        }
    }

    function getCycleFundingStatus() public view returns (FundingStatus memory) {
        FundingStatus memory status;

        status.totalPledged = pledgers.totalAmountPledged;
        status.percentOfGoal = ((100 * pledgers.totalAmountPledged) / campaign.cycleTarget);
        status.isTargetMet = isTargetMet();
        status.hasCycleExpired = hasCycleExpired();
        if (isTargetMet() && address(this).balance == 0) status.hasCreatorWithdrawnAllFunds = true;

        return status;
    }

    function getPledgerAndTotalWeights(address _pledger) public view returns (uint256, uint256) {
        uint256 pledgerWeight = unwrap(pledgers.pledgerWeight[_pledger]);
        uint256 totalWeight = unwrap(pledgers.totalPledgeWeight);

        return (pledgerWeight, totalWeight);
    }

    function getPledgerRefundStatus(address _pledger) public view returns (bool) {
        return pledgers.hasBeenRefunded[_pledger];
    }
}
