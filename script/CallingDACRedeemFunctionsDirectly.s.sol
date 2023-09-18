// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBDidRedeemData3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData3_1_1.sol";

/// Script to call redeemParams() and didRedeem() on the DAC directly.
contract CallingDACRedeemFunctionsDirectly is Script {
    function run(address _DAC, uint256 _projectID) external {
        // Store the deployed JB contracts depending on which network (Mainnet or Goerli) is called for
        DominantJuice DAC = DominantJuice(_DAC);

        JBRedeemParamsData memory redeemParamsData;
        redeemParamsData.holder = msg.sender;
        redeemParamsData.projectId = _projectID;

        JBDidRedeemData3_1_1 memory didRedeemData;
        didRedeemData.projectId = _projectID;
        didRedeemData.holder = msg.sender;

        console.log("Calling DAC.redeemParams() and DAC.didRedeem()...");

        vm.startBroadcast();
        DAC.redeemParams(redeemParamsData); // This call should not change DAC state
        // This next call should revert. Uncomment the line and comment out the above line to test individually.
        //DAC.didRedeem(didRedeemData);
        vm.stopBroadcast();
    }
}
