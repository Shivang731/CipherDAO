// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@fhenixprotocol/cofhe-contracts/contracts/FHE.sol";

/// @title ITreasury
/// @notice Private treasury execution module for CipherDAO
/// @dev Key design decision: all treasury calls are wrapped in FHE.select.
/// Failed proposal = silent no-op with NO observable difference from success.
/// This prevents side-channel leaks — a blockchain observer cannot distinguish
/// a passing proposal from a failing one by watching execution.
///
/// Payment rails use the Privara SDK (@reineira-os/sdk) for
/// confidential stablecoin transfers where amounts and recipients stay encrypted.
interface ITreasury {
    // -------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------
    /// @notice Emitted when a treasury action is attached to a proposal
    /// @dev actionHash is a public commitment — amounts and recipients stay encrypted
    event TreasuryActionQueued(
        uint256 indexed proposalId,
        bytes32 actionHash
    );
    /// @notice Emitted after executeAction() is called
    /// @dev emitted regardless of pass/fail — observer cannot distinguish the two
    event TreasuryActionSettled(uint256 indexed proposalId);

    // -------------------------------------------------------
    // STRUCTS
    // -------------------------------------------------------
    struct TreasuryAction {
        inEuint128 encryptedAmount; // payment amount — stays encrypted
        inEaddress encryptedRecipient; // recipient address — stays encrypted
        uint8 tokenType; // 0=native ETH, 1=USDC, 2=custom ERC20
        bytes32 actionHash; // public commitment to this action (for auditability)
    }

    // -------------------------------------------------------
    // CORE FUNCTIONS
    // -------------------------------------------------------
    /// @notice Attach an encrypted treasury action to a proposal before voting starts
    /// @param proposalId The proposal this action is tied to
    /// @param action Encrypted action — amount and recipient encrypted client-side
    function attachAction(
        uint256 proposalId,
        TreasuryAction calldata action
    ) external;

    /// @notice Execute or silently skip treasury action based on proposal outcome
    /// @dev Core privacy property:
    /// amount = FHE.select(passed, encryptedAmount, FHE.asEuint128(0))
    /// If proposal failed, amount resolves to zero — Privara transfer is a no-op.
    /// Gas cost and execution path are IDENTICAL for pass and fail.
    /// No external observer can tell which outcome occurred.
    /// @param proposalId Proposal to settle treasury action for
    function executeAction(uint256 proposalId) external;

    // -------------------------------------------------------
    // FUNDING
    // -------------------------------------------------------
    /// @notice Fund the treasury with an encrypted deposit
    /// @param encryptedAmount Amount encrypted client-side via @cofhe/sdk
    function deposit(inEuint128 calldata encryptedAmount) external payable;

    /// @notice Get the treasury's encrypted balance
    /// @dev Only treasury admin can decrypt this via FHE.allow permit
    function encryptedBalance() external view returns (euint128);

    // -------------------------------------------------------
    // SELECTIVE DISCLOSURE
    // -------------------------------------------------------
    /// @notice Grant an auditor permission to decrypt treasury data for a specific proposal
    /// @dev FHE.allow — scoped to proposalId only. Auditor sees the amount for that
    /// proposal but nothing else. Time-bounded in Wave 3+.
    /// @param auditor Auditor address
    /// @param proposalId Proposal to grant access for
    function grantAuditorAccess(
        address auditor,
        uint256 proposalId
    ) external;
}