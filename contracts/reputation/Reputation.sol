// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Will be replaced by DFY-AccessControl when it's merged.
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


contract Reputation is PausableUpgradeable, AccessControlUpgradeable {

    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using AddressUpgradeable for address;

    /**
    * @dev PAUSER_ROLE: those who can pause the contract
    * by default this role is assigned _to the contract creator.
    */ 
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // mapping of user address's reputation score
    mapping (address => uint32) private _reputationScore;

    address _contractCaller;

    // Reason for Reputation point adjustment
    /**
    * @dev Reputation points in correspondence with ReasonType 
    * LD_CREATE_PACKAGE     : +3
    * LD_CANCEL_PACKAGE     : -3
    * LD_REOPEN_PACKAGE     : +3
    * LD_GENERATE_CONTRACT  : +1
    * LD_CREATE_OFFER       : +2
    * LD_CANCEL_OFFER       : -2
    * BR_CREATE_COLLATERAL  : +3
    * BR_CANCEL_COLLATERAL  : -3
    * BR_ONTIME_PAYMENT     : +1
    * BR_LATE_PAYMENT       : -1
    * BR_ACCEPT_OFFER       : +1
    * BR_CONTRACT_COMPLETE  : +5
    * BR_CONTRACT_DEFAULTED : -5
    */ 

    enum ReasonType {
        LD_CREATE_PACKAGE, 
        LD_CANCEL_PACKAGE,
        LD_REOPEN_PACKAGE,
        LD_GENERATE_CONTRACT,
        LD_CREATE_OFFER,
        LD_CANCEL_OFFER,
        BR_CREATE_COLLATERAL,
        BR_CANCEL_COLLATERAL,
        BR_ONTIME_PAYMENT,
        BR_LATE_PAYMENT,
        BR_ACCEPT_OFFER,
        BR_CONTRACT_COMPLETE,
        BR_CONTRACT_DEFAULTED
    }

    mapping(ReasonType => int8) RewardByReason; 

    event ReputationPointRewarded(address _user, uint256 _points, ReasonType _reasonType);
    event ReputationPointReduced(address _user, uint256 _points, ReasonType _reasonType);
    
    function initialize() public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);

        //initialize Reward by Reason mapping values.
        _initializeRewardByReason();
    }

    function _initializeRewardByReason() internal {
        RewardByReason[ReasonType.LD_CREATE_PACKAGE]    =  3;
        RewardByReason[ReasonType.LD_CANCEL_OFFER]      = -3;
        RewardByReason[ReasonType.LD_REOPEN_PACKAGE]    =  3;
        RewardByReason[ReasonType.LD_GENERATE_CONTRACT] =  1;
        RewardByReason[ReasonType.LD_CREATE_OFFER]      =  2;
        RewardByReason[ReasonType.LD_CANCEL_OFFER]      = -2;
        RewardByReason[ReasonType.BR_CREATE_COLLATERAL] =  3;
        RewardByReason[ReasonType.BR_CANCEL_COLLATERAL] = -3;
        RewardByReason[ReasonType.BR_ONTIME_PAYMENT]    =  1;
        RewardByReason[ReasonType.BR_LATE_PAYMENT]      = -1;
        RewardByReason[ReasonType.BR_ACCEPT_OFFER]      =  1;
        RewardByReason[ReasonType.BR_CONTRACT_COMPLETE] =  5;
        RewardByReason[ReasonType.BR_CONTRACT_DEFAULTED]= -5;
    }

    modifier isNotZeroAddress(address _to) {
        require(_to != address(0), "DFY: Reward pawn reputation to the zero address");
        _;
    }

    modifier onlyEOA(address _to) {
        require(!_to.isContract(), "DFY: Reward pawn reputation to a contract address");
        _;
    }

    modifier onlyContractCaller() {
        require(_contractCaller == _msgSender(), "DFY: Calling Reputation adjustment from a non-contract address");
        _;
    }


    /**
    * @dev Get the address of the host contract
    */
    function getContractCaller() external view returns (address) {
        return _contractCaller;
    }
    
    /**
    * @dev Set the host contract address that only allowed to call functions from this contract
    */
    function setContractCaller(address _caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContractCaller(_caller);
    }

    function _setContractCaller(address _caller) internal {
        require(_caller.isContract(), "DFY: Setting reputation contract caller to a non-contract address");
        _contractCaller = _caller;
    }

    /**
    * @dev Get the reputation score of an account
    */
    function getReputationScore(address _address) view external returns(uint32) {
        return _reputationScore[_address];
    }


    /**
    * @dev Return the absolute value of a signed integer
    * @param _input is any signed integer
    * @return an unsigned integer that is the absolute value of _input
    */
    function abs(int256 _input) internal pure returns (uint256) {
        return _input >= 0 ? uint256(_input) : uint256(_input * -1);
    }

    /**
    * @dev Adjust reputation score base on the input reason
    * @param _user is the address of the user whose reputation score is being adjusted.
    * @param _reasonType is the reason of the adjustment.
    */
    function adjustReputationScore(
        address _user, 
        ReasonType _reasonType) 
        external whenNotPaused isNotZeroAddress(_user) onlyEOA(_user) onlyContractCaller
    {
        int8 pointsByReason     = RewardByReason[_reasonType];
        uint256 points          = abs(pointsByReason);

        // Check if the points mapped by _reasonType is greater than 0 or not
        if(pointsByReason >= 0) {
            // If pointsByReason is greater than 0, reward points to the user.
            _rewardReputationScore(_user, points, _reasonType);
        }
        else {
            // If pointByReason is lesser than 0, substract the points from user's current score.
            _reduceReputationScore(_user, points, _reasonType);
        }
    }
    
    /** 
    * @dev Reward Reputation score to a user
    * @param _to is the address whose reputation score is going to be adjusted
    * @param _points is the points will be added to _to's reputation score (unsigned integer)
    * @param _reasonType is the reason of score adjustment
    */    
    function _rewardReputationScore(
        address _to, 
        uint256 _points, 
        ReasonType _reasonType) 
        internal
    {
        uint256 currentScore = uint256(_reputationScore[_to]);
        _reputationScore[_to] = currentScore.add(_points).toUint32();

        emit ReputationPointRewarded(_to, _points, _reasonType);
    }

    /** 
    * @dev Reduce Reputation score of a user.
    * @param _from is the address whose reputation score is going to be adjusted
    * @param _points is the points will be subtracted from _from's reputation score (unsigned integer)
    * @param _reasonType is the reason of score adjustment
    */  
    function _reduceReputationScore(
        address _from, 
        uint256 _points, 
        ReasonType _reasonType) 
        internal 
    {
        uint256 currentScore = uint256(_reputationScore[_from]);
        
        (bool success, uint result) = currentScore.trySub(_points);
        
        // if the current reputation score is lesser than the reducing points, 
        // set reputation score to 0
        _reputationScore[_from] = success == true ? result.toUint32() : 0;

        emit ReputationPointReduced(_from, _points, _reasonType);
    }
}