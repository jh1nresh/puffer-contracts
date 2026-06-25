// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import { PufferProtocol } from "../../src/PufferProtocol.sol";
import { IGuardianModule } from "../../src/interface/IGuardianModule.sol";
import { PufferVaultV5 } from "../../src/PufferVaultV5.sol";
import { ValidatorTicket } from "../../src/ValidatorTicket.sol";
import { IPufferOracleV2 } from "../../src/interface/IPufferOracleV2.sol";
import { ProtocolStorage } from "../../src/PufferProtocolStorage.sol";

contract PufferProtocolSetterMock is PufferProtocol {
    constructor(
        PufferVaultV5 pufferVault,
        IGuardianModule guardianModule,
        address moduleManager,
        ValidatorTicket validatorTicket,
        IPufferOracleV2 oracle,
        address beaconDepositContract
    ) PufferProtocol(pufferVault, guardianModule, moduleManager, validatorTicket, oracle, beaconDepositContract) { }

    function setNodeVtBalance(address node, uint96 vtBalance) external {
        ProtocolStorage storage $ = _getPufferProtocolStorage();
        $.nodeOperatorInfo[node].vtBalance = vtBalance;
    }
}
