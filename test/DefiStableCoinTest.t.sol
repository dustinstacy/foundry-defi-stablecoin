// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from 'forge-std/Test.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

contract DefiStableCoinTest is Test {
    DefiStableCoin dsc;

    address USER = makeAddr('user');
    uint256 mintAmount = 20e18;
    uint256 burnAmount = 20e18;

    function setUp() public {
        dsc = new DefiStableCoin(DEFAULT_SENDER);
        vm.deal(USER, 1 ether);
    }

    function testConstructorSetsNameAndSymbolCorrectly() public view {
        string memory expectedName = 'Ballast';
        string memory expectedSymbol = 'BAL';
        assertEq(dsc.name(), expectedName);
        assertEq(dsc.symbol(), expectedSymbol);
    }

    function testConstructorSetsOwnerProperly() public view {
        address expectedOwner = DEFAULT_SENDER;
        assertEq(dsc.owner(), expectedOwner);
    }

    function testMintOnlyCallableByOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        dsc.mint(USER, mintAmount);
    }

    function testMintCanNotBeToZeroAddress() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), mintAmount);
    }

    function testMintAmountMustBeGreaterThanZero() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.mint(DEFAULT_SENDER, 0);
    }

    function testMintsTheRightAmountToTheCorrectAddress() public {
        uint256 startingBalance = dsc.balanceOf(DEFAULT_SENDER);
        vm.prank(DEFAULT_SENDER);
        dsc.mint(DEFAULT_SENDER, mintAmount);
        uint256 endingBalance = dsc.balanceOf(DEFAULT_SENDER);
        assertEq(startingBalance + mintAmount, endingBalance);
    }

    function testBurnOnlyCallableByOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        dsc.mint(USER, mintAmount);
    }

    function testBurnAmountMustBeGreaterThanZero() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testBurnAmountCannotExceedBalance() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(burnAmount);
    }
}
