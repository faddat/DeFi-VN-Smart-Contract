// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract DFYAccessControl is AccessControlUpgradeable {
    using AddressUpgradeable for address;
    
    /**
    * @dev OPERATOR_ROLE: those who have this role can assigne EVALUATOR_ROLE to others
    */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
    * @dev PAUSER_ROLE: those who can pause the contract
    * by default this role is assigned to the contract creator
    *
    * NOTE: The main contract must inherit `Pausable` or this ROLE doesn't make sense
    */ 
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
    * @dev EVALUATOR_ROLE: Whitelisted Evaluators who can mint NFT token after evaluation has been accepted.
    */
    bytes32 public constant EVALUATOR_ROLE = keccak256("EVALUATOR_ROLE");

    function __DFYAccessControl_init() internal initializer {
        __AccessControl_init();

        __DFYAccessControl_init_unchained();
    }

    function __DFYAccessControl_init_unchained() internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
        
        // Set OPERATOR_ROLE as EVALUATOR_ROLE's Admin Role 
        _setRoleAdmin(EVALUATOR_ROLE, OPERATOR_ROLE);
    }

    event ContractAdminChanged(address from, address to);

    function setOperatorRole(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(OPERATOR_ROLE, account);
    }

    function removeOperatorRole(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(PAUSER_ROLE, account);
    }

    function setPauserRole(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(PAUSER_ROLE, account);
    }

    function removePauserRole(address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(PAUSER_ROLE, account);
    }

    function setEvaluatorRole(address account) public virtual onlyRole(OPERATOR_ROLE) {
        grantRole(EVALUATOR_ROLE, account);
    }

    function removeEvaluatorRole(address account) public virtual onlyRole(OPERATOR_ROLE) {
        revokeRole(EVALUATOR_ROLE, account);
    }

    function changeContractAdmin(address newAdmin) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        // Check if the new Admin address is a contract address
        require(!newAdmin.isContract(), "New admin must not be a contract");
        
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        renounceRole(DEFAULT_ADMIN_ROLE, _msgSender());

        emit ContractAdminChanged(_msgSender(), newAdmin);
    }
}