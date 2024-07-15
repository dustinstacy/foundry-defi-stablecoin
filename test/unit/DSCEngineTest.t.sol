// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Test, console } from 'forge-std/Test.sol';
import { ERC20Mock } from 'test/mocks/ERC20Mock.sol';
import { MockV3Aggregator } from 'test/mocks/MockV3Aggregator.sol';
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
    address public user = address(1);
    uint256 public collateralAmount = 20 ether;
    uint256 public mintAmount = 10000 ether;

    uint256 public constant STARTING_USER_BALANCE = 20 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
    }

    function test_DepositsCollateralToContractAndMintsDSCToUser() public depositCollateralAndMintDSC {
        uint256 userBalance = dsc.balanceOf(user);
        uint256 contractBalance = ERC20Mock(wETH).balanceOf(address(dscEngine));
        assertEq(userBalance, mintAmount);
        assertEq(contractBalance, collateralAmount);
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

    function test_RevertsWhen_DepositTransferFails() public {}

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

    function test_RevertsIf_HealthFactorIsBroken() public depositCollateral {}

    function test_MintsCorrectAmountToUsersAddress() public depositCollateralAndMintDSC {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, mintAmount);
    }

    function test_RevertsWhen_MintFails() public depositCollateral {}

    /*//////////////////////////////////////////////////////////////
                       REDEEM COLLATERAL FOR DSC
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                           REDEEM COLLATERAL
    //////////////////////////////////////////////////////////////*/

    function test_SetsTheOriginalDepositersCollateralToCorrectAmount() public {}

    function test_EmitsCollateralRedeemedEvent() public {}

    /*//////////////////////////////////////////////////////////////
                               LIQUIDATE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      GET ACCOUNT COLLATERAL VALUE
    //////////////////////////////////////////////////////////////*/

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
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(user);
        console.log(totalDSCMinted);
        // totalDSCMinted = 10000e18 (10000 DSC)
        console.log(collateralValueInUSD);
        // collateralValueInUSD = 40000e18 (20 ETH)
        console.log((collateralValueInUSD * 50) / 100);
        // collateralAdjustForThreshold = 20000e18 (50%) Adjusted to ensure 2:1 ratio collateral to debt
        console.log((((collateralValueInUSD * 50) / 100) * 1e18) / totalDSCMinted);
        // healthFactor = 2e18
    }

    function test_HealthFactorCanGoBelowOne() public depositCollateralAndMintDSC {
        int256 updatedETHPrice = 900e8;
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(updatedETHPrice);
        console.log(dscEngine.getAccountCollateralValue(user));

        uint256 updatedUserHealthFactor = dscEngine.getHealthFactor(user);
        console.log(updatedUserHealthFactor);

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
}
