// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20Burnable, ERC20 } from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';

contract MockFailedMintDSC is ERC20Burnable, Ownable {
    error DefiStableCoin__AmountMustBeMoreThanZero();
    error DefiStableCoin__BurnAmountExceedsBalance();
    error DefiStableCoin__NotZeroAddress();

    constructor(address _owner) ERC20('DefiStableCoin', 'DSC') Ownable(_owner) {}

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

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DefiStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DefiStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return false;
    }
}
