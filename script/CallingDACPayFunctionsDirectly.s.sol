// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBDidPayData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData3_1_1.sol";

/// Script to call payParams() and didPay() on the DAC directly.
contract CallingDACPayFunctionsDirectly is Script {
    function run(address _DAC, uint256 _projectID, uint256 _amount) external {
        // Store the deployed JB contracts depending on which network (Mainnet or Goerli) is called for
        DominantJuice DAC = DominantJuice(_DAC);

        JBPayParamsData memory payParamsData;
        payParamsData.amount.value = _amount;

        JBDidPayData3_1_1 memory didPayData;
        didPayData.projectId = _projectID;
        didPayData.payer = msg.sender;
        didPayData.amount.value = _amount;

        console.log("Calling DAC.payParams() and DAC.didPay()...");

        vm.startBroadcast();
        DAC.payParams(payParamsData); // This call should not change DAC state
        // This next call should revert. Uncomment the line and comment out the above line to test individually.
        //DAC.didPay(didPayData);
        vm.stopBroadcast();
    }
}
