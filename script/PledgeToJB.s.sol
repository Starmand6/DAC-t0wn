// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {JBETHPaymentTerminal3_1_2} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_2.sol";

/// Script to pledge directly through the JB Payment Terminal contract
contract PledgeToJB is Script {
    function run(uint256 _projectID, uint256 _amount) external {
        // Store the deployed JB contracts depending on which network (Mainnet or Goerli) is called for
        HelperConfig helperConfig = new HelperConfig();
        (,, address _ethPaymentTerminal3_1_2) = helperConfig.activeNetworkConfig();
        JBETHPaymentTerminal3_1_2 jbETHPaymentTerminal3_1_2 = JBETHPaymentTerminal3_1_2(_ethPaymentTerminal3_1_2);

        vm.startBroadcast();
        console.log("Sending pledge request to Juicebox");
        jbETHPaymentTerminal3_1_2.pay{value: _amount}(
            _projectID, _amount, 0x000000000000000000000000000000000000EEEe, msg.sender, 0, false, "", ""
        );
        console.log("Pledge successful!");
        vm.stopBroadcast();
    }
}
