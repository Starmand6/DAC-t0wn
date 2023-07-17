// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DominantJuice} from "../src/DominantJuice.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBSingleTokenPaymentTerminalStore} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {IJBSingleTokenPaymentTerminal} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminal.sol";
import {JBETHPaymentTerminal3_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";
import {MyDelegateDeployer} from "../src/MyDelegateDeployer.sol";
import {MyDelegateProjectDeployer} from "../src/MyDelegateProjectDeployer.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";

// For deploying contracts on Goerli
contract DeployContracts is Script {
    // Put contracts in data struct to avoid stack too deep compiler error.
    struct Contracts {
        IJBController3_1 controller;
        IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore3_1_1;
        JBETHPaymentTerminal3_1_1 ethPaymentTerminal3_1_1;
        //DominantJuice dominantJuice;
        IJBDelegatesRegistry registry;
        IJBOperatorStore operatorStore;
    }

    Contracts public contracts;

    function run()
        external
        returns (
            IJBController3_1,
            IJBSingleTokenPaymentTerminalStore3_1_1,
            JBETHPaymentTerminal3_1_1,
            MyDelegateDeployer,
            MyDelegateProjectDeployer
        )
    {
        HelperConfig helperConfig = new HelperConfig();
        (address _controller, address _paymentTerminalStore3_1_1, address _ethPaymentTerminal3_1_1) =
            helperConfig.activeNetworkConfig();
        contracts.controller = IJBController3_1(_controller);
        contracts.paymentTerminalStore3_1_1 = IJBSingleTokenPaymentTerminalStore3_1_1(_paymentTerminalStore3_1_1);
        contracts.ethPaymentTerminal3_1_1 = JBETHPaymentTerminal3_1_1(_ethPaymentTerminal3_1_1);
        //contracts.dominantJuice = DominantJuice(payable(0x99b63066dbA6df960bf352438a2d10eE17846154));
        contracts.registry = IJBDelegatesRegistry(0xCe3Ebe8A7339D1f7703bAF363d26cD2b15D23C23);
        contracts.operatorStore = IJBOperatorStore(0x99dB6b517683237dE9C494bbd17861f3608F3585);

        vm.startBroadcast();
        // DominantJuice dominantJuice = new DominantJuice();
        MyDelegateDeployer delegateDeployer = new MyDelegateDeployer(contracts.registry);
        MyDelegateProjectDeployer projectDeployer =
        new MyDelegateProjectDeployer(delegateDeployer, contracts.controller, contracts.operatorStore, contracts.paymentTerminalStore3_1_1, contracts.ethPaymentTerminal3_1_1);
        vm.stopBroadcast();
        return (
            contracts.controller,
            contracts.paymentTerminalStore3_1_1,
            contracts.ethPaymentTerminal3_1_1,
            delegateDeployer,
            projectDeployer
        );
    }
}
