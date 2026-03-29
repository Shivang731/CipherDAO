// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@fhenixprotocol/cofhe-contracts/contracts/FHE.sol";
import "./IGovernance.sol";

contract CipherDAOGovernance is IGovernance {
    Proposal[] private _proposals;
    mapping(uint256 => mapping(address => bool)) private _hasVoted;
    mapping(uint256 => mapping(address => euint8)) private _lastChoice;
    mapping(uint256 => mapping(address => euint64)) private _lastWeight;

    function createProposal(
        inEuint256 calldata /* encryptedDescription */,
        uint32 deadline
    ) external override returns (uint256 proposalId) {
        proposalId = _proposals.length;

        _proposals.push(Proposal({
            creator: msg.sender,
            deadline: deadline,
            finalized: false,
            passed: false,
            forVotes: FHE.asEuint64(0),
            againstVotes: FHE.asEuint64(0),
            quorumThreshold: FHE.asEuint64(0) // can be set later in Wave 2+
        }));

        emit ProposalCreated(proposalId, msg.sender, deadline);
    }

    function castVote(
        uint256 proposalId,
        inEuint8 calldata encryptedChoice,
        inEuint64 calldata encryptedWeight
    ) external override {
        require(proposalId < _proposals.length, "Invalid proposal");
        require(!_proposals[proposalId].finalized, "Already finalized");
        require(block.timestamp < _proposals[proposalId].deadline, "Voting closed");

        euint8 choice = FHE.asEuint8(encryptedChoice);
        euint64 weight = FHE.asEuint64(encryptedWeight);

        _lastChoice[proposalId][msg.sender] = choice;
        _lastWeight[proposalId][msg.sender] = weight;
        _hasVoted[proposalId][msg.sender] = true;

        _proposals[proposalId].forVotes = FHE.select(
            FHE.eq(choice, FHE.asEuint8(1)),
            FHE.add(_proposals[proposalId].forVotes, weight),
            _proposals[proposalId].forVotes
        );
        _proposals[proposalId].againstVotes = FHE.select(
            FHE.eq(choice, FHE.asEuint8(2)),
            FHE.add(_proposals[proposalId].againstVotes, weight),
            _proposals[proposalId].againstVotes
        );

        emit VoteCast(proposalId, msg.sender);
    }

    function revokeAndRevote(
        uint256 proposalId,
        inEuint8 calldata newEncryptedChoice,
        inEuint64 calldata newEncryptedWeight
    ) external override {
        require(_hasVoted[proposalId][msg.sender], "No vote to revoke");

        euint8 oldChoice = _lastChoice[proposalId][msg.sender];
        euint64 oldWeight = _lastWeight[proposalId][msg.sender];

        // Subtract old weight homomorphically
        _proposals[proposalId].forVotes = FHE.select(
            FHE.eq(oldChoice, FHE.asEuint8(1)),
            FHE.sub(_proposals[proposalId].forVotes, oldWeight),
            _proposals[proposalId].forVotes
        );
        _proposals[proposalId].againstVotes = FHE.select(
            FHE.eq(oldChoice, FHE.asEuint8(2)),
            FHE.sub(_proposals[proposalId].againstVotes, oldWeight),
            _proposals[proposalId].againstVotes
        );

        // Cast new vote
        castVote(proposalId, newEncryptedChoice, newEncryptedWeight);

        emit VoteRevoked(proposalId, msg.sender);
    }

    function finalizeTally(uint256 proposalId) external override {
        require(proposalId < _proposals.length, "Invalid proposal");
        require(!_proposals[proposalId].finalized, "Already finalized");
        require(block.timestamp >= _proposals[proposalId].deadline, "Voting still open");

        Proposal storage p = _proposals[proposalId];
        ebool passed = FHE.gt(p.forVotes, p.againstVotes);

        p.finalized = true;
        p.passed = FHE.decrypt(passed); // only boolean outcome revealed

        emit ProposalFinalized(proposalId, p.passed);
    }

    function grantAuditorPermit(address /* auditor */, uint256 /* proposalId */) external override {
        // FHE.allow permit logic will be called from frontend in Wave 2
    }

    function proposalPassed(uint256 proposalId) external view override returns (bool) {
        return _proposals[proposalId].passed;
    }

    function isVotingOpen(uint256 proposalId) external view override returns (bool) {
        return block.timestamp < _proposals[proposalId].deadline;
    }

    function hasVoted(uint256 proposalId, address member) external view override returns (bool) {
        return _hasVoted[proposalId][member];
    }
}