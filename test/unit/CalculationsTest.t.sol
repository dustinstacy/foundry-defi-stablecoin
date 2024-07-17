// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from 'forge-std/Test.sol';
import { ERC20Mock } from 'test/mocks/ERC20Mock.sol';
import { MockV3Aggregator } from 'test/mocks/MockV3Aggregator.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { DSCEngine } from 'src/DSCEngine.sol';
import { DeployDSCEngine } from 'script/DeployDSCEngine.s.sol';
import { HelperConfig } from 'script/HelperConfig.s.sol';
import { Calculations } from 'src/libraries/Calculations.sol';

contract CalculationsTest is Test {
    DeployDSCEngine public deployer;
    DefiStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;

    address public ethUSDPriceFeed;
    address public btcUSDPriceFeed;
    address public wETH;
    address public wBTC;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public user = makeAddr('user');
    address public liquidator = makeAddr('liquidator');
    uint256 public collateralAmount = 20 ether;
    uint256 public mintAmount = 10000 ether;
    uint256 public redeemAmount = 5 ether;
    uint256 public debtToCover = 200 ether;

    uint256 public constant STARTING_USER_BALANCE = 20 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run(DEFAULT_SENDER);
        (ethUSDPriceFeed, btcUSDPriceFeed, wETH, wBTC) = config.activeNetworkConfig();
        vm.deal(user, STARTING_USER_BALANCE);
        ERC20Mock(wETH).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wBTC).mint(user, STARTING_USER_BALANCE);
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateralAndMintDSC(wETH, collateralAmount, mintAmount);
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        CALCULATE HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/

    function test_calculateHealthFactorReturnsTheExpectedHealthFactor() public depositCollateralAndMintDSC {
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        uint256 collateralValueInUSD = Calculations.calculateUSDValue(ethUSDPriceFeed, collateralAmount);
        uint256 expectedHealthFactor = Calculations.calculateHealthFactor(mintAmount, collateralValueInUSD);
        assertEq(userHealthFactor, expectedHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                  CALCULATE TOTAL COLLATERAL TO REDEEM
    //////////////////////////////////////////////////////////////*/

    function test_SetsTheTokenAmountFromDebtCoveredBonusCollateralAndTotalCollateralToRedeemProperly()
        public
        depositCollateralAndMintDSC
    {
        uint256 LIQUIDATION_BONUS = Calculations.getLiquidationBonus();
        uint256 LIQUIDATION_PRECISION = Calculations.getLiquidationPrecision();

        // Set up liquidator address.
        ERC20Mock(wETH).mint(liquidator, collateralAmount);
        vm.startPrank(liquidator);
        ERC20Mock(wETH).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateralAndMintDSC(wETH, collateralAmount, debtToCover);
        vm.stopPrank();

        // Update ETH price to break `user`'s health factor.
        int256 updatedETHPrice = 800e8;
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(updatedETHPrice);

        //liquidate
        vm.startPrank(liquidator);
        dsc.approve(address(dscEngine), debtToCover);
        dscEngine.liquidate(wETH, user, debtToCover);
        vm.stopPrank();
        uint256 tokenAmountFromDebtCovered = Calculations.calculateTokenAmountFromUSD(ethUSDPriceFeed, debtToCover);
        // tokenAmountFromDebtCovered = (200e18 * 1e18) / (800e8 * 1e10) = 0.25 ether or 25e16
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // bonusCollateral = (25e16 * 10) / 100 = 0.025 ether or 25e15
        uint256 expectedTotalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        // totalCollateralToReeded = 0.25 ether + 0.025 ether = 0.275 ether or 275e15;
        uint256 actualTotalCollateralToRedeem = Calculations.calculateTotalCollateralToRedeem(
            ethUSDPriceFeed,
            debtToCover
        );
        assertEq(tokenAmountFromDebtCovered, 0.25 ether);
        assertEq(bonusCollateral, 0.025 ether);
        assertEq(expectedTotalCollateralToRedeem, 0.275 ether);
        assertEq(expectedTotalCollateralToRedeem, actualTotalCollateralToRedeem);
    }

    /*//////////////////////////////////////////////////////////////
                          CALCULATE USD VALUE
    //////////////////////////////////////////////////////////////*/
    function test_GetsTheProperUSDValueFromTokenAmount() public view {
        uint256 ethAmount = 10e18;
        // 10e18 * 2000 (Mock ETH_USD_PRICE) = 20000e18
        uint256 expectedUSDValue = 20000e18;
        uint256 actualUSDValue = Calculations.calculateUSDValue(ethUSDPriceFeed, ethAmount);
        assertEq(expectedUSDValue, actualUSDValue);
    }

    /*//////////////////////////////////////////////////////////////
                       CALCULATE TOKEN AMOUNT FROM USD
    //////////////////////////////////////////////////////////////*/

    function test_GetsProperTokenAmountFromUSDValue() public view {
        uint256 usdAmount = 20000e18;
        // 20000e18 / 2000 (Mock ETH_USD_PRICE) = 10e18
        uint256 expectedTokenAmount = 10e18;
        uint256 actualTokenAmount = Calculations.calculateTokenAmountFromUSD(ethUSDPriceFeed, usdAmount);
        assertEq(expectedTokenAmount, actualTokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       GET LIQUIDATION THRESHOLD
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectLiquidationThreshold() public pure {
        uint256 LIQUIDATION_THRESHOLD = Calculations.getLiquidationThreshold();
        assertEq(LIQUIDATION_THRESHOLD, 50);
    }

    /*//////////////////////////////////////////////////////////////
                         GET LIQUIDATION BONUS
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectLiquidationBonus() public pure {
        uint256 LIQUIDATION_BONUS = Calculations.getLiquidationBonus();
        assertEq(LIQUIDATION_BONUS, 10);
    }

    /*//////////////////////////////////////////////////////////////
                       GET LIQUIDATION PRECISION
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectLiquidationPrecision() public pure {
        uint256 LIQUIDATION_PRECISION = Calculations.getLiquidationPrecision();
        assertEq(LIQUIDATION_PRECISION, 100);
    }

    /*//////////////////////////////////////////////////////////////
                       GET ADDITIONAL FEED PRECISION
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectAdditionalFeedPrecision() public pure {
        uint256 ADDITIONAL_FEED_PRECISION = Calculations.getAdditionaFeedPrecision();
        assertEq(ADDITIONAL_FEED_PRECISION, 1e10);
    }

    /*//////////////////////////////////////////////////////////////
                             GET PRECISION
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectPrecision() public pure {
        uint256 PRECISION = Calculations.getPrecision();
        assertEq(PRECISION, 1e18);
    }
}
