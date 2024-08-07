// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @title HelperConfig
/// @notice Manages configuration settings and deployment of network-specific contracts
/// such as price feeds and mocks.
contract HelperConfig is Script {
    /// @dev Struct representing network-specific configuration for price feeds and ERC20 tokens.
    struct NetworkConfig {
        /// @dev Address of the Chainlink aggregator contract for ETH-USD price feed.
        address wETHUSDPriceFeed;
        /// @dev Address of the Chainlink aggregator contract for BTC-USD price feed.
        address wBTCUSDPriceFeed;
        /// @dev Address of the ERC20 token contract for Wrapped Ethereum (WETH).
        address wETH;
        /// @dev Address of the ERC20 token contract for Wrapped Bitcoin (WBTC).
        address wBTC;
    }

    /// @dev Active network configuration struct instance.
    NetworkConfig public activeNetworkConfig;

    /// @dev Number of decimal places used for mock price feeds and ERC20 tokens.
    uint8 public constant DECIMALS = 8;
    /// @dev Initial price of ETH in USD for the mock ETH-USD price feed.
    int256 public constant ETH_USD_PRICE = 2000e8;
    /// @dev Initial price of BTC in USD for the mock BTC-USD price feed.
    int256 public constant BTC_USD_PRICE = 15000e8;
    /// @dev Initial balance for mock ERC20 tokens upon deployment.
    uint256 public constant INITIAL_BALANCE = 1000e8;

    /// @dev Constructor function to determine and set the active network configuration
    /// based on the chain ID.
    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    /// @dev Retrieves or creates the Anvil network configuration,
    /// including mock price feeds and ERC20 tokens.
    /// @return anvilNetworkConfig The Anvil network configuration.
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.wETHUSDPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUSDPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcUSDPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wETHMock = new ERC20Mock("Wrapped Ethereum", "WETH", msg.sender, INITIAL_BALANCE);
        ERC20Mock wBTCMock = new ERC20Mock("Wrapped BitCoin", "WBTC", msg.sender, INITIAL_BALANCE);
        vm.stopBroadcast();

        return anvilNetworkConfig = NetworkConfig({
            wETHUSDPriceFeed: address(ethUSDPriceFeed),
            wBTCUSDPriceFeed: address(btcUSDPriceFeed),
            wETH: address(wETHMock),
            wBTC: address(wBTCMock)
        });
    }

    /// @dev Retrieves the Sepolia network configuration, which includes
    /// specific addresses for production environment contracts.
    /// @return sepoliaNetworkConfig The Sepolia network configuration.
    function getSepoliaConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        return sepoliaNetworkConfig = NetworkConfig({
            wETHUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063
        });
    }
}
