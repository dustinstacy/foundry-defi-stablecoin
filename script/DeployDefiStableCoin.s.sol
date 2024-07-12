// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { Script } from 'forge-std/Script.sol';

/// @title DeployDefiStableCoin
/// @notice Script for deploying the DefiStableCoin contract.
contract DeployDefiStableCoin is Script {
    /// @dev Executes the deployment of the DefiStableCoin contract.
    /// @param _owner The address that will initially own the DefiStableCoin contract.
    /// @return dsc Instance of the deployed DefiStableCoin contract.
    function run(address _owner) external returns (DefiStableCoin dsc) {
        // Start broadcasting deployment transactions
        vm.startBroadcast();
        // Deploy DefiStableCoin contract
        dsc = new DefiStableCoin(_owner);
        // Stop broadcasting deployment transactions
        vm.stopBroadcast();
        // Return deployed contract instance
        return dsc;
    }
}
