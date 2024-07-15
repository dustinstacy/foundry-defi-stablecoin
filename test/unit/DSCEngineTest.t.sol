// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Test, console } from 'forge-std/Test.sol';
import { ERC20Mock } from 'test/mocks/ERC20Mock.sol';
import { MockV3Aggregator } from 'test/mocks/MockV3Aggregator.sol';
import { MockFailedTransferFrom } from 'test/mocks/MockFailedTransferFrom.sol';
import { MockFailedTransfer } from 'test/mocks/MockFailedTransfer.sol';
import { MockFailedMintDSC } from 'test/mocks/MockFailedMintDSC.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { DSCEngine } from 'src/DSCEngine.sol';
import { DeployDSCEngine } from 'script/DeployDSCEngine.s.sol';
import { HelperConfig } from 'script/HelperConfig.s.sol';

contract DSCEngineTest is Test {
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

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    function test_RevertsWhen_ArgumentArraysAreNotSameLength() public {
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [ethUSDPriceFeed];
        vm.expectRevert(DSCEngine.DSCEngine__ArraysMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_SetsTokenAddressArrayProperly() public {
        tokenAddresses = [wETH, wBTC];
        assertEq(tokenAddresses, dscEngine.getCollateralTokens());
    }

    function test_SetsPriceFeedAddressArrayProperly() public {
        priceFeedAddresses = [ethUSDPriceFeed, btcUSDPriceFeed];
        assertEq(priceFeedAddresses[0], dscEngine.getPriceFeedAddress(wETH));
        assertEq(priceFeedAddresses[1], dscEngine.getPriceFeedAddress(wBTC));
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT COLLATERAL AND MINT DSC
    //////////////////////////////////////////////////////////////*/

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateralAndMintDSC(wETH, collateralAmount, mintAmount);
        vm.stopPrank();
        _;
        // Resulting Health Factor is 2e18
        // See `test_DispalyHealthFactorSequence()` for insight
    }

    function test_DepositsCollateralToContractAndMintsDSCToUser() public depositCollateralAndMintDSC {
        uint256 userBalance = dsc.balanceOf(user);
        uint256 contractBalance = ERC20Mock(wETH).balanceOf(address(dscEngine));
        assertEq(userBalance, mintAmount);
        assertEq(contractBalance, collateralAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       REDEEM COLLATERAL FOR DSC
    //////////////////////////////////////////////////////////////*/

    function test_ProperlyBurnsDSCAndRedeemsCollateralToUser() public depositCollateralAndMintDSC {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), mintAmount);
        dscEngine.redeemCollateralForDSC(wETH, collateralAmount, mintAmount);
        vm.stopPrank();
        uint256 userAddressEndingETHBalance = ERC20Mock(wETH).balanceOf(user);
        uint256 userAddressEndingDSCBalance = dsc.balanceOf(user);
        assertEq(userAddressEndingETHBalance, collateralAmount);
        assertEq(userAddressEndingDSCBalance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                               LIQUIDATE
    //////////////////////////////////////////////////////////////*/

    function test_RevertsWhen_DebtToCoverIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.liquidate(wETH, user, 0);
    }

    function test_RevertsWhen_HealthFactorNotBroken() public depositCollateralAndMintDSC {
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotBroken.selector);
        dscEngine.liquidate(wETH, user, mintAmount);
        assertEq(userHealthFactor, 2e18);
    }

    function test_SetsTheTokenAmountFromDebtCoveredBonusCollateralAndTotalCollateralToRedeemProperly()
        public
        depositCollateralAndMintDSC
    {
        uint256 LIQUIDATION_BONUS = dscEngine.getLiquidationBonus();
        uint256 LIQUIDATION_PRECISION = dscEngine.getLiquidationPrecision();

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
        uint256 tokenAmountFromDebtCovered = dscEngine.getTokenAmountFromUSD(wETH, debtToCover);
        // tokenAmountFromDebtCovered = (200e18 * 1e18) / (800e8 * 1e10) = 0.25 ether or 25e16
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // bonusCollateral = (25e16 * 10) / 100 = 0.025 ether or 25e15
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        // totalCollateralToReeded = 0.25 ether + 0.025 ether = 0.275 ether or 275e15;
        assertEq(tokenAmountFromDebtCovered, 0.25 ether);
        assertEq(bonusCollateral, 0.025 ether);
        assertEq(totalCollateralToRedeem, 0.275 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT COLLATERAL
    //////////////////////////////////////////////////////////////*/

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(wETH, collateralAmount);
        vm.stopPrank();
        _;
    }

    function test_RevertsIf_DepositAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateral(wETH, 0);
    }

    function test_RevertsIf_UnallowedTokenIsDeposited() public {
        ERC20Mock invalidToken = new ERC20Mock('INVALID', 'INV', DEFAULT_SENDER, collateralAmount);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(invalidToken), collateralAmount);
    }

    function test_SetsUserCollatertalDepositedProperly() public depositCollateral {
        uint256 depositedCollateral = dscEngine.getCollateralDeposited(user, wETH);
        assertEq(depositedCollateral, collateralAmount);
    }

    function test_EmitsCollateralDepositedEvent() public {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(dscEngine), collateralAmount);
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralDeposited(user, wETH, collateralAmount);
        dscEngine.depositCollateral(wETH, collateralAmount);
    }

    function test_TransfersCollateralFromUserToContract() public depositCollateral {
        uint256 userBalance = ERC20Mock(wETH).balanceOf(user);
        uint256 contractBalance = ERC20Mock(wETH).balanceOf(address(dscEngine));
        assertEq(userBalance, 0);
        assertEq(contractBalance, collateralAmount);
    }

    function test_RevertsWhen_TransferFromFails() public {
        address owner = DEFAULT_SENDER;

        vm.startPrank(owner);
        MockFailedTransferFrom mockETH = new MockFailedTransferFrom(owner);
        address mETH = address(mockETH);

        tokenAddresses = [mETH];
        priceFeedAddresses = [ethUSDPriceFeed];

        DefiStableCoin mockDSC = new DefiStableCoin(owner);
        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDSC));

        mockDSC.transferOwnership(address(mockDSCE));
        vm.stopPrank();

        vm.startPrank(user);
        ERC20Mock(mETH).approve(address(mockDSCE), collateralAmount);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCE.depositCollateral(mETH, collateralAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/

    modifier mintDSC() {
        vm.startPrank(user);
        dscEngine.mintDSC(mintAmount);
        vm.stopPrank();
        _;
    }

    function test_RevertsIf_MintAmountIsZero() public depositCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.mintDSC(0);
    }

    function test_SetsUserDSCMintedProperly() public depositCollateralAndMintDSC {
        uint256 userDSCMinted = dscEngine.getDSCMinted(user);
        assertEq(userDSCMinted, mintAmount);
    }

    function test_RevertsIf_HealthFactorIsBroken() public depositCollateralAndMintDSC {
        uint256 alternateMintAmount = 20000e18;
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngine.mintDSC(alternateMintAmount);
    }

    function test_MintsCorrectAmountToUsersAddress() public depositCollateralAndMintDSC {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, mintAmount);
    }

    function test_RevertsWhen_MintFails() public {
        address owner = DEFAULT_SENDER;

        vm.startPrank(owner);
        MockFailedMintDSC mockDSC = new MockFailedMintDSC(owner);
        address mDSC = address(mockDSC);

        tokenAddresses = [wETH];
        priceFeedAddresses = [ethUSDPriceFeed];

        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, priceFeedAddresses, mDSC);

        mockDSC.transferOwnership(address(mockDSCE));
        vm.stopPrank();

        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(mockDSCE), collateralAmount);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDSCE.depositCollateralAndMintDSC(wETH, collateralAmount, mintAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                BURN DSC
    //////////////////////////////////////////////////////////////*/

    function test_SetsDSCMintedOfUserHavingDSCBurntOnBehalfOfToCorrectAmount() public depositCollateralAndMintDSC {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), mintAmount);
        dscEngine.burnDSC(mintAmount);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function test_RevertsIf_BurnAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine.burnDSC(0);
    }

    /*//////////////////////////////////////////////////////////////
                           REDEEM COLLATERAL
    //////////////////////////////////////////////////////////////*/

    function test_SetsTheOriginalDepositersCollateralToCorrectAmount() public depositCollateralAndMintDSC {
        vm.prank(user);
        dscEngine.redeemCollateral(wETH, redeemAmount);
        uint256 userEndingCollateral = dscEngine.getCollateralDeposited(user, wETH);
        uint256 expectedCollateral = collateralAmount - redeemAmount;
        assertEq(userEndingCollateral, expectedCollateral);
    }

    function test_EmitsCollateralRedeemedEvent() public depositCollateralAndMintDSC {
        vm.prank(user);
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(user, user, wETH, redeemAmount);
        dscEngine.redeemCollateral(wETH, redeemAmount);
    }

    function test_TransfersTheCorrectAmountToTheCorrectAddress() public depositCollateralAndMintDSC {
        uint256 userAddressStartingBalance = ERC20Mock(wETH).balanceOf(user);
        vm.prank(user);
        dscEngine.redeemCollateral(wETH, redeemAmount);
        uint256 userAddressEndingBalance = ERC20Mock(wETH).balanceOf(user);
        assertEq(userAddressEndingBalance, (userAddressStartingBalance + redeemAmount));
    }

    function test_CannotBeCalledIfItBreaksHealthFactor() public depositCollateralAndMintDSC {
        uint256 alternateRedeemAmount = 15 ether;

        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngine.redeemCollateral(wETH, alternateRedeemAmount);
    }

    function test_RevertsWhen_TransferFails() public {
        address owner = DEFAULT_SENDER;
        MockFailedTransfer mockETH = new MockFailedTransfer(owner);
        address mETH = address(mockETH);

        tokenAddresses = [mETH];
        priceFeedAddresses = [ethUSDPriceFeed];

        vm.startPrank(owner);
        DefiStableCoin mockDSC = new DefiStableCoin(owner);
        DSCEngine mockDSCE = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDSC));
        ERC20Mock(mETH).mint(user, collateralAmount);
        mockDSC.transferOwnership(address(mockDSCE));
        vm.stopPrank();

        vm.startPrank(user);
        ERC20Mock(mETH).approve(address(mockDSCE), collateralAmount);
        mockDSCE.depositCollateral(mETH, collateralAmount);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDSCE.redeemCollateral(mETH, collateralAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                      GET ACCOUNT COLLATERAL VALUE
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheProperTotalUSDValueOfAllDepositedCollateralByUser() public depositCollateralAndMintDSC {
        vm.startPrank(user);
        ERC20Mock(wBTC).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(wBTC, collateralAmount);
        vm.stopPrank();
        uint256 totalCollateralValueInUSD = dscEngine.getAccountCollateralValue(user);
        uint256 expectedETHUSDValue = dscEngine.getUSDValue(wETH, collateralAmount);
        uint256 expectedBTCUSDValue = dscEngine.getUSDValue(wBTC, collateralAmount);
        assertEq(totalCollateralValueInUSD, (expectedETHUSDValue + expectedBTCUSDValue));
    }

    /*//////////////////////////////////////////////////////////////
                             GET USD VALUE
    //////////////////////////////////////////////////////////////*/
    function test_GetsTheProperUSDValueFromTokenAmount() public view {
        uint256 ethAmount = 10e18;
        // 10e18 * 2000 (Mock ETH_USD_PRICE) = 20000e18
        uint256 expectedUSDValue = 20000e18;
        uint256 actualUSDValue = dscEngine.getUSDValue(wETH, ethAmount);
        assertEq(expectedUSDValue, actualUSDValue);
    }

    /*//////////////////////////////////////////////////////////////
                       GET TOKEN AMOUNT FROM USD
    //////////////////////////////////////////////////////////////*/

    function test_GetsProperTokenAmountFromUSDValue() public view {
        uint256 usdAmount = 20000e18;
        // 20000e18 / 2000 (Mock ETH_USD_PRICE) = 10e18
        uint256 expectedTokenAmount = 10e18;
        uint256 actualTokenAmount = dscEngine.getTokenAmountFromUSD(wETH, usdAmount);
        assertEq(expectedTokenAmount, actualTokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        CALCULATE HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/

    function test_calculateHealthFactorReturnsTheExpectedHealthFactor() public depositCollateralAndMintDSC {
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        uint256 collateralValueInUSD = dscEngine.getUSDValue(wETH, collateralAmount);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(mintAmount, collateralValueInUSD);
        assertEq(userHealthFactor, expectedHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                        GET COLLATERAL TOKENS
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectArrayOfAllowedCollateralTokens() public {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        tokenAddresses = [wETH, wBTC];
        assertEq(collateralTokens, tokenAddresses);
    }

    /*//////////////////////////////////////////////////////////////
                         GET PRICE FEED ADDRESS
    //////////////////////////////////////////////////////////////*/

    function test_GetsCorrectPriceFeedAddressForToken() public view {
        address priceFeedAddress = dscEngine.getPriceFeedAddress(wETH);
        assertEq(priceFeedAddress, ethUSDPriceFeed);
    }

    /*//////////////////////////////////////////////////////////////
                        GET COLLATERAL DEPOSITED
    //////////////////////////////////////////////////////////////*/

    function test_GetsCorrectAmountOfCollateralDepositedByTokenAndUser() public depositCollateralAndMintDSC {
        uint256 wBTCDepositAmount = 10e18;
        vm.startPrank(user);
        ERC20Mock(wBTC).approve(address(dscEngine), wBTCDepositAmount);
        dscEngine.depositCollateral(wBTC, wBTCDepositAmount);
        vm.stopPrank();

        uint256 wETHDeposited = dscEngine.getCollateralDeposited(user, wETH);
        uint256 wBTCDeposited = dscEngine.getCollateralDeposited(user, wBTC);
        assertEq(wETHDeposited, collateralAmount);
        assertEq(wBTCDeposited, wBTCDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                             GET DSC MINTED
    //////////////////////////////////////////////////////////////*/

    function test_GetsCorrectAmountOfDSCMintedbyUser() public depositCollateralAndMintDSC {
        uint256 dscMinted = dscEngine.getDSCMinted(user);
        assertEq(dscMinted, mintAmount);
    }

    /*//////////////////////////////////////////////////////////////
                           GET HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/

    function test_ReportsAccurateHealthFactor() public depositCollateralAndMintDSC {
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        assertEq(userHealthFactor, 2e18);
    }

    function test_DisplayHealthFactorSequence() public depositCollateralAndMintDSC {
        uint256 LIQUIDATION_THRESHOLD = dscEngine.getLiquidationThreshold();
        uint256 LIQUIDATION_PRECISION = dscEngine.getLiquidationPrecision();
        uint256 PRECISION = dscEngine.getPrecision();

        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(user);
        console.log(totalDSCMinted);
        // totalDSCMinted = 10000e18 (10000 DSC)
        console.log(collateralValueInUSD);
        // collateralValueInUSD = 40000e18 (20 ETH)
        console.log((collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION);
        // collateralAdjustForThreshold = 20000e18 (50%) Adjusted to ensure 2:1 ratio collateral to debt
        console.log(
            (((collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION) * PRECISION) / totalDSCMinted
        );
        // ((20000e18 * 1e18(PRECISION used to ensure proper decimals)) / 10000e18) = 2e18
        // healthFactor = 2e18
    }

    function test_HealthFactorCanGoBelowOne() public depositCollateralAndMintDSC {
        int256 updatedETHPrice = 900e8;
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(updatedETHPrice);
        uint256 updatedUserHealthFactor = dscEngine.getHealthFactor(user);
        assertLt(updatedUserHealthFactor, 1e18);
        assertEq(updatedUserHealthFactor, 0.9e18);
    }

    function test_RevertsWhen_HealthFactorIsBroken() public {
        uint256 alternateMintAmount = 30000e18;
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(dscEngine), collateralAmount);
        dscEngine.depositCollateral(wETH, collateralAmount);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dscEngine.mintDSC(alternateMintAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         GET ACCOUNT INFORMATION
    //////////////////////////////////////////////////////////////*/

    function test_RetrievesAccurateUserAccountInformation() public depositCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(user);
        uint256 expectedDSCMinted = 0;
        uint256 expectedTokenCollateralAmount = dscEngine.getTokenAmountFromUSD(wETH, collateralValueInUSD);
        assertEq(totalDSCMinted, expectedDSCMinted);
        assertEq(collateralAmount, expectedTokenCollateralAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       GET LIQUIDATION THRESHOLD
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectLiquidationThreshold() public view {
        uint256 LIQUIDATION_THRESHOLD = dscEngine.getLiquidationThreshold();
        assertEq(LIQUIDATION_THRESHOLD, 50);
    }

    /*//////////////////////////////////////////////////////////////
                         GET LIQUIDATION BONUS
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectLiquidationBonus() public view {
        uint256 LIQUIDATION_BONUS = dscEngine.getLiquidationBonus();
        assertEq(LIQUIDATION_BONUS, 10);
    }

    /*//////////////////////////////////////////////////////////////
                       GET LIQUIDATION PRECISION
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectLiquidationPrecision() public view {
        uint256 LIQUIDATION_PRECISION = dscEngine.getLiquidationPrecision();
        assertEq(LIQUIDATION_PRECISION, 100);
    }

    /*//////////////////////////////////////////////////////////////
                       GET ADDITIONAL FEED PRECISION
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectAdditionalFeedPrecision() public view {
        uint256 ADDITIONAL_FEED_PRECISION = dscEngine.getAdditionaFeedPrecision();
        assertEq(ADDITIONAL_FEED_PRECISION, 1e10);
    }

    /*//////////////////////////////////////////////////////////////
                             GET PRECISION
    //////////////////////////////////////////////////////////////*/

    function test_GetsTheCorrectPrecision() public view {
        uint256 PRECISION = dscEngine.getPrecision();
        assertEq(PRECISION, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                                GET DSC
    //////////////////////////////////////////////////////////////*/

    function test_GetsCorrectDSCAddres() public view {
        address dscAddress = dscEngine.getDSC();
        assertEq(address(dsc), dscAddress);
    }
}
