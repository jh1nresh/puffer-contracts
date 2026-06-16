// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Script.sol";
import { DeployerHelper } from "./DeployerHelper.s.sol";
import { ProofSubmitter } from "../src/ProofSubmitter.sol";

/**
 * forge script script/DeployProofSubmitter.s.sol:DeployProofSubmitter --rpc-url=$RPC_URL --account deployer
 *
 * deploy along with verification:
 * forge script script/DeployProofSubmitter.s.sol:DeployProofSubmitter -vvvv --rpc-url=$RPC_URL --account deployer --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
 */
contract DeployProofSubmitter is DeployerHelper {
    function run() public {
        vm.startBroadcast();

        ProofSubmitter proofSubmitter = new ProofSubmitter(_getAccessManager());

        vm.label(address(proofSubmitter), "PROOF_SUBMITTER");

        vm.stopBroadcast();
    }
}
