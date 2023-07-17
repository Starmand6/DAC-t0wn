// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBSingleTokenPaymentTerminalStore} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {IJBSingleTokenPaymentTerminal} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol";
import {JBETHPaymentTerminal3_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";

contract DeployDominantJuice is Script {
    function run()
        external
        returns (DominantJuice, IJBController3_1, IJBSingleTokenPaymentTerminalStore3_1_1, JBETHPaymentTerminal3_1_1)
    {
        HelperConfig helperConfig = new HelperConfig();
        (address _controller, address _paymentTerminalStore3_1_1, address _ethPaymentTerminal3_1_1) =
            helperConfig.activeNetworkConfig();
        IJBController3_1 controller = IJBController3_1(_controller);
        IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore3_1_1 =
            IJBSingleTokenPaymentTerminalStore3_1_1(_paymentTerminalStore3_1_1);
        JBETHPaymentTerminal3_1_1 ethPaymentTerminal3_1_1 = JBETHPaymentTerminal3_1_1(_ethPaymentTerminal3_1_1);

        vm.startBroadcast();
        DominantJuice dominantJuice = new DominantJuice();
        vm.stopBroadcast();
        return (dominantJuice, controller, paymentTerminalStore3_1_1, ethPaymentTerminal3_1_1);
    }
}
