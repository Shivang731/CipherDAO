// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@fhenixprotocol/cofhe-contracts/contracts/FHE.sol";

/// @title IGovernance
/// @notice Core governance interface for CipherDAO
/// @dev All vote data stays encrypted. Only outcomes are revealed.
interface IGovernance {
    // -------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------
    /// @notice Emitted when a proposal is created (description stays encrypted)
    event ProposalCreated(uint256 indexed proposalId, address indexed creator, uint32 deadline);
    /// @notice Emitted when a vote is cast (choice and weight stay encrypted)
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    /// @notice Emitted when a vote is overwritten before deadline (revocable voting)
    event VoteRevoked(uint256 indexed proposalId, address indexed voter);
    /// @notice Emitted when tally is finalised — only bool outcome revealed
    event ProposalFinalized(uint256 indexed proposalId, bool passed);

    // -------------------------------------------------------
    // STRUCTS
    // -------------------------------------------------------
    struct Proposal {
        address creator;
        uint32 deadline; // block number deadline
        bool finalized;
        bool passed;
        euint64 forVotes; // homomorphic accumulator
        euint64 againstVotes; // homomorphic accumulator
        euint64 quorumThreshold; // encrypted — never revealed
    }

    // -------------------------------------------------------
    // CORE TRANSITIONS
    // -------------------------------------------------------
    /// @notice Create a new proposal
    /// @param encryptedDescription Encrypted proposal payload (client-side via @cofhe/sdk)
    /// @param deadline Block number when voting closes
    /// @return proposalId Unique identifier
    function createProposal(
        inEuint256 calldata encryptedDescription,
        uint32 deadline
    ) external returns (uint256 proposalId);

    /// @notice Cast an encrypted vote
    /// @param proposalId Target proposal
    /// @param encryptedChoice euint8 — 1=For, 2=Against, 3=Abstain
    /// @param encryptedWeight euint64 — voting power (token balance or fixed)
    /// @dev Uses FHE.add to accumulate into forVotes or againstVotes homomorphically
    function castVote(
        uint256 proposalId,
        inEuint8 calldata encryptedChoice,
        inEuint64 calldata encryptedWeight
    ) external;

    /// @notice Overwrite a previous vote before deadline (revocable voting)
    /// @dev Subtracts old weight homomorphically, adds new weight
    function revokeAndRevote(
        uint256 proposalId,
        inEuint8 calldata newEncryptedChoice,
        inEuint64 calldata newEncryptedWeight
    ) external;

    /// @notice Finalize tally after deadline
    /// @dev Runs FHE.gt(forVotes, againstVotes) + FHE.gt(totalVotes, quorumThreshold)
    /// Decrypts only the boolean outcome via threshold network
    /// @param proposalId Proposal to finalize
    function finalizeTally(uint256 proposalId) external;

    // -------------------------------------------------------
    // SELECTIVE DISCLOSURE
    // -------------------------------------------------------
    /// @notice Grant auditor permit to decrypt specific data
    /// @dev Uses FHE.allow — auditor can decrypt only what they are permitted to see
    /// @param auditor Address of the auditor
    /// @param proposalId Proposal to grant access for
    function grantAuditorPermit(address auditor, uint256 proposalId) external;

    // -------------------------------------------------------
    // VIEWS
    // -------------------------------------------------------
    /// @notice Check if a proposal has passed (only available post-finalization)
    function proposalPassed(uint256 proposalId) external view returns (bool);

    /// @notice Check if voting is still open
    function isVotingOpen(uint256 proposalId) external view returns (bool);

    /// @notice Check if member has voted (not HOW they voted)
    function hasVoted(uint256 proposalId, address member) external view returns (bool);
}