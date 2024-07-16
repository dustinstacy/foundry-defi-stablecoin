// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from 'forge-std/Test.sol';
import { StdInvariant } from 'forge-std/StdInvariant.sol';
import { DeployDSCEngine } from 'script/DeployDSCEngine.s.sol';
import { DSCEngine } from 'src/DSCEngine.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { HelperConfig } from 'script/HelperConfig.s.sol';
import { ERC20Mock } from 'test/mocks/ERC20Mock.sol';
import { Handler } from 'test/fuzz/Handler.t.sol';

contract Invariants is StdInvariant, Test {
    DeployDSCEngine deployer;
    DSCEngine dscEngine;
    DefiStableCoin dsc;
    HelperConfig config;
    Handler handler;

    address ethUSDPriceFeed;
    address btcUSDPriceFeed;
    address wETH;
    address wBTC;

    function setUp() external {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run(DEFAULT_SENDER);
        (ethUSDPriceFeed, btcUSDPriceFeed, wETH, wBTC) = config.activeNetworkConfig();
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWETHDeposited = ERC20Mock(wETH).balanceOf(address(dscEngine));
        uint256 totalWBTCDeposited = ERC20Mock(wBTC).balanceOf(address(dscEngine));
        uint256 wETHValue = dscEngine.getUSDValue(wETH, totalWETHDeposited);
        uint256 wBTCValue = dscEngine.getUSDValue(wBTC, totalWBTCDeposited);
        assert(wETHValue + wBTCValue >= totalSupply);
    }
}
