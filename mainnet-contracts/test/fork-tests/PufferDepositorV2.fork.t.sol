// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "forge-std/Test.sol";
import { MainnetForkTestHelper } from "../MainnetForkTestHelper.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PufferDepositorV2 } from "../../src/PufferDepositorV2.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { IStETH } from "../../src/interface/Lido/IStETH.sol";
import { GenerateAccessManagerCallData } from "script/GenerateAccessManagerCallData.sol";
import { Permit } from "../../src/structs/Permit.sol";
import { InvalidAddress } from "../../src/Errors.sol";

/**
 * @dev PufferDepositorV2 used to mint against `_ST_ETH.sharesOf(address(this))` (the proxy's whole stETH balance),
 * so any stETH already sitting on the proxy was credited to the next caller. The fix measures the shares
 * contributed by the current call (delta) instead. These tests seed the proxy with stETH up front and assert
 * the next depositor is credited only for their own funds, and that a generic rescue path recovers stranded assets.
 */
contract PufferDepositorV2ForkTest is MainnetForkTestHelper {
    // Override the base setUp: it re-runs initializers that mainnet already consumed (InvalidInitialization).
    // Here we just swap in the working-copy implementation with empty init data (proxy storage already exists).
    function setUp() public virtual override {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 20682408);
        _setupLiveContracts();

        // Upgrade the depositor to the working-copy implementation (no re-init).
        // As the AccessManager admin (Timelock), point the upgrade selector at a role this test holds, then swap.
        PufferDepositorV2 newDepositorImpl =
            new PufferDepositorV2(PufferVaultV5(payable(address(pufferVault))), IStETH(_getStETH()));
        bytes4[] memory upgradeSelector = new bytes4[](1);
        upgradeSelector[0] = UUPSUpgradeable.upgradeToAndCall.selector;
        vm.startPrank(_getTimelock());
        accessManager.setTargetFunctionRole(address(pufferDepositor), upgradeSelector, 1);
        accessManager.grantRole(1, address(this), 0);
        vm.stopPrank();
        UUPSUpgradeable(address(pufferDepositor)).upgradeToAndCall(address(newDepositorImpl), "");

        // Re-apply the public access config (idempotent) so depositStETH/depositWstETH are callable.
        bytes memory encodedMulticall =
            new GenerateAccessManagerCallData().run(address(pufferVault), address(pufferDepositor));
        vm.prank(_getTimelock());
        (bool success,) = address(accessManager).call(encodedMulticall);
        require(success, "access setup failed");
    }

    // An empty/invalid permit. depositStETH/depositWstETH wrap the permit call in try/catch, so the failed
    // permit is swallowed and the transfer falls back to the ERC20 allowance set in the test.
    function _emptyPermit(uint256 amount) internal pure returns (Permit memory) {
        return Permit({ deadline: 0, amount: amount, v: 0, r: bytes32(0), s: bytes32(0) });
    }

    // stETH already on the proxy must NOT be attributed to the next caller.
    function test_depositStETH_doesNotCreditPreExistingStETH()
        public
        giveToken(BLAST_DEPOSIT, address(_ST_ETH), address(pufferDepositor), 2 ether) // stranded stETH
        giveToken(BLAST_DEPOSIT, address(_ST_ETH), alice, 1 ether) // alice's own funds
    {
        uint256 strandedShares = _ST_ETH.sharesOf(address(pufferDepositor));
        assertGt(strandedShares, 0, "precondition: stETH stranded on proxy");

        uint256 depositAmount = 1 ether;
        uint256 expectedShares = pufferVault.convertToShares(depositAmount);

        vm.startPrank(alice);
        IERC20(address(_ST_ETH)).approve(address(pufferDepositor), depositAmount);
        uint256 minted = pufferDepositor.depositStETH(_emptyPermit(depositAmount), alice);
        vm.stopPrank();

        // Alice is credited for ~1 ETH (her deposit), NOT ~3 ETH (stranded + deposit).
        assertApproxEqRel(minted, expectedShares, 0.01e18, "minted must reflect only the caller's deposit");
        assertEq(pufferVault.balanceOf(alice), minted, "recipient holds the minted pufETH");

        // The stranded stETH is untouched. On the buggy implementation it would have been swept to ~0.
        assertEq(_ST_ETH.sharesOf(address(pufferDepositor)), strandedShares, "stranded stETH must remain on the proxy");
    }

    // Same guarantee for the wstETH entrypoint.
    function test_depositWstETH_doesNotCreditPreExistingStETH()
        public
        giveToken(BLAST_DEPOSIT, address(_ST_ETH), address(pufferDepositor), 2 ether) // stranded stETH
        giveToken(BLAST_DEPOSIT, address(_ST_ETH), alice, 2 ether) // alice wraps part of this into wstETH
    {
        uint256 strandedShares = _ST_ETH.sharesOf(address(pufferDepositor));

        vm.startPrank(alice);
        IERC20(address(_ST_ETH)).approve(address(_WST_ETH), 1 ether);
        uint256 wstAmount = _WST_ETH.wrap(1 ether);
        IERC20(address(_WST_ETH)).approve(address(pufferDepositor), wstAmount);
        uint256 minted = pufferDepositor.depositWstETH(_emptyPermit(wstAmount), alice);
        vm.stopPrank();

        // ~1 ETH of stETH was unwrapped and deposited for alice; stranded stETH is untouched.
        uint256 expectedShares = pufferVault.convertToShares(1 ether);
        assertApproxEqRel(minted, expectedShares, 0.01e18, "minted must reflect only the caller's wstETH");
        assertEq(pufferVault.balanceOf(alice), minted, "recipient holds the minted pufETH");
        assertEq(_ST_ETH.sharesOf(address(pufferDepositor)), strandedShares, "stranded stETH must remain on the proxy");
    }

    // rescueAnything is restricted; an arbitrary caller cannot sweep funds.
    function test_rescueAnything_revertsForUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        vm.prank(alice);
        pufferDepositor.rescueAnything(address(_ST_ETH), bob, 1 ether);
    }

    // The authorized caller (AccessManager admin / Timelock) can recover stranded ERC20s.
    function test_rescueAnything_recoversStrandedStETH()
        public
        giveToken(BLAST_DEPOSIT, address(_ST_ETH), address(pufferDepositor), 2 ether)
    {
        uint256 amount = 1 ether;
        uint256 bobBefore = _ST_ETH.balanceOf(bob);

        vm.prank(_getTimelock());
        pufferDepositor.rescueAnything(address(_ST_ETH), bob, amount);

        assertApproxEqAbs(_ST_ETH.balanceOf(bob) - bobBefore, amount, 2, "bob receives the rescued stETH");
    }

    // The token == address(0) branch recovers native ETH.
    function test_rescueAnything_recoversStrandedETH() public {
        uint256 amount = 1 ether;
        vm.deal(address(pufferDepositor), amount);
        uint256 bobBefore = bob.balance;

        vm.prank(_getTimelock());
        pufferDepositor.rescueAnything(address(0), bob, amount);

        assertEq(bob.balance - bobBefore, amount, "bob receives the rescued ETH");
    }

    function test_rescueAnything_revertsForZeroRecipient() public {
        vm.expectRevert(InvalidAddress.selector);
        vm.prank(_getTimelock());
        pufferDepositor.rescueAnything(address(_ST_ETH), address(0), 1 ether);
    }

    function test_rescueAnything_revertsForSelfRecipient() public {
        vm.expectRevert(InvalidAddress.selector);
        vm.prank(_getTimelock());
        pufferDepositor.rescueAnything(address(_ST_ETH), address(pufferDepositor), 1 ether);
    }
}
