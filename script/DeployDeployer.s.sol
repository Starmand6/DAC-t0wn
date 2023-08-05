// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DelegateProjectDeployer} from "../src/DelegateProjectDeployer.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {JBETHPaymentTerminal3_1_1} from "@jbx-protocol/juice-contracts-v3/contracts/JBETHPaymentTerminal3_1_1.sol";

// For deploying deployer contract on ETH Goerli or Mainnet
contract DeployDeployer is Script {
    struct Contracts {
        IJBController3_1 controller;
        IJBOperatorStore operatorStore;
        IJBSingleTokenPaymentTerminalStore3_1_1 paymentTerminalStore3_1_1;
        JBETHPaymentTerminal3_1_1 ethPaymentTerminal3_1_1;
    }

    Contracts public contracts;

    function run()
        external
        returns (
            IJBController3_1,
            IJBOperatorStore,
            IJBSingleTokenPaymentTerminalStore3_1_1,
            JBETHPaymentTerminal3_1_1,
            DelegateProjectDeployer
        )
    {
        HelperConfig helperConfig = new HelperConfig();
        (
            address _controller,
            address _operatorStore,
            address _paymentTerminalStore3_1_1,
            address _ethPaymentTerminal3_1_1
        ) = helperConfig.activeNetworkConfig();
        contracts.controller = IJBController3_1(_controller);
        contracts.operatorStore = IJBOperatorStore(_operatorStore);
        contracts.paymentTerminalStore3_1_1 = IJBSingleTokenPaymentTerminalStore3_1_1(_paymentTerminalStore3_1_1);
        contracts.ethPaymentTerminal3_1_1 = JBETHPaymentTerminal3_1_1(_ethPaymentTerminal3_1_1);
        vm.startBroadcast();
        DelegateProjectDeployer delegateProjectDeployer =
        new DelegateProjectDeployer(_controller, _operatorStore, _paymentTerminalStore3_1_1, _ethPaymentTerminal3_1_1);
        vm.stopBroadcast();
        return (
            contracts.controller,
            contracts.operatorStore,
            contracts.paymentTerminalStore3_1_1,
            contracts.ethPaymentTerminal3_1_1,
            delegateProjectDeployer
        );
    }
}
