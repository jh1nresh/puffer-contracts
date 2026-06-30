// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { UnitTestHelper } from "../helpers/UnitTestHelper.sol";
import { IGuardianModule, PublicIdentity, GuardianSessionProof } from "../../src/interface/IGuardianModule.sol";
import { GuardianModule } from "../../src/GuardianModule.sol";
import { Unauthorized, InvalidAddress } from "../../src/Errors.sol";
import { SessionRegistryMock } from "../mocks/SessionRegistryMock.sol";
import { ALGO_ID_ES256K } from "@automata-network/automata-tee-workload-measurement/types/Constants.sol";
import { LibKey } from "@automata-network/automata-tee-workload-measurement/lib/LibKey.sol";
import { ISessionRegistry } from
    "@automata-network/automata-tee-workload-measurement/interfaces/registries/ISessionRegistry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ROLE_ID_DAO } from "../../script/Roles.sol";

contract GuardianModuleTest is UnitTestHelper {
    uint256 public newSKEnclave;
    bytes public newEnclavePubKey;

    uint256 public newSKGuardian;
    address public newGuardian;
    bytes public newGuardianPubKey;

    PublicIdentity public newGuardianOwnerPublicIdentity;
    PublicIdentity public newGuardianSessionPublicIdentity;

    bytes32 public newGuardianSessionId = keccak256("newGuardianSessionId");

    function setUp() public override {
        // Just call the parent setUp()
        super.setUp();
        _skipDefaultFuzzAddresses();

        newSKEnclave = 40280701971156975094650330025087207427871411154031414620449944599045365691365;
        newEnclavePubKey =
            hex"04f6a0b4231ab4442dff42aeeb7a0f761d0591cd10f6ef793b545a78130955e485ce17a19dd12916bfc7b5230e8e16ac14050069ed7609f926346912b2a899df21";

        newSKGuardian = 62446650044403031109669988213557076707788335704243384097041391592912982163892;
        newGuardianPubKey =
            hex"0410a8e13cb502346e709da19444ffa7584377fd6c68f8a8c3689edef46deac332523d15524394b64c932added00b6a0f9452b2c5cf8fee12e176a10a1dabbd7ba";
        newGuardian = vm.addr(newSKGuardian);

        newGuardianOwnerPublicIdentity = PublicIdentity({ typeId: ALGO_ID_ES256K, key: newGuardianPubKey });
        newGuardianSessionPublicIdentity = PublicIdentity({ typeId: ALGO_ID_ES256K, key: newEnclavePubKey });
    }

    function test_invalid_constructor() public {
        address[] memory guardians = new address[](1);
        guardians[0] = guardian1;
        address authority = guardianModule.authority();

        // invalid session registry
        vm.expectRevert(InvalidAddress.selector);
        new GuardianModule(
            ISessionRegistry(address(0)), guardians, 1, authority, FRESHNESS_BLOCKS, address(pufferVault)
        );

        // invalid authority
        vm.expectRevert(InvalidAddress.selector);
        new GuardianModule(
            ISessionRegistry(address(sessionRegistryMock)),
            guardians,
            1,
            address(0),
            FRESHNESS_BLOCKS,
            address(pufferVault)
        );

        // empty guardians
        address[] memory emptyGuardians = new address[](1);
        vm.expectRevert(InvalidAddress.selector);
        new GuardianModule(
            ISessionRegistry(address(sessionRegistryMock)),
            emptyGuardians,
            1,
            authority,
            FRESHNESS_BLOCKS,
            address(pufferVault)
        );

        // invalid threshold
        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 0));
        new GuardianModule(
            ISessionRegistry(address(sessionRegistryMock)),
            guardians,
            0,
            authority,
            FRESHNESS_BLOCKS,
            address(pufferVault)
        );
    }

    function test_setup() public view {
        assertEq(guardianModule.getEjectionThreshold(), 31.75 ether, "initial value ejection threshold (31.75)");
        assertEq(guardianModule.getThreshold(), 1, "initial value threshold (1)");
    }

    function test_rave() public {
        _deployContractAndSetupGuardians();
    }

    function test_set_ejection_threshold_reverts() public {
        vm.startPrank(DAO);

        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 32.1 ether));
        guardianModule.setEjectionThreshold(32.1 ether);
    }

    function test_set_threshold_to_0_reverts() public {
        vm.startPrank(DAO);
        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 0));
        guardianModule.setThreshold(0);
    }

    function test_set_threshold_to_50_reverts() public {
        // 50 is more than the number of guardians
        vm.startPrank(DAO);
        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 50));
        guardianModule.setThreshold(50);
    }

    function test_addGuardian(address guardian) public assumeEOA(guardian) {
        vm.startPrank(DAO);

        // Must not be a guardian already
        vm.assume(!guardianModule.isGuardian(guardian));

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.GuardianAdded(guardian);
        guardianModule.addGuardian(guardian);
    }

    function test_removeGuardian(address guardian) public {
        test_addGuardian(guardian);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.GuardianRemoved(guardian);
        guardianModule.removeGuardian(guardian);
    }

    function test_removeGuardian_check_enclave_removed() public {
        bytes32 workloadId = keccak256("allowed_workload");
        vm.startPrank(DAO);
        guardianModule.addGuardian(newGuardian);
        guardianModule.setAllowedWorkload(workloadId, true);
        vm.stopPrank();

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        sessionRegistryMock.setSessionWorkload(newGuardianSessionId, workloadId);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.RotatedGuardianKey(newGuardian, vm.addr(newSKEnclave), newEnclavePubKey);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: signature
            })
        );

        assertEq(guardianModule.getGuardiansEnclaveAddress(newGuardian), vm.addr(newSKEnclave), "bad enclave address");

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.GuardianRemoved(newGuardian);
        guardianModule.removeGuardian(newGuardian);
        vm.stopPrank();

        assertEq(
            guardianModule.getGuardiansEnclaveAddress(newGuardian), address(0), "enclave address should be cleared"
        );
    }

    function test_remove_guardian_below_threshold() public {
        // Our test env has 3 guardians and threshold 1

        vm.startPrank(DAO);
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.ThresholdChanged(1, 3);
        guardianModule.setThreshold(3);
        assertEq(guardianModule.getThreshold(), 3, "guardians threshold");

        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.InvalidThreshold.selector, 3));
        guardianModule.removeGuardian(guardian1);
    }

    function test_splitFunds() public {
        vm.deal(address(guardianModule), 1 ether);

        guardianModule.splitGuardianFunds();

        assertEq(guardian1.balance, guardian2.balance, "guardian balances");
        assertEq(guardian1.balance, guardian3.balance, "guardian balances");
    }

    function test_splitFunds_pufETH() public {
        // splitGuardianFunds distributes whatever the module holds, so we mint pufETH directly to it
        vm.deal(address(this), 3 ether);
        uint256 pufETHAmount = pufferVault.depositETH{ value: 3 ether }(address(guardianModule));

        assertEq(pufferVault.balanceOf(guardian1), 0, "guardian1 pre-balance");
        assertEq(pufferVault.balanceOf(guardian2), 0, "guardian2 pre-balance");
        assertEq(pufferVault.balanceOf(guardian3), 0, "guardian3 pre-balance");
        assertEq(pufferVault.balanceOf(address(guardianModule)), pufETHAmount, "module pre-balance");

        uint256 expectedPerGuardian = pufETHAmount / 3;

        // The vault's ERC20 Transfer should fire once per guardian
        vm.expectEmit(true, true, true, true, address(pufferVault));
        emit IERC20.Transfer(address(guardianModule), guardian1, expectedPerGuardian);
        vm.expectEmit(true, true, true, true, address(pufferVault));
        emit IERC20.Transfer(address(guardianModule), guardian2, expectedPerGuardian);
        vm.expectEmit(true, true, true, true, address(pufferVault));
        emit IERC20.Transfer(address(guardianModule), guardian3, expectedPerGuardian);

        guardianModule.splitGuardianFunds();

        assertEq(pufferVault.balanceOf(guardian1), expectedPerGuardian, "guardian1 pufETH balance");
        assertEq(pufferVault.balanceOf(guardian2), expectedPerGuardian, "guardian2 pufETH balance");
        assertEq(pufferVault.balanceOf(guardian3), expectedPerGuardian, "guardian3 pufETH balance");

        // 3 ether is evenly divisible by 3 — nothing left behind
        assertEq(pufferVault.balanceOf(address(guardianModule)), 0, "module post-balance");
    }

    function test_splitFunds_pufETH_with_remainder() public {
        // Deposit an amount that doesn't divide evenly by 3 to exercise the rounding path
        vm.deal(address(this), 10 ether);
        uint256 pufETHAmount = pufferVault.depositETH{ value: 10 ether }(address(guardianModule));

        uint256 expectedPerGuardian = pufETHAmount / 3;
        uint256 expectedRemainder = pufETHAmount - expectedPerGuardian * 3;
        assertGt(expectedRemainder, 0, "test setup should produce a remainder");

        vm.expectEmit(true, true, true, true, address(pufferVault));
        emit IERC20.Transfer(address(guardianModule), guardian1, expectedPerGuardian);
        vm.expectEmit(true, true, true, true, address(pufferVault));
        emit IERC20.Transfer(address(guardianModule), guardian2, expectedPerGuardian);
        vm.expectEmit(true, true, true, true, address(pufferVault));
        emit IERC20.Transfer(address(guardianModule), guardian3, expectedPerGuardian);

        guardianModule.splitGuardianFunds();

        assertEq(pufferVault.balanceOf(guardian1), expectedPerGuardian, "guardian1 pufETH balance");
        assertEq(pufferVault.balanceOf(guardian2), expectedPerGuardian, "guardian2 pufETH balance");
        assertEq(pufferVault.balanceOf(guardian3), expectedPerGuardian, "guardian3 pufETH balance");

        // Rounding remainder stays in the module
        assertEq(pufferVault.balanceOf(address(guardianModule)), expectedRemainder, "module keeps remainder");
    }

    function test_addAllowedToken() public {
        ERC20Mock newToken = new ERC20Mock("Mock", "MCK");

        vm.expectEmit(true, true, true, true, address(guardianModule));
        emit IGuardianModule.AllowedTokenAdded(address(newToken));

        vm.prank(DAO);
        guardianModule.addAllowedToken(address(newToken));

        // Sanity: a freshly minted balance to the module is now distributed by splitGuardianFunds
        newToken.mint(address(guardianModule), 3 ether);
        guardianModule.splitGuardianFunds();
        assertEq(newToken.balanceOf(guardian1), 1 ether, "guardian1 received new token");
        assertEq(newToken.balanceOf(guardian2), 1 ether, "guardian2 received new token");
        assertEq(newToken.balanceOf(guardian3), 1 ether, "guardian3 received new token");
    }

    function test_addAllowedToken_revertsForZeroAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        vm.prank(DAO);
        guardianModule.addAllowedToken(address(0));
    }

    function test_addAllowedToken_revertsIfAlreadyAdded() public {
        // pufETH is added in the constructor, so re-adding must revert
        vm.expectRevert(InvalidAddress.selector);
        vm.prank(DAO);
        guardianModule.addAllowedToken(address(pufferVault));
    }

    function test_addAllowedToken_revertsIfUnauthorized(address caller) public {
        ERC20Mock newToken = new ERC20Mock("Mock", "MCK");

        vm.assume(caller != address(0));
        (bool hasDaoRole,) = accessManager.hasRole(ROLE_ID_DAO, caller);
        vm.assume(!hasDaoRole);
        // The AccessManager admin can always call; exclude any admins set up in the deploy
        (bool hasAdminRole,) = accessManager.hasRole(accessManager.ADMIN_ROLE(), caller);
        vm.assume(!hasAdminRole);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        vm.prank(caller);
        guardianModule.addAllowedToken(address(newToken));
    }

    function test_addAllowedToken_distributesExistingFundsFirst() public {
        ERC20Mock newToken = new ERC20Mock("Mock", "MCK");

        // Seed the module with pufETH so addAllowedToken's internal split has something to do
        vm.deal(address(this), 3 ether);
        pufferVault.depositETH{ value: 3 ether }(address(guardianModule));
        uint256 modulePufBalance = pufferVault.balanceOf(address(guardianModule));
        assertGt(modulePufBalance, 0, "module should hold pufETH pre-add");

        vm.prank(DAO);
        guardianModule.addAllowedToken(address(newToken));

        // The pre-existing pufETH balance was split across the guardians
        uint256 expectedPerGuardian = modulePufBalance / 3;
        assertEq(pufferVault.balanceOf(guardian1), expectedPerGuardian, "guardian1 pufETH from pre-add split");
        assertEq(pufferVault.balanceOf(guardian2), expectedPerGuardian, "guardian2 pufETH from pre-add split");
        assertEq(pufferVault.balanceOf(guardian3), expectedPerGuardian, "guardian3 pufETH from pre-add split");
    }

    function test_splitFunds_airdroppedToken() public {
        // Someone airdrops a random ERC-20 to the module before it's allowlisted
        ERC20Mock airdroppedToken = new ERC20Mock("Airdrop", "AIR");
        uint256 airdropAmount = 9 ether;
        airdroppedToken.mint(address(guardianModule), airdropAmount);

        // Until DAO allowlists it, splitGuardianFunds ignores the airdropped balance
        guardianModule.splitGuardianFunds();
        assertEq(airdroppedToken.balanceOf(guardian1), 0, "guardian1 should not receive un-allowed token");
        assertEq(airdroppedToken.balanceOf(address(guardianModule)), airdropAmount, "module still holds full airdrop");

        // DAO allowlists the token
        vm.prank(DAO);
        guardianModule.addAllowedToken(address(airdroppedToken));

        uint256 expectedPerGuardian = airdropAmount / 3;

        // Now the next split distributes the airdrop. Expect one Transfer per guardian on the airdrop token
        vm.expectEmit(true, true, true, true, address(airdroppedToken));
        emit IERC20.Transfer(address(guardianModule), guardian1, expectedPerGuardian);
        vm.expectEmit(true, true, true, true, address(airdroppedToken));
        emit IERC20.Transfer(address(guardianModule), guardian2, expectedPerGuardian);
        vm.expectEmit(true, true, true, true, address(airdroppedToken));
        emit IERC20.Transfer(address(guardianModule), guardian3, expectedPerGuardian);

        guardianModule.splitGuardianFunds();

        assertEq(airdroppedToken.balanceOf(guardian1), expectedPerGuardian, "guardian1 received airdrop share");
        assertEq(airdroppedToken.balanceOf(guardian2), expectedPerGuardian, "guardian2 received airdrop share");
        assertEq(airdroppedToken.balanceOf(guardian3), expectedPerGuardian, "guardian3 received airdrop share");
        assertEq(airdroppedToken.balanceOf(address(guardianModule)), 0, "module fully drained (9 / 3 is exact)");
    }

    function test_removeAllowedToken() public {
        vm.expectEmit(true, true, true, true, address(guardianModule));
        emit IGuardianModule.AllowedTokenRemoved(address(pufferVault));

        vm.prank(DAO);
        guardianModule.removeAllowedToken(address(pufferVault));

        // After removal, pufETH held by the module is no longer distributed
        vm.deal(address(this), 3 ether);
        uint256 pufETHAmount = pufferVault.depositETH{ value: 3 ether }(address(guardianModule));

        guardianModule.splitGuardianFunds();

        assertEq(pufferVault.balanceOf(guardian1), 0, "guardian1 should not receive pufETH after removal");
        assertEq(pufferVault.balanceOf(guardian2), 0, "guardian2 should not receive pufETH after removal");
        assertEq(pufferVault.balanceOf(guardian3), 0, "guardian3 should not receive pufETH after removal");
        assertEq(pufferVault.balanceOf(address(guardianModule)), pufETHAmount, "module still holds pufETH");
    }

    function test_removeAllowedToken_revertsForZeroAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        vm.prank(DAO);
        guardianModule.removeAllowedToken(address(0));
    }

    function test_removeAllowedToken_revertsIfNotAdded() public {
        ERC20Mock unknownToken = new ERC20Mock("Mock", "MCK");

        vm.expectRevert(InvalidAddress.selector);
        vm.prank(DAO);
        guardianModule.removeAllowedToken(address(unknownToken));
    }

    function test_removeAllowedToken_revertsIfUnauthorized(address caller) public {
        vm.assume(caller != address(0));
        (bool hasDaoRole,) = accessManager.hasRole(ROLE_ID_DAO, caller);
        vm.assume(!hasDaoRole);
        (bool hasAdminRole,) = accessManager.hasRole(accessManager.ADMIN_ROLE(), caller);
        vm.assume(!hasAdminRole);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        vm.prank(caller);
        guardianModule.removeAllowedToken(address(pufferVault));
    }

    function test_set_threshold() public {
        vm.startPrank(DAO);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.ThresholdChanged(1, 2);
        guardianModule.setThreshold(2);
    }

    function test_set_threshold_reverts() public {
        vm.startPrank(DAO);

        // We have 3 guardians, try setting threshold to 5
        vm.expectRevert();
        guardianModule.setThreshold(5);
    }

    // Invalid signature reverts with unauthorized
    function test_validateSkipProvisioning_reverts() public {
        (, uint256 bobSK) = makeAddrAndKey("bob");
        bytes[] memory guardianSignatures = new bytes[](3);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobSK, bytes32("whatever"));
        guardianSignatures[0] = abi.encodePacked(r, s, v);
        vm.expectRevert(Unauthorized.selector);
        guardianModule.validateSkipProvisioning(PUFFER_MODULE_0, 0, guardianSignatures);
    }

    function test_split_funds_rounding() external {
        vm.deal(address(guardianModule), 2); // 2 wei, but 3 guardians
        // shouldn't revert, but due to rounding down, they will not receive any eth
        guardianModule.splitGuardianFunds();

        assertEq(guardian1.balance, 0);
        assertEq(guardian2.balance, 0);
        assertEq(guardian3.balance, 0);

        vm.deal(address(guardianModule), 32); // 32 wei on 3 guardians = 10 each, the rest stays in the module
        guardianModule.splitGuardianFunds();

        assertEq(guardian1.balance, 10);
        assertEq(guardian2.balance, 10);
        assertEq(guardian3.balance, 10);
        assertEq(address(guardianModule).balance, 2);
    }

    function test_setAllowedWorkload() public {
        vm.startPrank(DAO);

        vm.expectRevert(abi.encodeWithSelector(IGuardianModule.WorkloadNotAllowed.selector));
        guardianModule.setAllowedWorkload(bytes32(0), true);

        bytes32 workloadId = keccak256("test_workload");

        // Initially workload should not be allowed
        assertFalse(guardianModule.isWorkloadAllowed(workloadId), "workload should not be allowed initially");

        // Set workload as allowed
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.WorkloadAllowanceChanged(workloadId, true);
        guardianModule.setAllowedWorkload(workloadId, true);

        // Verify workload is now allowed
        assertTrue(guardianModule.isWorkloadAllowed(workloadId), "workload should be allowed");

        // Set workload as not allowed
        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.WorkloadAllowanceChanged(workloadId, false);
        guardianModule.setAllowedWorkload(workloadId, false);

        // Verify workload is not allowed anymore
        assertFalse(guardianModule.isWorkloadAllowed(workloadId), "workload should not be allowed");

        vm.stopPrank();
    }

    function test_rotateGuardianKey_invalid_algorithm() public {
        newGuardianOwnerPublicIdentity.typeId = 0; // invalid algorithm

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            abi.encodePacked(newGuardianPubKey, bytes1(0x00)), // invalid length
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_owner_key_length() public {
        newGuardianOwnerPublicIdentity.key = abi.encodePacked(newGuardianOwnerPublicIdentity.key, bytes1(0x00)); // invalid length

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            abi.encodePacked(newGuardianPubKey, bytes1(0x00)), // invalid length
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_from_non_guardian_reverts() public {
        vm.expectRevert(Unauthorized.selector);
        guardianModule.rotateGuardianKey(
            0,
            new bytes(65),
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_pubkey_length() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            abi.encodePacked(newGuardianPubKey, bytes1(0x00)), // invalid length
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_stale_evidence() public {
        vm.roll(block.number + FRESHNESS_BLOCKS + 1); // move forward in time to make the proof stale
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        vm.expectRevert(IGuardianModule.StaleEvidence.selector);
        guardianModule.rotateGuardianKey(
            0,
            newGuardianPubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_signature() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        vm.expectRevert(IGuardianModule.InvalidSignature.selector);
        guardianModule.rotateGuardianKey(
            0,
            newGuardianPubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: new bytes(65)
            })
        );
    }

    function test_rotateGuardianKey_invalid_owner_fingerprint() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        vm.expectRevert(IGuardianModule.InvalidECDSAPubKey.selector);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: guardian1OwnerPublicIdentity, // invalid owner key (not matching the one used to sign)
                signature: signature
            })
        );
    }

    function test_rotateGuardianKey_invalid_workload_not_allowed() public {
        vm.prank(DAO);
        guardianModule.addGuardian(newGuardian);

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        vm.expectRevert(IGuardianModule.WorkloadNotAllowed.selector);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: signature
            })
        );
    }

    function test_rotateGuardianKey_success() public {
        bytes32 workloadId = keccak256("allowed_workload");
        vm.startPrank(DAO);
        guardianModule.addGuardian(newGuardian);
        guardianModule.setAllowedWorkload(workloadId, true);
        vm.stopPrank();

        bytes32 signedMessageHash =
            keccak256(abi.encode("ROTATE_GUARDIAN_KEY", address(guardianModule), block.chainid, 0, newEnclavePubKey));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newSKEnclave, signedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        sessionRegistryMock.setSessionOwner(
            newGuardianSessionId, LibKey.computeKeyFingerprint(newGuardianOwnerPublicIdentity)
        );

        sessionRegistryMock.setSessionWorkload(newGuardianSessionId, workloadId);

        vm.expectEmit(true, true, true, true);
        emit IGuardianModule.RotatedGuardianKey(newGuardian, vm.addr(newSKEnclave), newEnclavePubKey);
        guardianModule.rotateGuardianKey(
            0,
            newEnclavePubKey,
            GuardianSessionProof({
                sessionId: newGuardianSessionId,
                sessionKey: newGuardianSessionPublicIdentity,
                ownerKey: newGuardianOwnerPublicIdentity,
                signature: signature
            })
        );

        assertEq(guardianModule.getGuardiansEnclaveAddress(newGuardian), vm.addr(newSKEnclave), "bad enclave address");
    }
}
