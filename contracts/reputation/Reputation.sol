// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Will be replaced by DFY-AccessControl when it's merged.
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
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
    mapping (address => uint32) public _reputationScore;

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

    event ReputationPointRewarded(address _user, uint256 _points, ReasonType _reasonType);
    event ReputationPointReduced(address _user, uint256 _points, ReasonType _reasonType);
    
    function initialize() public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
    }

    modifier isNotZeroAddress(address _to) {
        require(_to != address(0), "DFY: Reward pawn reputation to the zero address");
        _;
    }

    modifier onlyEOA(address _to) {
        require(!_to.isContract(), "DFY: Reward pawn reputation to a contract address");
        _;
    }
    
    /** 
    * @dev Reward Reputation score to a user
    * @param _to is the address whose reputation score is going to be adjusted
    * @param _points is the points will be added to _to's reputation score (unsigned integer)
    * @param _reasonType is the reason of score adjustment
    */    
    function rewardReputationScore(
        address _to, 
        uint256 _points, 
        ReasonType _reasonType) 
        external whenNotPaused isNotZeroAddress(_to) onlyEOA(_to) 
    {
        uint256 currentScore = uint256(_reputationScore[_to]);
        currentScore = currentScore.add(_points);
        _reputationScore[_to] = currentScore.toUint32();

        emit ReputationPointRewarded(_to, _points, _reasonType);
    }

    /** 
    * @dev Reduce Reputation score of a user.
    * @param _from is the address whose reputation score is going to be adjusted
    * @param _points is the points will be subtracted from _from's reputation score (unsigned integer)
    * @param _reasonType is the reason of score adjustment
    */  
    function reduceReputationScore(
        address _from, 
        uint256 _points, 
        ReasonType _reasonType) 
        external whenNotPaused isNotZeroAddress(_from) onlyEOA(_from) 
    {
        uint256 currentScore = uint256(_reputationScore[_from]);
        
        (bool flag, uint result) = currentScore.trySub(_points);
        
        // if the current reputation score is lesser than the reducing points, 
        // set reputation score to 0
        _reputationScore[_from] = flag == true ? result.toUint32() : 0;

        emit ReputationPointReduced(_from, _points, _reasonType);
    }
}