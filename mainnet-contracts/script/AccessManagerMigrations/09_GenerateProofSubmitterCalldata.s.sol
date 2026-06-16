// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ROLE_ID_OPERATIONS_PAYMASTER } from "../../script/Roles.sol";
import { ProofSubmitter } from "../../src/ProofSubmitter.sol";

// forge script script/AccessManagerMigrations/09_GenerateProofSubmitterCalldata.s.sol:GenerateProofSubmitterCalldata -vvvv --sig "run(address)(bytes memory)" PROOF_SUBMITTER_ADDRESS
contract GenerateProofSubmitterCalldata is Script {
    function run(address proofSubmitter) public pure returns (bytes memory) {
        bytes[] memory calldatas = new bytes[](1);

        bytes4[] memory paymasterSelectors = new bytes4[](4);
        paymasterSelectors[0] = ProofSubmitter.startCheckpoint.selector;
        paymasterSelectors[1] = ProofSubmitter.verifyCheckpointProofs.selector;
        paymasterSelectors[2] = ProofSubmitter.verifyWithdrawalCredentials.selector;
        paymasterSelectors[3] = ProofSubmitter.verifyStaleBalance.selector;

        calldatas[0] = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            proofSubmitter,
            paymasterSelectors,
            ROLE_ID_OPERATIONS_PAYMASTER
        );

        bytes memory encodedMulticall = abi.encodeCall(Multicall.multicall, (calldatas));

        return encodedMulticall;
    }
}
