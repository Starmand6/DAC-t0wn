// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";

/// Script for the Campaign Manager to deposit the refund bonus into the dominant assurance contract (DAC).
contract DepositRefundBonus is Script {
    function run(address _DAC, uint256 _amount) external {
        DominantJuice DAC = DominantJuice(_DAC);
        console.log("Depositing refund bonus into DAC...");

        vm.startBroadcast();
        DAC.depositRefundBonus{value: _amount}();
        vm.stopBroadcast();

        console.log("Deposit successful!");
    }
}
