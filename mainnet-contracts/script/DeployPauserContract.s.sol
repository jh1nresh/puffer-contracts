// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { DeployerHelper } from "./DeployerHelper.s.sol";
import { PauserContract } from "../src/PauserContract.sol";
import "forge-std/Script.sol";

/**
 * forge script script/DeployPauserContract.s.sol:DeployPauserContract --rpc-url=$RPC_URL --private-key $PK
 */
contract DeployPauserContract is DeployerHelper {
    function run() public returns (PauserContract) {
        vm.startBroadcast();

        PauserContract pauser = new PauserContract(_getAccessManager(), _getTimelock());

        vm.label(address(pauser), "PauserContract");
        console.log("PauserContract deployed to:", address(pauser));

        vm.stopBroadcast();
        return pauser;
    }
}
