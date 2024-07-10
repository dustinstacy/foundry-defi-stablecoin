// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from 'forge-std/Script.sol';
import { DefiStableCoin } from 'src/DefiStableCoin.sol';

contract DeployDefiStableCoin is Script {
    function run(address _owner) external returns (DefiStableCoin dsc) {
        vm.startBroadcast();
        dsc = new DefiStableCoin(_owner);
        vm.stopBroadcast();
    }
}
