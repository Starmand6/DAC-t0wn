// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {DominantJuice} from "../src/DominantJuice.sol";

/// Script to assign the Campaign Manager role for the dominant assurance contract (DAC).
contract AssignCampaignManagerRole is Script {
    function run(address _DAC, address _newCampaignManager) external {
        vm.startBroadcast();
        DominantJuice DAC = DominantJuice(_DAC);
        bool hasDefaultAdminRole = DAC.hasRole(0x0, msg.sender);
        console.log("Does msg.sender have DEFAULT_ADMIN_ROLE? ", hasDefaultAdminRole);

        console.log("Assigning DAC Campaign Manager Role...");
        DAC.grantRole(keccak256("CAMPAIGN_MANAGER_ROLE"), _newCampaignManager);
        console.log("DAC Campaign Manager Role has been assigned to:", _newCampaignManager);
        vm.stopBroadcast();
    }
}
