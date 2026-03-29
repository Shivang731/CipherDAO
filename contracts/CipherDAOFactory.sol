// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IFactory.sol";
import "./CipherDAOGovernance.sol";
import "./CipherDAOTreasury.sol";

contract CipherDAOFactory is IFactory {
    address[] private _allDAOs;
    mapping(address => address[]) private _daosByAdmin;
    mapping(address => bool) private _isValidDAO;

    function deployDAO(DAOConfig calldata config) external override returns (address dao, address treasury) {
        CipherDAOGovernance governance = new CipherDAOGovernance();
        treasury = config.treasuryEnabled 
            ? address(new CipherDAOTreasury(address(governance))) 
            : address(0);

        dao = address(governance);

        _allDAOs.push(dao);
        _daosByAdmin[config.admin].push(dao);
        _isValidDAO[dao] = true;

        emit DAODeployed(dao, config.admin, config.name, block.timestamp);
    }

    function getDAOsByAdmin(address admin) external view override returns (address[] memory) {
        return _daosByAdmin[admin];
    }

    function getAllDAOs() external view override returns (address[] memory) {
        return _allDAOs;
    }

    function totalDAOs() external view override returns (uint256) {
        return _allDAOs.length;
    }

    function isValidDAO(address dao) external view override returns (bool) {
        return _isValidDAO[dao];
    }
}