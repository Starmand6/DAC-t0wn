// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DominantJuice} from "../src/DominantJuice.sol";

contract DeployDominantJuice is Script {
    function run() external returns (DominantJuice) {
        vm.startBroadcast();
        DominantJuice dominantJuice = new DominantJuice();
        vm.stopBroadcast();
        return (dominantJuice);
    }
}
