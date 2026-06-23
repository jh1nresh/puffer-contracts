// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { Permit } from "../structs/Permit.sol";

/**
 * @title IPufferDepositorV2
 * @author Puffer Finance
 * @custom:security-contact security@puffer.fi
 */
interface IPufferDepositorV2 {
    /**
     * @notice Emitted when the admin role sends a token or native ETH out of the contract.
     * @param by The caller that authorized the rescue.
     * @param token The token sent, or address(0) for native ETH.
     * @param to The recipient.
     * @param amount The requested amount to be sent.
     */
    event Rescued(address indexed by, address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Deposits wrapped stETH (wstETH) into the Puffer Vault
     * @param permitData The permit data containing the approval information
     * @param recipient The recipient of pufETH tokens
     * @return pufETHAmount The amount of pufETH received from the deposit
     */
    function depositWstETH(Permit calldata permitData, address recipient) external returns (uint256 pufETHAmount);

    /**
     * @notice Deposits stETH into the Puffer Vault using Permit
     * @param permitData The permit data containing the approval information
     * @param recipient The recipient of pufETH tokens
     * @return pufETHAmount The amount of pufETH received from the deposit
     */
    function depositStETH(Permit calldata permitData, address recipient) external returns (uint256 pufETHAmount);

    /**
     * @notice Admin sends `amount` of `token` to `to`. Pass `token == address(0)` for native ETH.
     *         Rescues stuck or mistakenly-sent tokens, and can move any asset out of the contract.
     * @dev Reverts on `to == address(0)` (InvalidAddress), on `to == address(this)` (InvalidAddress), and on a
     *      failed native ETH send (EthTransferFailed). Restricted to the admin role; frozen while the vault
     *      target is paused. Emits Rescued.
     * @param token The token to send, or address(0) for native ETH.
     * @param to The recipient.
     * @param amount The requested amount to send.
     */
    function rescueAnything(address token, address to, uint256 amount) external;
}
