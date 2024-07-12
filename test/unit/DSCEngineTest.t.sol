// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Test } from 'forge-std/Test.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { DSCEngine } from 'src/DSCEngine.sol';
import { DeployDSCEngine } from 'script/DeployDSCEngine.s.sol';
import { HelperConfig } from 'script/HelperConfig.s.sol';

contract DSCEngineTest is Test {
    DeployDSCEngine deployer;
    DefiStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUSDPricefeed;
    address weth;
    address btcUSDPricefeed;
    address wbtc;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run(msg.sender);
        (ethUSDPricefeed, btcUSDPricefeed, weth, wbtc) = config.activeNetworkConfig();
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    function test_RevertsWhen_ArgumentArraysAreNotSameLength() public {
        tokenAddresses = [address(0x01), address(0x02)];
        priceFeedAddresses = [address(0x03)];
        vm.expectRevert(DSCEngine.DSCEngine__ArraysMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_SetsTokenAddressArrayProperly() public {
        tokenAddresses = [weth, wbtc];
        assertEq(tokenAddresses, dscEngine.getCollateralTokens());
    }

    function test_SetsPriceFeedAddressArrayProperly() public {
        priceFeedAddresses = [ethUSDPricefeed, btcUSDPricefeed];
        assertEq(priceFeedAddresses[0], dscEngine.getPriceFeedAddress(weth));
        assertEq(priceFeedAddresses[1], dscEngine.getPriceFeedAddress(wbtc));
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT COLLATERAL
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      GET ACCOUNT COLLATERAL VALUE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             GET USD VALUE
    //////////////////////////////////////////////////////////////*/
    function test_GetUSDValue() public view {
        uint256 ethAmount = 10e18;
        // 10e18 * 2000 (Mock ETH_USD_PRICE) = 20000e18;
        uint256 expectedUSDValue = 20000e18;
        uint256 actualUSDValue = dscEngine.getUSDValue(weth, ethAmount);
        assertEq(expectedUSDValue, actualUSDValue);
    }

    /*//////////////////////////////////////////////////////////////
                   _REVERT IF HEALTH FACTOR IS BROKEN
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                        _GET ACCOUNT INFORMATION
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                             _HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/
}
