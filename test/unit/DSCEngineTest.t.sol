// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Test } from 'forge-std/Test.sol';
import { ERC20Mock } from 'test/mocks/ERC20Mock.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { DSCEngine } from 'src/DSCEngine.sol';
import { DeployDSCEngine } from 'script/DeployDSCEngine.s.sol';
import { HelperConfig } from 'script/HelperConfig.s.sol';

contract DSCEngineTest is Test {
    DeployDSCEngine public deployer;
    DefiStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;

    address public ethUSDPricefeed;
    address public btcUSDPricefeed;
    address public wETH;
    address public wBTC;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public user = address(1);
    uint256 public collateralAmount = 10 ether;
    uint256 public mintAmount = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dsc, dscEngine, config) = deployer.run(DEFAULT_SENDER);
        (ethUSDPricefeed, btcUSDPricefeed, wETH, wBTC) = config.activeNetworkConfig();
        vm.deal(user, STARTING_USER_BALANCE);
        ERC20Mock(wETH).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wBTC).mint(user, STARTING_USER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    function test_RevertsWhen_ArgumentArraysAreNotSameLength() public {
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [ethUSDPricefeed];
        vm.expectRevert(DSCEngine.DSCEngine__ArraysMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_SetsTokenAddressArrayProperly() public {
        tokenAddresses = [wETH, wBTC];
        assertEq(tokenAddresses, dscEngine.getCollateralTokens());
    }

    function test_SetsPriceFeedAddressArrayProperly() public {
        priceFeedAddresses = [ethUSDPricefeed, btcUSDPricefeed];
        assertEq(priceFeedAddresses[0], dscEngine.getPriceFeedAddress(wETH));
        assertEq(priceFeedAddresses[1], dscEngine.getPriceFeedAddress(wBTC));
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
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(0x123), 1e18);
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

    function test_RevertsWhen_TransferFails() public {}

    /*//////////////////////////////////////////////////////////////
                                MINT DSC
    //////////////////////////////////////////////////////////////*/

    function test_RevertsIf_MintAmountIsZero() public {}

    function test_SetsUserDSCMintedProperly() public {}

    function test_RevertsIf_HealthFactorIsBroken() public {}

    function test_MintsCorrectAmountToUsersAddress() public {}

    function test_RevertsWhen_MintFails() public {}

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
        uint256 actualUSDValue = dscEngine.getUSDValue(wETH, ethAmount);
        assertEq(expectedUSDValue, actualUSDValue);
    }

    /*//////////////////////////////////////////////////////////////
                   _REVERT IF HEALTH FACTOR IS BROKEN
    //////////////////////////////////////////////////////////////*/

    function test_RevertsWhen_UserBreaksHealthFactor() public {}

    /*//////////////////////////////////////////////////////////////
                        _GET ACCOUNT INFORMATION
    //////////////////////////////////////////////////////////////*/

    function test_RetrievesAccurateUserAccountInformation() public {}

    /*//////////////////////////////////////////////////////////////
                             _HEALTH FACTOR
    //////////////////////////////////////////////////////////////*/

    function test_ReportsAccurateHealthFactor() public {}

    function test_HealthFactorCanGoBelowOne() public {}
}
