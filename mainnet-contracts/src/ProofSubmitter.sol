// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { IEigenPod, BeaconChainProofs } from "./interface/Eigenlayer-Slashing/IEigenPod.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

/**
 * @title PUFFER Token
 * @author Puffer Finance
 * @dev This contract limits the functions from IEigenPod that can be called by the operations paymaster. It is intended to be used as a "proof submitter" for EigenPods,
 *      allowing the operations paymaster to submit proofs on behalf of the pod owner.
 *      This prevents the proof submitter to call other more critical functions like `requestWithdrawal()`.
 * @custom:security-contact security@puffer.fi
 */
contract ProofSubmitter is AccessManaged {
    constructor(address initialAuthority) AccessManaged(initialAuthority) { }

    /// @dev Create a checkpoint used to prove this pod's active validator set. Checkpoints are completed
    /// by submitting one checkpoint proof per ACTIVE validator. During the checkpoint process, the total
    /// change in ACTIVE validator balance is tracked, and any validators with 0 balance are marked `WITHDRAWN`.
    /// @dev Once finalized, the pod owner is awarded shares corresponding to:
    /// - the total change in their ACTIVE validator balances
    /// - any ETH in the pod not already awarded shares
    /// @dev A checkpoint cannot be created if the pod already has an outstanding checkpoint. If
    /// this is the case, the pod owner MUST complete the existing checkpoint before starting a new one.
    /// @dev restricted to ROLE_ID_OPERATIONS_PAYMASTER
    /// @param eigenPod The address of the EigenPod to start a checkpoint for
    /// @param revertIfNoBalance Forces a revert if the pod ETH balance is 0. This allows the pod owner
    /// to prevent accidentally starting a checkpoint that will not increase their shares
    function startCheckpoint(address eigenPod, bool revertIfNoBalance) external restricted {
        IEigenPod(eigenPod).startCheckpoint(revertIfNoBalance);
    }

    /// @dev Progress the current checkpoint towards completion by submitting one or more validator
    /// checkpoint proofs. Anyone can call this method to submit proofs towards the current checkpoint.
    /// For each validator proven, the current checkpoint's `proofsRemaining` decreases.
    /// @dev If the checkpoint's `proofsRemaining` reaches 0, the checkpoint is finalized.
    /// (see `_updateCheckpoint` for more details)
    /// @dev This method can only be called when there is a currently-active checkpoint.
    /// @dev restricted to ROLE_ID_OPERATIONS_PAYMASTER
    /// @param eigenPod The address of the EigenPod for which to verify proofs
    /// @param balanceContainerProof proves the beacon's current balance container root against a checkpoint's `beaconBlockRoot`
    /// @param proofs Proofs for one or more validator current balances against the `balanceContainerRoot`
    function verifyCheckpointProofs(
        address eigenPod,
        BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof,
        BeaconChainProofs.BalanceProof[] calldata proofs
    ) external restricted {
        IEigenPod(eigenPod).verifyCheckpointProofs(balanceContainerProof, proofs);
    }

    /// @dev Verify one or more validators have their withdrawal credentials pointed at this EigenPod, and award
    /// shares based on their effective balance. Proven validators are marked `ACTIVE` within the EigenPod, and
    /// future checkpoint proofs will need to include them.
    /// @dev Withdrawal credential proofs MUST NOT be older than `currentCheckpointTimestamp`.
    /// @dev Validators proven via this method MUST NOT have an exit epoch set already.
    /// @dev restricted to ROLE_ID_OPERATIONS_PAYMASTER
    /// @param eigenPod The address of the EigenPod for which to verify withdrawal credentials
    /// @param beaconTimestamp the beacon chain timestamp sent to the 4788 oracle contract. Corresponds
    /// to the parent beacon block root against which the proof is verified.
    /// @param stateRootProof proves a beacon state root against a beacon block root
    /// @param validatorIndices a list of validator indices being proven
    /// @param validatorFieldsProofs proofs of each validator's `validatorFields` against the beacon state root
    /// @param validatorFields the fields of the beacon chain "Validator" container. See consensus specs for
    /// details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
    function verifyWithdrawalCredentials(
        address eigenPod,
        uint64 beaconTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external restricted {
        IEigenPod(eigenPod).verifyWithdrawalCredentials(
            beaconTimestamp, stateRootProof, validatorIndices, validatorFieldsProofs, validatorFields
        );
    }

    /// @dev Prove that one of this pod's active validators was slashed on the beacon chain. A successful
    /// staleness proof allows the caller to start a checkpoint.
    ///
    /// @dev Note that in order to start a checkpoint, any existing checkpoint must already be completed!
    /// (See `_startCheckpoint` for details)
    ///
    /// @dev Note that this method allows anyone to start a checkpoint as soon as a slashing occurs on the beacon
    /// chain. This is intended to make it easier to external watchers to keep a pod's balance up to date.
    ///
    /// @dev Note too that beacon chain slashings are not instant. There is a delay between the initial slashing event
    /// and the validator's final exit back to the execution layer. During this time, the validator's balance may or
    /// may not drop further due to a correlation penalty. This method allows proof of a slashed validator
    /// to initiate a checkpoint for as long as the validator remains on the beacon chain. Once the validator
    /// has exited and been checkpointed at 0 balance, they are no longer "checkpoint-able" and cannot be proven
    /// "stale" via this method.
    /// See https://eth2book.info/capella/part3/transition/epoch/#slashings for more info.
    ///
    /// @dev restricted to ROLE_ID_OPERATIONS_PAYMASTER
    /// @param eigenPod The address of the EigenPod for which to verify staleness
    /// @param beaconTimestamp the beacon chain timestamp sent to the 4788 oracle contract. Corresponds
    /// to the parent beacon block root against which the proof is verified.
    /// @param stateRootProof proves a beacon state root against a beacon block root
    /// @param proof the fields of the beacon chain "Validator" container, along with a merkle proof against
    /// the beacon state root. See the consensus specs for more details:
    /// https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
    ///
    /// @dev Staleness conditions:
    /// - Validator's last checkpoint is older than `beaconTimestamp`
    /// - Validator MUST be in `ACTIVE` status in the pod
    /// - Validator MUST be slashed on the beacon chain
    function verifyStaleBalance(
        address eigenPod,
        uint64 beaconTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.ValidatorProof calldata proof
    ) external restricted {
        IEigenPod(eigenPod).verifyStaleBalance(beaconTimestamp, stateRootProof, proof);
    }
}
