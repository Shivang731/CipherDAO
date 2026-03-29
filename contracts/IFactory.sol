// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IFactory
/// @notice Permissionless factory for deploying private CipherDAO instances
/// @dev Factory has ZERO FHE operations — it only deploys governance contract clones.
///      This keeps factory gas costs low and architecture clean.
///      All FHE operations happen inside the deployed Governance and Treasury contracts.
interface IFactory {

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
    // STRUCTS
    // -------------------------------------------------------

    struct DAOConfig {
        string name;
        address membershipToken;      // ERC20 for token-weighted voting. address(0) = equal weight per member.
        uint32 votingPeriodBlocks;    // how many blocks a vote stays open
        address admin;                // initial admin address
        bool treasuryEnabled;         // whether to deploy Treasury module alongside Governance
    }

    // -------------------------------------------------------
    // CORE FUNCTIONS
    // -------------------------------------------------------

    /// @notice Deploy a new private DAO instance permissionlessly
    /// @param config DAO configuration — all public data, no sensitive information here
    /// @return dao Address of the deployed Governance contract
    /// @return treasury Address of the deployed Treasury contract (address(0) if disabled)
    function deployDAO(
        DAOConfig calldata config
    ) external returns (address dao, address treasury);

    // -------------------------------------------------------
    // VIEW FUNCTIONS
    // -------------------------------------------------------

    /// @notice Get all DAOs deployed by a specific admin
    function getDAOsByAdmin(
        address admin
    ) external view returns (address[] memory);

    /// @notice Get all DAOs deployed through this factory
    function getAllDAOs() external view returns (address[] memory);

    /// @notice Total number of DAOs deployed
    function totalDAOs() external view returns (uint256);

    /// @notice Check if an address is a CipherDAO deployed by this factory
    function isValidDAO(address dao) external view returns (bool);
}