// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./CipherGovernance.sol";

/// @title CipherDAOFactory
/// @notice Permissionless factory for deploying private CipherDAO instances
/// @dev Zero FHE operations here. Factory only deploys governance contracts.
///      All FHE operations happen inside CipherGovernance.
contract CipherDAOFactory {

    // -------------------------------------------------------
    // STATE
    // -------------------------------------------------------

    address[] public allDAOs;
    mapping(address => address[]) public daosByAdmin;
    mapping(address => bool) public isValidDAO;

    // -------------------------------------------------------
    // EVENTS
    // -------------------------------------------------------

    event DAODeployed(
        address indexed dao,
        address indexed admin,
        string name,
        uint256 timestamp
    );

    // -------------------------------------------------------
    // DEPLOY
    // -------------------------------------------------------

    /// @notice Deploy a new private DAO instance
    /// @param name Human-readable name for the DAO
    /// @param votingPeriodBlocks How many blocks voting stays open
    /// @param quorumThreshold Minimum votes for proposal to pass (plaintext for MVP)
    /// @return dao Address of the deployed CipherGovernance contract
    function deployDAO(
        string calldata name,
        uint32 votingPeriodBlocks,
        uint64 quorumThreshold
    ) external returns (address dao) {
        require(votingPeriodBlocks > 0, "Voting period must be > 0");
        require(quorumThreshold > 0, "Quorum must be > 0");

        CipherGovernance governance = new CipherGovernance(
            msg.sender,
            name,
            votingPeriodBlocks,
            quorumThreshold
        );

        dao = address(governance);
        allDAOs.push(dao);
        daosByAdmin[msg.sender].push(dao);
        isValidDAO[dao] = true;

        emit DAODeployed(dao, msg.sender, name, block.timestamp);
    }

    // -------------------------------------------------------
    // VIEWS
    // -------------------------------------------------------

    function getDAOsByAdmin(address admin) external view returns (address[] memory) {
        return daosByAdmin[admin];
    }

    function getAllDAOs() external view returns (address[] memory) {
        return allDAOs;
    }

    function totalDAOs() external view returns (uint256) {
        return allDAOs.length;
    }
}