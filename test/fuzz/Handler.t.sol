// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from 'forge-std/Test.sol';
import { ERC20Mock } from '@openzeppelin/contracts/mocks/token/ERC20Mock.sol';
import { MockV3Aggregator } from 'test/mocks/MockV3Aggregator.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { DSCEngine } from 'src/DSCEngine.sol';

contract Handler is Test {
    DefiStableCoin dsc;
    DSCEngine dscEngine;

    ERC20Mock wETH;
    ERC20Mock wBTC;
    MockV3Aggregator public ethUSDPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DefiStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        wETH = ERC20Mock(collateralTokens[0]);
        wBTC = ERC20Mock(collateralTokens[1]);

        ethUSDPriceFeed = MockV3Aggregator(dscEngine.getPriceFeedAddress(address(wETH)));
    }

    function mintAndDepositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralDeposited(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        }
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return wETH;
        } else {
            return wBTC;
        }
    }
}
