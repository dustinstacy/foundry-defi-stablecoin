// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { DSCEngine } from 'src/DSCEngine.sol';
import { HelperConfig } from './HelperConfig.s.sol';
import { Script } from 'forge-std/Script.sol';

/// @title DeployDSCEngine
/// @notice Script for deploying the DSCEngine contract and its dependencies.
contract DeployDSCEngine is Script {
    /// @dev Arrays holding addresses of tokens and price feeds used by the DSCEngine contract.
    /// @notice `tokenAddresses` contains addresses of collateral tokens supported by the system.
    /// `priceFeedAddresses` contains addresses of Chainlink aggregators providing price feeds for corresponding tokens.
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /// @dev Executes the deployment of DSCEngine and related contracts.
    /// @param _owner The address that will initially own the DefiStableCoin contract.
    /// @return dsc Instance of the deployed DefiStableCoin contract.
    /// @return dscEngine Instance of the deployed DSCEngine contract.
    /// @return config Instance of the deployed HelperConfig contract.
    function run(address _owner) external returns (DefiStableCoin dsc, DSCEngine dscEngine, HelperConfig config) {
        // Deploy HelperConfig contract for retrieving network configurations
        config = new HelperConfig();

        // Retrieve active network configurations for tokens and price feeds
        (address wETHUSDPriceFeed, address wBTCUSDPriceFeed, address wETH, address wBTC) = config.activeNetworkConfig();

        // Define token and price feed addresses for DSCEngine deployment
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHUSDPriceFeed, wBTCUSDPriceFeed];

        // Start broadcasting deployment transactions
        vm.startBroadcast();

        // Deploy DefiStableCoin and DSCEngine contracts and transfer ownership to DSCEngine
        dsc = new DefiStableCoin(_owner);
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));

        // Stop broadcasting deployment transactions
        vm.stopBroadcast();

        // Return deployed contract instances
        return (dsc, dscEngine, config);
    }
}
