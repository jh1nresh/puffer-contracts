// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { PufferDepositor } from "src/PufferDepositor.sol";
import { Timelock } from "src/Timelock.sol";
import { PauserContract } from "src/PauserContract.sol";
import { PufferVaultV5 } from "src/PufferVaultV5.sol";
import { stETHMock } from "test/mocks/stETHMock.sol";
import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { PufferDeployment } from "src/structs/PufferDeployment.sol";
import { DeployPufETH } from "script/DeployPufETH.s.sol";
import { UUPSUpgradeable } from "@openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ROLE_ID_PAUSER } from "script/Roles.sol";

contract PauserContractTest is Test {
    PufferDepositor public pufferDepositor;
    PufferVaultV5 public pufferVault;
    AccessManager public accessManager;
    stETHMock public stETH;
    Timelock public timelock;
    PauserContract public pauserContract;

    address public pauser = makeAddr("pauser");

    address public constant BROADCASTER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        PufferDeployment memory deployment = new DeployPufETH().run();

        pufferDepositor = PufferDepositor(payable(deployment.pufferDepositor));
        pufferVault = PufferVaultV5(payable(deployment.pufferVault));
        accessManager = AccessManager(payable(deployment.accessManager));
        stETH = stETHMock(payable(deployment.stETH));
        timelock = Timelock(payable(deployment.timelock));

        pauserContract = new PauserContract(address(accessManager), address(timelock));

        // Grant the PauserContract permission to act as the Timelock's pauserMultisig
        vm.prank(timelock.COMMUNITY_MULTISIG());
        timelock.executeTransaction(address(timelock), abi.encodeCall(Timelock.setPauser, (address(pauserContract))), 1);

        // Wire up AccessManager so `pauser` can call pause / pauseSelectors on the PauserContract
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = PauserContract.pause.selector;
        selectors[1] = PauserContract.pauseSelectors.selector;

        vm.startPrank(address(timelock));
        accessManager.setTargetFunctionRole(address(pauserContract), selectors, ROLE_ID_PAUSER);
        accessManager.grantRole(ROLE_ID_PAUSER, pauser, 0);
        vm.stopPrank();
    }

    function test_constructor_setsImmutables() public view {
        assertEq(address(pauserContract.TIMELOCK()), address(timelock), "TIMELOCK not set");
        assertEq(pauserContract.authority(), address(accessManager), "authority not set");
    }

    function test_pause_revertsIfCallerUnauthorized(address caller) public {
        vm.assume(caller != pauser);
        vm.assume(caller != BROADCASTER);

        address[] memory targets = new address[](1);
        targets[0] = address(pufferDepositor);

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        vm.prank(caller);
        pauserContract.pause(targets);
    }

    function test_pauseSelectors_revertsIfCallerUnauthorized(address caller) public {
        vm.assume(caller != pauser);
        vm.assume(caller != BROADCASTER);

        address[] memory targets = new address[](1);
        targets[0] = address(pufferDepositor);

        bytes4[][] memory selectors = new bytes4[][](1);
        selectors[0] = new bytes4[](1);
        selectors[0][0] = PufferDepositor.swapAndDeposit.selector;

        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, caller));
        vm.prank(caller);
        pauserContract.pauseSelectors(targets, selectors);
    }

    function test_pause_forwardsToTimelock(address caller) public {
        vm.assume(caller != address(timelock));
        vm.assume(caller != address(accessManager));
        vm.assume(caller != BROADCASTER);

        address[] memory targets = new address[](1);
        targets[0] = address(pufferDepositor);

        (bool canCall,) =
            accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.swapAndDeposit.selector);
        assertTrue(canCall, "swapAndDeposit should not be paused");

        (canCall,) =
            accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.swapAndDepositWithPermit.selector);
        assertTrue(canCall, "swapAndDepositWithPermit should not be paused");

        (canCall,) = accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.depositWstETH.selector);
        assertTrue(canCall, "depositWstETH should not be paused");

        vm.prank(pauser);
        pauserContract.pause(targets);

        (canCall,) = accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.swapAndDeposit.selector);
        assertFalse(canCall, "swapAndDeposit should be paused");

        (canCall,) =
            accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.swapAndDepositWithPermit.selector);
        assertFalse(canCall, "swapAndDepositWithPermit should be paused");

        (canCall,) = accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.depositWstETH.selector);
        assertFalse(canCall, "depositWstETH should be paused");
    }

    function test_pauseSelectors_forwardsToTimelock(address caller) public {
        vm.assume(caller != address(timelock));
        vm.assume(caller != address(accessManager));

        address[] memory targets = new address[](1);
        targets[0] = address(pufferDepositor);

        bytes4[][] memory selectors = new bytes4[][](1);
        selectors[0] = new bytes4[](1);
        selectors[0][0] = PufferDepositor.swapAndDeposit.selector;

        vm.prank(pauser);
        pauserContract.pauseSelectors(targets, selectors);

        (bool canCall,) =
            accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.swapAndDeposit.selector);
        assertFalse(canCall, "swapAndDeposit should be paused");

        // Other selectors on the same target remain callable
        (canCall,) =
            accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.swapAndDepositWithPermit.selector);
        assertTrue(canCall, "swapAndDepositWithPermit should still be callable");

        (canCall,) = accessManager.canCall(caller, address(pufferDepositor), PufferDepositor.depositWstETH.selector);
        assertTrue(canCall, "depositWstETH should still be callable");
    }

    function test_pause_revertsIfNotTimelockPauser() public {
        // Replace PauserContract on the Timelock with a different address so the forwarded call fails
        vm.prank(timelock.COMMUNITY_MULTISIG());
        timelock.executeTransaction(address(timelock), abi.encodeCall(Timelock.setPauser, (makeAddr("otherPauser"))), 2);

        address[] memory targets = new address[](1);
        targets[0] = address(pufferDepositor);

        vm.expectRevert(abi.encodeWithSelector(Timelock.Unauthorized.selector));
        vm.prank(pauser);
        pauserContract.pause(targets);
    }
}
