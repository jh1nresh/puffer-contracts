// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { BeaconChainProofs } from "../../src/interface/Eigenlayer-Slashing/IEigenPod.sol";

/**
 * @dev Minimal EigenPod stand-in that records the calls forwarded by the ProofSubmitter
 * so the tests can assert that arguments are passed through untouched.
 */
contract EigenPodMock {
    event StartCheckpointCalled(bool revertIfNoBalance);
    event VerifyCheckpointProofsCalled(bytes32 balanceContainerRoot, uint256 proofsLength);
    event VerifyWithdrawalCredentialsCalled(uint64 beaconTimestamp, uint256 validatorIndicesLength);
    event VerifyStaleBalanceCalled(uint64 beaconTimestamp, bytes32 beaconStateRoot);

    function startCheckpoint(bool revertIfNoBalance) external {
        emit StartCheckpointCalled(revertIfNoBalance);
    }

    function verifyCheckpointProofs(
        BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof,
        BeaconChainProofs.BalanceProof[] calldata proofs
    ) external {
        emit VerifyCheckpointProofsCalled(balanceContainerProof.balanceContainerRoot, proofs.length);
    }

    function verifyWithdrawalCredentials(
        uint64 beaconTimestamp,
        BeaconChainProofs.StateRootProof calldata, /* stateRootProof */
        uint40[] calldata validatorIndices,
        bytes[] calldata, /* validatorFieldsProofs */
        bytes32[][] calldata /* validatorFields */
    ) external {
        emit VerifyWithdrawalCredentialsCalled(beaconTimestamp, validatorIndices.length);
    }

    function verifyStaleBalance(
        uint64 beaconTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.ValidatorProof calldata /* proof */
    ) external {
        emit VerifyStaleBalanceCalled(beaconTimestamp, stateRootProof.beaconStateRoot);
    }
}
