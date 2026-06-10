// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import { Timelock } from "./Timelock.sol";
import { InvalidAddress } from "./Errors.sol";

/**
 * @title PauserContract
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 * @notice Access-controlled entry point that forwards pause actions to the Timelock
 */
contract PauserContract is AccessManaged {
    /**
     * @notice The Timelock contract this pauser forwards calls to
     */
    Timelock public immutable TIMELOCK;

    /**
     * @param accessManager The AccessManager that governs which callers may invoke the restricted functions
     * @param timelock The Timelock contract to forward pause actions to
     */
    constructor(address accessManager, address timelock) AccessManaged(accessManager) {
        require(timelock != address(0), InvalidAddress());
        TIMELOCK = Timelock(timelock);
    }

    /**
     * @notice Pauses the system by closing access to the specified targets
     * @dev Forwards the call to {Timelock.pause}; restricted by the AccessManager
     * @param targets An array of addresses to which access will be paused
     */
    function pause(address[] calldata targets) external restricted {
        TIMELOCK.pause(targets);
    }

    /**
     * @notice Pauses the system by closing access to the specified target selectors
     * @dev Forwards the call to {Timelock.pauseSelectors}; restricted by the AccessManager
     * @param targets An array of addresses to which access will be paused
     * @param selectors A per-target array of selectors to which access will be paused
     */
    function pauseSelectors(address[] calldata targets, bytes4[][] calldata selectors) external restricted {
        TIMELOCK.pauseSelectors(targets, selectors);
    }
}
