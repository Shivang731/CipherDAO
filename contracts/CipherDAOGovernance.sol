// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title CipherGovernance
/// @notice Private DAO governance with FHE-encrypted votes and homomorphic tally
/// @dev Core privacy properties:
///      - Vote choices stored as euint8 ciphertexts
///      - Vote weights stored as euint64 ciphertexts
///      - Tally runs via FHE.add — no individual vote ever decrypted
///      - Only the final boolean outcome is revealed via threshold decryption
///      - Voters can revoke and revote before deadline (no on-chain receipt)
contract CipherGovernance {

    // -------------------------------------------------------
    // STATE
    // -------------------------------------------------------

    address public admin;
    string public daoName;
    uint32 public votingPeriodBlocks;
    uint64 public quorumThreshold;

    uint256 public proposalCount;

    struct Proposal {
        address creator;
        uint32 deadline;
        bool finalized;
        bool passed;
        euint64 forVotes;       // encrypted accumulator — FHE.add only
        euint64 againstVotes;   // encrypted accumulator — FHE.add only
        uint256 totalVoters;    // plaintext count (not weight) for gas efficiency
    }

    mapping(uint256 => Proposal) public proposals;

    // voter => proposalId => encrypted weight they cast (for revoke logic)
    mapping(address => mapping(uint256 => euint64)) private voterWeight;
    mapping(address => mapping(uint256 => euint8)) private voterChoice;
    mapping(address => mapping(uint256 => bool)) public hasVoted;

    // Members allowed to vote
    mapping(address => bool) public isMember;

    // -------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------

    event ProposalCreated(uint256 indexed proposalId, address indexed creator, uint32 deadline);
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    event VoteRevoked(uint256 indexed proposalId, address indexed voter);
    event ProposalFinalized(uint256 indexed proposalId, bool passed);
    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);

    // -------------------------------------------------------
    // MODIFIERS
    // -------------------------------------------------------

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyMember() {
        require(isMember[msg.sender], "Not a member");
        _;
    }

    // -------------------------------------------------------
    // CONSTRUCTOR
    // -------------------------------------------------------

    constructor(
        address _admin,
        string memory _name,
        uint32 _votingPeriodBlocks,
        uint64 _quorumThreshold
    ) {
        admin = _admin;
        daoName = _name;
        votingPeriodBlocks = _votingPeriodBlocks;
        quorumThreshold = _quorumThreshold;
        isMember[_admin] = true;
    }

    // -------------------------------------------------------
    // MEMBERSHIP
    // -------------------------------------------------------

    function addMember(address member) external onlyAdmin {
        isMember[member] = true;
        emit MemberAdded(member);
    }

    function removeMember(address member) external onlyAdmin {
        isMember[member] = false;
        emit MemberRemoved(member);
    }

    // -------------------------------------------------------
    // PROPOSALS
    // -------------------------------------------------------

    /// @notice Create a new proposal
    /// @dev Proposal content is off-chain or encrypted — only deadline stored on-chain
    function createProposal() external onlyMember returns (uint256 proposalId) {
        proposalId = proposalCount++;
        uint32 deadline = uint32(block.number) + votingPeriodBlocks;

        proposals[proposalId] = Proposal({
            creator: msg.sender,
            deadline: deadline,
            finalized: false,
            passed: false,
            forVotes: FHE.asEuint64(0),
            againstVotes: FHE.asEuint64(0),
            totalVoters: 0
        });

        emit ProposalCreated(proposalId, msg.sender, deadline);
    }

    // -------------------------------------------------------
    // VOTING — CORE FHE OPERATIONS
    // -------------------------------------------------------

    /// @notice Cast an encrypted vote
    /// @param proposalId Target proposal
    /// @param encryptedChoice inEuint8 — 1=For, 2=Against (encrypted client-side)
    /// @param encryptedWeight inEuint64 — voting weight (encrypted client-side)
    /// @dev FHE.add accumulates votes homomorphically.
    ///      FHE.select routes weight to forVotes or againstVotes based on encrypted choice.
    ///      No individual vote is ever decrypted during this process.
    function castVote(
        uint256 proposalId,
        inEuint8 calldata encryptedChoice,
        inEuint64 calldata encryptedWeight
    ) external onlyMember {
        Proposal storage p = proposals[proposalId];
        require(block.number < p.deadline, "Voting closed");
        require(!p.finalized, "Already finalized");
        require(!hasVoted[msg.sender][proposalId], "Already voted — use revokeAndRevote");

        // Convert encrypted inputs to FHE handles
        euint8 choice = FHE.asEuint8(encryptedChoice);
        euint64 weight = FHE.asEuint64(encryptedWeight);

        // FHE.select: if choice == 1 (For), add weight to forVotes, else add to againstVotes
        // This is entirely on ciphertexts — no branching based on plaintext values
        euint8 forChoice = FHE.asEuint8(1);
        ebool isFor = FHE.eq(choice, forChoice);

        euint64 forWeight = FHE.select(isFor, weight, FHE.asEuint64(0));
        euint64 againstWeight = FHE.select(isFor, FHE.asEuint64(0), weight);

        p.forVotes = FHE.add(p.forVotes, forWeight);
        p.againstVotes = FHE.add(p.againstVotes, againstWeight);
        p.totalVoters++;

        // Store encrypted vote for potential revocation
        voterChoice[msg.sender][proposalId] = choice;
        voterWeight[msg.sender][proposalId] = weight;
        hasVoted[msg.sender][proposalId] = true;

        // Allow voter to decrypt their own vote (for self-verification only)
        FHE.allow(choice, msg.sender);
        FHE.allow(weight, msg.sender);

        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Revoke previous vote and cast a new one before deadline
    /// @dev Revocable voting — subtracts old weight, adds new weight homomorphically.
    ///      Key privacy property: no coercer can prove how you voted because
    ///      you can silently change your vote before the deadline.
    function revokeAndRevote(
        uint256 proposalId,
        inEuint8 calldata newEncryptedChoice,
        inEuint64 calldata newEncryptedWeight
    ) external onlyMember {
        Proposal storage p = proposals[proposalId];
        require(block.number < p.deadline, "Voting closed");
        require(!p.finalized, "Already finalized");
        require(hasVoted[msg.sender][proposalId], "No vote to revoke");

        // Subtract old vote homomorphically
        euint8 oldChoice = voterChoice[msg.sender][proposalId];
        euint64 oldWeight = voterWeight[msg.sender][proposalId];

        euint8 forChoice = FHE.asEuint8(1);
        ebool wasFor = FHE.eq(oldChoice, forChoice);

        euint64 oldForWeight = FHE.select(wasFor, oldWeight, FHE.asEuint64(0));
        euint64 oldAgainstWeight = FHE.select(wasFor, FHE.asEuint64(0), oldWeight);

        p.forVotes = FHE.sub(p.forVotes, oldForWeight);
        p.againstVotes = FHE.sub(p.againstVotes, oldAgainstWeight);

        // Add new vote
        euint8 newChoice = FHE.asEuint8(newEncryptedChoice);
        euint64 newWeight = FHE.asEuint64(newEncryptedWeight);

        ebool isFor = FHE.eq(newChoice, forChoice);
        euint64 newForWeight = FHE.select(isFor, newWeight, FHE.asEuint64(0));
        euint64 newAgainstWeight = FHE.select(isFor, FHE.asEuint64(0), newWeight);

        p.forVotes = FHE.add(p.forVotes, newForWeight);
        p.againstVotes = FHE.add(p.againstVotes, newAgainstWeight);

        voterChoice[msg.sender][proposalId] = newChoice;
        voterWeight[msg.sender][proposalId] = newWeight;

        emit VoteRevoked(proposalId, msg.sender);
        emit VoteCast(proposalId, msg.sender);
    }

    // -------------------------------------------------------
    // TALLY — DECRYPT ONLY THE BOOLEAN OUTCOME
    // -------------------------------------------------------

    /// @notice Finalize tally after voting deadline
    /// @dev FHE.gt(forVotes, againstVotes) + quorum check.
    ///      Threshold decryption network reveals ONLY the boolean.
    ///      Individual votes are never decrypted — ever.
    function finalizeTally(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(block.number >= p.deadline, "Voting still open");
        require(!p.finalized, "Already finalized");
        require(p.totalVoters >= quorumThreshold, "Quorum not reached");

        // FHE comparison — runs on ciphertexts, returns encrypted boolean
        ebool forWins = FHE.gt(p.forVotes, p.againstVotes);

        // Decrypt ONLY the boolean outcome via threshold network
        // This is the ONLY decryption in the entire voting lifecycle
        uint8 result = FHE.decrypt(forWins);
        p.passed = result == 1;
        p.finalized = true;

        emit ProposalFinalized(proposalId, p.passed);
    }

    // -------------------------------------------------------
    // SELECTIVE DISCLOSURE — AUDITOR ACCESS
    // -------------------------------------------------------

    /// @notice Grant auditor scoped access to encrypted vote totals for a proposal
    /// @dev FHE.allow — auditor can decrypt forVotes/againstVotes totals only.
    ///      Individual voter choices and weights remain private.
    function grantAuditorPermit(address auditor, uint256 proposalId) external onlyAdmin {
        Proposal storage p = proposals[proposalId];
        require(p.finalized, "Proposal not finalized yet");

        FHE.allow(p.forVotes, auditor);
        FHE.allow(p.againstVotes, auditor);
    }

    // -------------------------------------------------------
    // VIEWS
    // -------------------------------------------------------

    function isVotingOpen(uint256 proposalId) external view returns (bool) {
        return block.number < proposals[proposalId].deadline &&
               !proposals[proposalId].finalized;
    }

    function proposalPassed(uint256 proposalId) external view returns (bool) {
        require(proposals[proposalId].finalized, "Not finalized");
        return proposals[proposalId].passed;
    }

    function getProposal(uint256 proposalId) external view returns (
        address creator,
        uint32 deadline,
        bool finalized,
        bool passed,
        uint256 totalVoters
    ) {
        Proposal storage p = proposals[proposalId];
        return (p.creator, p.deadline, p.finalized, p.passed, p.totalVoters);
    }
}