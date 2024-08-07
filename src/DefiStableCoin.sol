// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

///
/// @title DefiStableCoin
/// @author Dustin Stacy
/// @notice Collateral: Exogenous (ETH & BTC)
/// @notice Minting: Algorithmic
/// @notice Relative Stability: Pegged to USD
/// @notice This is the contract meant to be governed by DSCEngine. This contract
/// is just the ERC20 implementation of our stablecoin system.
///
contract DefiStableCoin is ERC20Burnable, Ownable {
    /// @dev Emitted when attempting to perform an action with an amount that must be more than zero.
    error DefiStableCoin__AmountMustBeMoreThanZero();

    /// @dev Emitted when attempting to burn an amount that exceeds the sender's balance.
    error DefiStableCoin__BurnAmountExceedsBalance();

    /// @dev Emitted when attempting to perform an action with a zero address.
    error DefiStableCoin__NotZeroAddress();

    /// @param _owner The initial owner of the contract
    constructor(address _owner) ERC20("Defi StableCoin", "DSC") Ownable(_owner) {}

    /// @dev Function to mint tokens
    /// @param _to The address that will receive the minted tokens
    /// @param _amount The amount of tokens to mint
    /// @return A boolean that indicates if the operation was successful
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DefiStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DefiStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    /// @dev Function to burn tokens
    /// @param _amount The amount of tokens to burn
    /// @inheritdoc ERC20Burnable
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DefiStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DefiStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
