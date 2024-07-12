// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { Test } from 'forge-std/Test.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';

contract DefiStableCoinTest is Test {
    DefiStableCoin dsc;

    address USER = makeAddr('user');
    uint256 mintAmount = 20e18;
    uint256 burnAmount = 20e18;

    function setUp() public {
        dsc = new DefiStableCoin(DEFAULT_SENDER);
        vm.deal(USER, 1 ether);
    }

    ///
    /// Constructor
    ///
    function test_ConstructorSetsNameAndSymbolCorrectly() public view {
        string memory expectedName = 'Ballast';
        string memory expectedSymbol = 'BAL';
        assertEq(dsc.name(), expectedName);
        assertEq(dsc.symbol(), expectedSymbol);
    }

    function test_ConstructorSetsOwnerProperly() public view {
        address expectedOwner = DEFAULT_SENDER;
        assertEq(dsc.owner(), expectedOwner);
    }

    ///
    /// Mint
    ///
    function test_RevertIf_MintCallerIsNotTheOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        dsc.mint(USER, mintAmount);
    }

    function test_RevertIf_ToAddressIsZero() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), mintAmount);
    }

    function test_RevertIf_MintAmountIsZero() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.mint(DEFAULT_SENDER, 0);
    }

    function test_MintsTheRightAmountToTheCorrectAddress() public {
        uint256 startingBalance = dsc.balanceOf(DEFAULT_SENDER);
        vm.prank(DEFAULT_SENDER);
        dsc.mint(DEFAULT_SENDER, mintAmount);
        uint256 endingBalance = dsc.balanceOf(DEFAULT_SENDER);
        assertEq(startingBalance + mintAmount, endingBalance);
    }

    ///
    /// Burn
    ///
    function test_RevertIf_BurnCallerIsNotTheOwner() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        dsc.mint(USER, mintAmount);
    }

    function test_RevertIf_BurnAmountIsZero() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function test_RevertIf_BurnAmountExceedsUserBalance() public {
        vm.prank(DEFAULT_SENDER);
        vm.expectRevert(DefiStableCoin.DefiStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(burnAmount);
    }
}
