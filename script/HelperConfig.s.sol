// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

// HelperConfig retrieves the JB deployed contract addresses (Goerli or Mainnet) necessary for function calls.
contract HelperConfig is Script {
    struct NetworkConfig {
        address controller;
        address paymentTerminalStore3_1_1;
        address jbETHPaymentTerminal3_1_2;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 5) {
            activeNetworkConfig = getGoerliConfig();
        }
        if (block.chainid == 1) {
            activeNetworkConfig = getMainnetConfig();
        }
    }

    function getGoerliConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory goerliConfig = NetworkConfig({
            controller: 0x1d260DE91233e650F136Bf35f8A4ea1F2b68aDB6, // JBController 3_1
            paymentTerminalStore3_1_1: 0x5d8eC74256DB2326843714B852df3acE45144492,
            jbETHPaymentTerminal3_1_2: 0xd89Ed8008961F68Aab849f49e122f9a1266240Db
        });
        return goerliConfig;
    }

    function getMainnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory mainnetConfig = NetworkConfig({
            controller: 0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b, // JBController 3_1
            paymentTerminalStore3_1_1: 0x82129d4109625F94582bDdF6101a8Cd1a27919f5,
            jbETHPaymentTerminal3_1_2: 0x1d9619E10086FdC1065B114298384aAe3F680CC0
        });
        return mainnetConfig;
    }
}
