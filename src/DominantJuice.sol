// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {mulDiv} from '@prb/math/src/Common.sol';
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
//import {JBDidRedeemData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBRedemptionDelegateAllocation3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation3_1_1.sol";
import {JBTokenAmount} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBTokenAmount.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud, add, pow, powu, div, mul, wrap, unwrap} from "@prb/math/UD60x18.sol";

/**
 * @title Dominant Juice
 * @author Armand Daigle
 * @notice This contract is a JB Data Source, JB Pay Delegate, JB Redemption Delegate, and a Refund Bonus Escrow
 * implementation. Campaigns, referred to as cycles from here on, that use this implementation as a Data Source
 * will incorporate Alex Tabarrok's dominant assurance mechanism, which incentivize early pledgers with a campaign
 * creator-provided refund bonus that can be withdrawn from this contract after a failed campaign.
 * @dev This contract uses the JB Data Source, Pay Delegate, and Pay Redemption interfaces and extends the
 * functionality of a Juicebox project. There is no constructor since each campaign will deploy a clone of this
 * contract. The initialize() function acts as the constructor. This contract is written to only be used for one cycle.
 * If projects want dominant assurance on more cycles, refactoring is required.
 */
contract DominantJuice is IJBFundingCycleDataSource3_1_1, IJBPayDelegate3_1_1, IJBRedemptionDelegate3_1_1, Ownable {
    /// Juicebox Contracts

    IJBController3_1 public controller;
    IJBDirectory public directory; // directory of terminals and controllers for projects.
    IJBFundAccessConstraintsStore public fundAccessConstraintsStore;
    IJBSingleTokenPaymentTerminalStore3_1_1 public paymentTerminalStore;
    IJBSingleTokenPaymentTerminal public paymentTerminal;

    /// Juicebox Project State Variables
    uint256 public projectId;
    uint256 public projectConfiguration;
    address public paymentToken;

    /// Dominant Assurance State Variables
    uint256 public cycleExpiryDate;
    uint256 public cycleTarget;
    uint256 public minimumPledgeAmount;
    uint256 public totalRefundBonus;
    uint256 public totalAmountPledged;
    uint256 public totalAmountPledged_fromJB;
    UD60x18 public rateOfDecay = ud(0.75e18); // Need to confirm we want to hardcode this
    bool public isCycleExpired = false;
    bool public isTargetMet = false;
    bool public hasCreatorWithdrawnAllFunds = false;

    /// Pledger Mappings and Array
    mapping(address => uint256) public pledgedAmount;
    mapping(address => bool) public hasBeenRefunded;
    mapping(uint256 => mapping(address => uint256)) public orderToPledgerToAmount;
    address[] public pledgers;
    uint32 public pledgeOrder; // make internal?

    // Events for transparency to pledgers
    event RefundBonusDeposited(address, uint256 indexed);
    event CycleHasClosed(bool indexed, bool indexed);
    event CycleRefundBonusWithdrawal(address indexed, uint256 indexed);
    event OwnerWithdrawal(address, uint256);
    event Test(string, uint256);

    error DataSourceNotInitialized();
    error FundsMustMatchInputAmount(uint256 input);
    error AmountIsBelowMinimumPledge(uint256 minAmount);
    error InvalidPaymentEvent(address caller, uint256 projectId, uint256 value);
    error CycleHasExpired();
    error FunctionHasAlreadyBeenCalled();
    error MustBePledger();
    error CycleHasNotEndedYet(uint256 endTimestamp);
    error NoRefundsForSuccessfulCycle();
    error ContractAlreadyInitialized();
    error AlreadyWithdrawnRefund();
    error InvalidRedemptionEvent(address caller, uint256 projectId, uint256 value);
    error InsufficientFunds();

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IJBFundingCycleDataSource3_1_1).interfaceId
            || _interfaceId == type(IJBPayDelegate3_1_1).interfaceId
            || _interfaceId == type(IJBRedemptionDelegate3_1_1).interfaceId;
    }

    /// @notice Initializes the Dominant Assurance cloned contract with project details
    /// and the pertinent Juicebox architecture contracts. Function should be called by the
    /// Delegate Deployer contract directly after it creates the clone for each new project.
    /// @param _projectId The ID of the project this contract's functionality applies to.
    function initialize(
        uint256 _projectId,
        uint256 _cycleTarget,
        uint256 _minimumPledgeAmount,
        IJBController3_1 _controller,
        IJBSingleTokenPaymentTerminalStore3_1_1 _paymentTerminalStore
    ) external {
        // Stop re-initialization.
        if (projectId != 0) revert ContractAlreadyInitialized();

        // Store project parameters and ready JB architecture contracts for calling
        cycleTarget = _cycleTarget;
        minimumPledgeAmount = _minimumPledgeAmount;
        projectId = _projectId;
        controller = _controller;
        paymentTerminalStore = _paymentTerminalStore;
        directory = controller.directory();
        fundAccessConstraintsStore = controller.fundAccessConstraintsStore();
        address terminalAddr = address(directory.terminalsOf(projectId)[0]);
        paymentTerminal = IJBSingleTokenPaymentTerminal(terminalAddr);
        //paymentToken = paymentTerminal.token();
        (JBFundingCycle memory cycleData,) = controller.currentFundingCycleOf(projectId);
        cycleExpiryDate = cycleData.start + cycleData.duration;
    }

    /**
     * @notice Project creator calls this function to deposit refund bonus before funding cycle start
     * to increase potential pledger confidence.
     * @dev Can only be called by the contract owner / project creator.
     */
    function depositRefundBonus(uint256 refundBonusAmount) external payable onlyOwner {
        // Reverts if initialize() has not been called yet.
        if (projectId == 0) revert DataSourceNotInitialized();

        // Reverts if ETH sent does not match input amount.
        if (msg.value != refundBonusAmount) revert FundsMustMatchInputAmount(refundBonusAmount);

        // Updates contract refund bonus variable.
        totalRefundBonus = refundBonusAmount;

        emit RefundBonusDeposited(msg.sender, totalRefundBonus);
    }

    /// @notice This function gets called when the project receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard project payment data. See https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that project tokens should get minted relative to. This is useful for optionally customizing how many tokens are issued per payment.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to local balance. Useful for auto-routing funds from a treasury as payment come in.
    function payParams(JBPayParamsData calldata _data)
        external
        virtual
        override
        returns (uint256 weight, string memory memo, JBPayDelegateAllocation3_1_1[] memory delegateAllocations)
    {
        // The if statements are the only changes from the payParams() template.
        // This is also not a payable function, so calls with msg.value will revert.
        if (getBalance() == 0) revert DataSourceNotInitialized();
        if (_data.amount.value < minimumPledgeAmount) revert AmountIsBelowMinimumPledge(minimumPledgeAmount);

        // Forward the default weight received from the protocol.
        weight = _data.weight;
        // Forward the default memo received from the payer.
        memo = _data.memo;
        // Add `this` contract as a Pay Delegate so that it receives a `didPay` call. Don't send any funds to the delegate (keep all funds in the treasury).
        delegateAllocations = new JBPayDelegateAllocation3_1_1[](1);
        delegateAllocations[0] = JBPayDelegateAllocation3_1_1(this, 0, "");

        return (weight, memo, delegateAllocations);
    }

    /// @notice Received hook from the payment terminal after a payment.
    /// @dev Reverts if the calling contract is not one of the project's terminals.
    /// @dev This example implementation reverts if the payer isn't on the allow list.
    /// @param _data Standard Juicebox project payment data.
    /// See https://docs.juicebox.money/dev/api/data-structures/jbdidpaydata3_1_1/.
    function didPay(JBDidPayData3_1_1 calldata _data) external payable virtual override {
        // Make sure the caller is a terminal of the project, and that the call is
        // being made on behalf of an interaction with the correct project.
        if (
            msg.value != 0 || !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender))
                || _data.projectId != projectId
        ) revert InvalidPaymentEvent(msg.sender, _data.projectId, msg.value);

        if (block.timestamp >= cycleExpiryDate) revert CycleHasExpired();

        // Get payer address and amount paid from JB DidPay data struct
        address payer = _data.payer;
        JBTokenAmount memory amount = _data.amount;
        uint256 paymentAmount = amount.value;

        // Update storage variables
        totalAmountPledged += paymentAmount;
        pledgedAmount[payer] = paymentAmount;
        pledgers.push(payer);
        orderToPledgerToAmount[pledgeOrder][payer] = paymentAmount;
        pledgeOrder++;
    }

    /**
     * @notice After the funding cycle ends, anyone can call this function to store the cycle results.
     * @dev
     */
    function relayCycleResults() public {
        if (isCycleExpired == true) revert FunctionHasAlreadyBeenCalled();
        if (block.timestamp < cycleExpiryDate) revert CycleHasNotEndedYet(cycleExpiryDate);
        // This function can only be called once.
        isCycleExpired = true;

        // Sanity check comparison with JB total amount pledged. If same, lock in. If different,
        // go to fallback scenario.
        // totalAmountPledged_fromJB = paymentTerminalStore.balanceOf(paymentTerminal, projectId);
        // if (totalAmountPledged != totalAmountPledged_fromJB) {
        //     totalAmountPledged = totalAmountPledged_fromJB;
        // Need fallback scenario here, or is ^ this adequate?
        // }
        if (totalAmountPledged >= cycleTarget) {
            isTargetMet = true;
        }

        emit CycleHasClosed(isCycleExpired, isTargetMet);
    }

    /// @notice This function gets called when the project's token holders redeem.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @param _data Standard Juicebox project redemption data. See https://docs.juicebox.money/dev/api/data-structures/jbredeemparamsdata/.
    /// @return reclaimAmount Amount to be reclaimed from the treasury. This is useful for optionally customizing how much funds from the treasury are disbursed per redemption.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of being added to the beneficiary. Useful for auto-routing funds from a treasury as redemptions are sought.
    function redeemParams(JBRedeemParamsData calldata _data)
        external
        view
        virtual
        override
        returns (
            uint256 reclaimAmount,
            string memory memo,
            JBRedemptionDelegateAllocation3_1_1[] memory delegateAllocations
        )
    {
        address payable redeemer = payable(_data.holder);

        // The if statements are the only changes from the redeemParams() template.
        if (pledgedAmount[redeemer] == 0) revert MustBePledger();
        if (isCycleExpired != true) revert CycleHasNotEndedYet(cycleExpiryDate);
        if (isTargetMet == true) revert NoRefundsForSuccessfulCycle();
        if (hasBeenRefunded[redeemer] == true) revert AlreadyWithdrawnRefund();

        // Forward the default reclaimAmount received from the protocol.
        reclaimAmount = _data.reclaimAmount.value;
        // Forward the default memo received from the redeemer.
        memo = _data.memo;
        // Add `this` contract as a Redeem Delegate so that it receives a `didRedeem` call. Don't send any extra funds to the delegate.
        delegateAllocations = new JBRedemptionDelegateAllocation3_1_1[](1);
        delegateAllocations[0] = JBRedemptionDelegateAllocation3_1_1(this, 0, "");

        return (reclaimAmount, memo, delegateAllocations);
    }

    /// @notice If cycle meets project target, then this function cannot be called, since pauseRedemptions will be on.
    /// If cycle fails to meet its target, then this function will proceed all the way through for pledgers.
    function didRedeem(JBDidRedeemData3_1_1 calldata _data) external payable {
        if (
            msg.value != 0 || !directory.isTerminalOf(projectId, IJBPaymentTerminal(msg.sender))
                || _data.projectId != projectId
        ) revert InvalidRedemptionEvent(msg.sender, _data.projectId, msg.value);

        address payable redeemer = payable(_data.holder);
        if (pledgedAmount[redeemer] == 0) revert MustBePledger();
        if (isCycleExpired != true) revert CycleHasNotEndedYet(cycleExpiryDate);
        if (isTargetMet == true) revert NoRefundsForSuccessfulCycle();
        if (hasBeenRefunded[redeemer] == true) revert AlreadyWithdrawnRefund();

        // Calculates the refund bonus, based on the time and size of the pledge
        uint256 pledgerRefundBonus = calculateRefundBonus(redeemer);

        // Sanity Check
        if (address(this).balance < pledgerRefundBonus) revert InsufficientFunds();

        // This redeeem function is now locked for the current redeeming address.
        hasBeenRefunded[redeemer] = true;

        // Sending early pledger refund bonus.
        (bool sendSuccess,) = redeemer.call{value: pledgerRefundBonus}("");
        require(sendSuccess, "Failed to send refund bonus.");
        emit CycleRefundBonusWithdrawal(redeemer, pledgerRefundBonus);
    }

    /**
     * @dev This function is callable only after cycle expiry if goal is met.
     * @param receivingAddress Contract Owner must call this function, but they can
     * input another address to receive funds if desired.
     */
    function creatorWithdraw(address payable receivingAddress, uint256 amount) external payable onlyOwner {
        require(
            isCycleExpired == true && isTargetMet == true, "Cycle must be expired and successful to call this function."
        );
        if (amount > address(this).balance) revert InsufficientFunds();

        (bool success,) = receivingAddress.call{value: amount}("");
        require(success, "Failed to withdraw cycle funds.");

        emit OwnerWithdrawal(receivingAddress, amount);

        if (address(this).balance == 0) {
            hasCreatorWithdrawnAllFunds = true;
        }
    }

    /// Getters and Helpers

    // Due to decimnal precision and calculating the power of floating-point numbers, we use PRBMath for this helper function.
    function calculateRefundBonus(address _pledger) public returns (uint256) {
        require(pledgedAmount[_pledger] > 0, "Address is not a pledger.");

        uint256 numPledgers = pledgers.length;
        UD60x18 individualRefundBonus;
        UD60x18 pledgeAmount_orderLoop;
        UD60x18 pledgeAmount_amountLoop;

        // Donations and order of pledges are weighted to benefit earlier, larger pledges
        UD60x18 orderWeight;
        UD60x18 sumOfOrderWeights;
        // Memory array of normalized order weights (w-1s)
        uint256[] memory orderWeightNormalized = new uint[](numPledgers);
        UD60x18 sumOfAmountsXNormalizedOrderWeights;
        // uint256 donationWeight;
        // uint256 donationWeightNormalized;
        // Represents the combined order and pledge amount weighting.
        UD60x18 overallPledgeWeight;
        emit Test("totalAmountPledged", totalAmountPledged);
        // First, get the sum of pledge order weights to use in the normalizing loop
        for (uint32 i = 0; i < numPledgers; i++) {
            // Add 1 to i because rateOfDecay is being raised to the pledge ordereth power
            sumOfOrderWeights = add(sumOfOrderWeights, rateOfDecay.powu(i + 1));
        }

        // Refund Bonus calculation prep work:
        for (uint32 j = 0; j < numPledgers; j++) {
            // Earlier pledges are given more weight according to the exponential decay rate.
            // Add 1 to j because rateOfDecay is being raised to the ordereth power.
            orderWeight = rateOfDecay.powu(j + 1);
            // Order weights are normalized to compare each pledge to the total pledging data.
            // Save in memory array for use in next for loop.
            orderWeightNormalized[j] = unwrap(orderWeight / sumOfOrderWeights);
            // Get the payment amount for each order
            pledgeAmount_orderLoop = wrap(orderToPledgerToAmount[j][pledgers[j]]);
            // Multiply payments by their respective normalized weight. Sum all products by
            // looping (=sum(x*w_1)). Use in next for loop
            sumOfAmountsXNormalizedOrderWeights =
                add(sumOfAmountsXNormalizedOrderWeights, mul(pledgeAmount_orderLoop, wrap(orderWeightNormalized[j])));
        }

        // Next, give more weight to larger contribution amounts by multiplying each pledge amount with its
        // orderWeightNormalized. Looping logic is for the possibility of repeat pledgers
        for (uint32 k = 0; k < numPledgers; k++) {
            if (pledgers[k] == _pledger) {
                pledgeAmount_amountLoop = wrap(orderToPledgerToAmount[k][_pledger]);
                overallPledgeWeight =
                    mul(pledgeAmount_amountLoop, wrap(orderWeightNormalized[k])) / sumOfAmountsXNormalizedOrderWeights;
                // Multiply totalRefundBonus by overallWeight to get the individual refund. Loop again.
                // If pledger's address is found in the pledger array again, add to individual total.
                individualRefundBonus = add(individualRefundBonus, mul(overallPledgeWeight, wrap(totalRefundBonus)));
            }
        }
        return unwrap(individualRefundBonus);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getCycleFundingStatus() public view returns (uint256, uint256, bool, bool) {
        uint256 percentOfGoal = ((100 * totalAmountPledged) / cycleTarget);
        return (totalAmountPledged, percentOfGoal, isTargetMet, hasCreatorWithdrawnAllFunds);
    }

    function getPledgerAmount(address _address) public view returns (uint256) {
        return pledgedAmount[_address];
    }
}
