// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";

/// Script for the Campaign Manager to withdraw the refund bonus from the dominant assurance contract (DAC).
contract CreatorWithdraw is Script {
    function run(address _DAC, address payable _receiver, uint256 _amount) external {
        vm.startBroadcast();
        DominantJuice DAC = DominantJuice(_DAC);
        console.log("Calling creatorWithdraw() on the DAC...");
        DAC.creatorWithdraw(_receiver, _amount);
        console.log("Withdraw successful!");
        vm.stopBroadcast();
    }
}
