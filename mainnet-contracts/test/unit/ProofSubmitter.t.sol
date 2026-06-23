// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { ROLE_ID_OPERATIONS_PAYMASTER } from "../../script/Roles.sol";
import { ProofSubmitter } from "../../src/ProofSubmitter.sol";
import { BeaconChainProofs } from "../../src/interface/Eigenlayer-Slashing/IEigenPod.sol";
import { EigenPodMock } from "../mocks/EigenPodMock.sol";
import { GenerateProofSubmitterCalldata } from
    "../../script/AccessManagerMigrations/09_GenerateProofSubmitterCalldata.s.sol";

/**
 * @dev Test for the simple ProofSubmitter smart contract
 */
contract ProofSubmitterTest is UnitTestHelper {
    ProofSubmitter proofSubmitter;
    EigenPodMock eigenPod;

    function setUp() public override {
        // Just call the parent setUp()
        super.setUp();

        // Deploy the ProofSubmitter contract, authority is the AccessManager
        proofSubmitter = new ProofSubmitter(address(accessManager));

        eigenPod = new EigenPodMock();

        // Wire up the AccessManager so that ROLE_ID_OPERATIONS_PAYMASTER is allowed to call
        // the restricted functions on the ProofSubmitter, and grant the role to the PAYMASTER.
        bytes memory encodedCalldata = new GenerateProofSubmitterCalldata().run(address(proofSubmitter));

        vm.startPrank(timelock);
        accessManager.grantRole(ROLE_ID_OPERATIONS_PAYMASTER, PAYMASTER, 0);
        (bool success,) = address(accessManager).call(encodedCalldata);
        assertTrue(success, "setTargetFunctionRole multicall failed");
        vm.stopPrank();
    }

    // -- helpers ---------------------------------------------------------------------------------

    function _emptyBalanceContainerProof() internal pure returns (BeaconChainProofs.BalanceContainerProof memory) {
        return BeaconChainProofs.BalanceContainerProof({ balanceContainerRoot: bytes32("root"), proof: "" });
    }

    function _emptyStateRootProof() internal pure returns (BeaconChainProofs.StateRootProof memory) {
        return BeaconChainProofs.StateRootProof({ beaconStateRoot: bytes32("state"), proof: "" });
    }

    // -- authority -------------------------------------------------------------------------------

    function test_authorityIsAccessManager() public view {
        assertEq(proofSubmitter.authority(), address(accessManager), "authority should be the AccessManager");
    }

    // -- startCheckpoint -------------------------------------------------------------------------

    function test_startCheckpoint_paymasterForwardsCall() public {
        vm.expectEmit(true, true, true, true, address(eigenPod));
        emit EigenPodMock.StartCheckpointCalled(true);

        vm.prank(PAYMASTER);
        proofSubmitter.startCheckpoint(address(eigenPod), true);
    }

    function test_startCheckpoint_revertsForUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        proofSubmitter.startCheckpoint(address(eigenPod), true);
    }

    function testFuzz_startCheckpoint_revertsForUnauthorized(address caller) public {
        vm.assume(caller != PAYMASTER);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        vm.prank(caller);
        proofSubmitter.startCheckpoint(address(eigenPod), false);
    }

    // -- verifyCheckpointProofs ------------------------------------------------------------------

    function test_verifyCheckpointProofs_paymasterForwardsCall() public {
        BeaconChainProofs.BalanceProof[] memory proofs = new BeaconChainProofs.BalanceProof[](2);
        proofs[0] = BeaconChainProofs.BalanceProof({ pubkeyHash: bytes32("a"), balanceRoot: bytes32("b"), proof: "" });
        proofs[1] = BeaconChainProofs.BalanceProof({ pubkeyHash: bytes32("c"), balanceRoot: bytes32("d"), proof: "" });

        vm.expectEmit(true, true, true, true, address(eigenPod));
        emit EigenPodMock.VerifyCheckpointProofsCalled(bytes32("root"), 2);

        vm.prank(PAYMASTER);
        proofSubmitter.verifyCheckpointProofs(address(eigenPod), _emptyBalanceContainerProof(), proofs);
    }

    function test_verifyCheckpointProofs_revertsForUnauthorized() public {
        BeaconChainProofs.BalanceProof[] memory proofs = new BeaconChainProofs.BalanceProof[](0);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        vm.prank(bob);
        proofSubmitter.verifyCheckpointProofs(address(eigenPod), _emptyBalanceContainerProof(), proofs);
    }

    // -- verifyWithdrawalCredentials -------------------------------------------------------------

    function test_verifyWithdrawalCredentials_paymasterForwardsCall() public {
        uint40[] memory validatorIndices = new uint40[](1);
        validatorIndices[0] = 42;
        bytes[] memory validatorFieldsProofs = new bytes[](1);
        bytes32[][] memory validatorFields = new bytes32[][](1);

        vm.expectEmit(true, true, true, true, address(eigenPod));
        emit EigenPodMock.VerifyWithdrawalCredentialsCalled(123, 1);

        vm.prank(PAYMASTER);
        proofSubmitter.verifyWithdrawalCredentials(
            address(eigenPod), 123, _emptyStateRootProof(), validatorIndices, validatorFieldsProofs, validatorFields
        );
    }

    function test_verifyWithdrawalCredentials_revertsForUnauthorized() public {
        uint40[] memory validatorIndices = new uint40[](0);
        bytes[] memory validatorFieldsProofs = new bytes[](0);
        bytes32[][] memory validatorFields = new bytes32[][](0);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, charlie));
        vm.prank(charlie);
        proofSubmitter.verifyWithdrawalCredentials(
            address(eigenPod), 123, _emptyStateRootProof(), validatorIndices, validatorFieldsProofs, validatorFields
        );
    }

    // -- verifyStaleBalance ----------------------------------------------------------------------

    function test_verifyStaleBalance_paymasterForwardsCall() public {
        BeaconChainProofs.ValidatorProof memory proof =
            BeaconChainProofs.ValidatorProof({ validatorFields: new bytes32[](0), proof: "" });

        vm.expectEmit(true, true, true, true, address(eigenPod));
        emit EigenPodMock.VerifyStaleBalanceCalled(456, bytes32("state"));

        vm.prank(PAYMASTER);
        proofSubmitter.verifyStaleBalance(address(eigenPod), 456, _emptyStateRootProof(), proof);
    }

    function test_verifyStaleBalance_revertsForUnauthorized() public {
        BeaconChainProofs.ValidatorProof memory proof =
            BeaconChainProofs.ValidatorProof({ validatorFields: new bytes32[](0), proof: "" });

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, dianna));
        vm.prank(dianna);
        proofSubmitter.verifyStaleBalance(address(eigenPod), 456, _emptyStateRootProof(), proof);
    }
}
