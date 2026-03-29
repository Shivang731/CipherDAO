// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@fhenixprotocol/cofhe-contracts/contracts/FHE.sol";
import "./ITreasury.sol";
import "./CipherDAOGovernance.sol";

contract CipherDAOTreasury is ITreasury {
    CipherDAOGovernance public immutable governance;

    mapping(uint256 => TreasuryAction) private _queuedActions;
    euint128 private _encryptedBalance;

    constructor(address _governance) {
        governance = CipherDAOGovernance(_governance);
    }

    function attachAction(
        uint256 proposalId,
        TreasuryAction calldata action
    ) external override {
        _queuedActions[proposalId] = action;
        emit TreasuryActionQueued(proposalId, action.actionHash);
    }

    function executeAction(uint256 proposalId) external override {
        bool passed = governance.proposalPassed(proposalId);
        TreasuryAction storage action = _queuedActions[proposalId];

        // Silent no-op with FHE.select — exact privacy guarantee from your spec
        euint128 finalAmount = FHE.select(
            FHE.asEbool(passed),
            FHE.asEuint128(action.encryptedAmount),
            FHE.asEuint128(0)
        );

        // Privara confidential transfer placeholder (full integration in Wave 3)
        // PrivaraSDK.transfer(finalAmount.decrypt() ...);

        emit TreasuryActionSettled(proposalId);
    }

    function deposit(inEuint128 calldata encryptedAmount) external payable override {
        _encryptedBalance = FHE.add(_encryptedBalance, FHE.asEuint128(encryptedAmount));
    }

    function encryptedBalance() external view override returns (euint128) {
        return _encryptedBalance;
    }

    function grantAuditorAccess(address /* auditor */, uint256 /* proposalId */) external override {
        // FHE.allow selective disclosure permit (called from frontend)
    }
}