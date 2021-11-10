// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// Will be replaced by DFY-AccessControl when it's merged or later phases.
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IReputation.sol";


contract Reputation is 
    IReputation, 
    UUPSUpgradeable, 
    PausableUpgradeable, 
    AccessControlUpgradeable {

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

    mapping(ReasonType => int8) _rewardByReason;

    mapping(address => bool) whitelistedContractCaller;

    event ReputationPointRewarded(address _user, uint256 _points, ReasonType _reasonType);
    event ReputationPointReduced(address _user, uint256 _points, ReasonType _reasonType);
    
    function initialize() public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);

        //initialize Reward by Reason mapping values.
        _initializeRewardByReason();
    }

    // Reason for Reputation point adjustment
    /**
    * @dev Reputation points in correspondence with ReasonType 
    * LD_CREATE_PACKAGE         : +3    (0)
    * LD_CANCEL_PACKAGE         : -3    (1)
    * LD_REOPEN_PACKAGE         : +3    (2)
    * LD_GENERATE_CONTRACT      : +1    (3)
    * LD_CREATE_OFFER           : +2    (4)
    * LD_CANCEL_OFFER           : -2    (5)
    * LD_ACCEPT_OFFER           : +1    (6)
    * BR_CREATE_COLLATERAL      : +3    (7)
    * BR_CANCEL_COLLATERAL      : -3    (8)
    * BR_ONTIME_PAYMENT         : +1    (9)
    * BR_LATE_PAYMENT           : -1    (10)
    * BR_ACCEPT_OFFER           : +1    (11)
    * BR_CONTRACT_COMPLETE      : +5    (12)
    * BR_CONTRACT_DEFAULTED     : -5    (13)
    * LD_REVIEWED_BY_BORROWER_1 : +1    (14)
    * LD_REVIEWED_BY_BORROWER_2 : +2    (15)
    * LD_REVIEWED_BY_BORROWER_3 : +3    (16)
    * LD_REVIEWED_BY_BORROWER_4 : +4    (17)
    * LD_REVIEWED_BY_BORROWER_5 : +5    (18)
    * LD_KYC                    : +5    (19)
    * BR_REVIEWED_BY_LENDER_1   : +1    (20)
    * BR_REVIEWED_BY_LENDER_2   : +2    (21)
    * BR_REVIEWED_BY_LENDER_3   : +3    (22)
    * BR_REVIEWED_BY_LENDER_4   : +4    (23)
    * BR_REVIEWED_BY_LENDER_5   : +5    (24)
    * BR_KYC                    : +5    (25)
    */
    function _initializeRewardByReason() internal virtual {
        _rewardByReason[ReasonType.LD_CREATE_PACKAGE]    =  3;  // index: 0
        _rewardByReason[ReasonType.LD_CANCEL_PACKAGE]    = -3;  // index: 1
        _rewardByReason[ReasonType.LD_REOPEN_PACKAGE]    =  3;  // index: 2
        _rewardByReason[ReasonType.LD_GENERATE_CONTRACT] =  1;  // index: 3
        _rewardByReason[ReasonType.LD_CREATE_OFFER]      =  2;  // index: 4
        _rewardByReason[ReasonType.LD_CANCEL_OFFER]      = -2;  // index: 5
        _rewardByReason[ReasonType.LD_ACCEPT_OFFER]      =  1;  // index: 6
        _rewardByReason[ReasonType.BR_CREATE_COLLATERAL] =  3;  // index: 7
        _rewardByReason[ReasonType.BR_CANCEL_COLLATERAL] = -3;  // index: 8
        _rewardByReason[ReasonType.BR_ONTIME_PAYMENT]    =  1;  // index: 9
        _rewardByReason[ReasonType.BR_LATE_PAYMENT]      = -1;  // index: 10
        _rewardByReason[ReasonType.BR_ACCEPT_OFFER]      =  1;  // index: 11
        _rewardByReason[ReasonType.BR_CONTRACT_COMPLETE] =  5;  // index: 12
        _rewardByReason[ReasonType.BR_CONTRACT_DEFAULTED]= -5;  // index: 13
    }

    function initializeRewardByReason() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _initializeRewardByReason();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function version() public virtual pure returns (string memory) {
        return "1.0.2";
    }

    modifier isNotZeroAddress(address _to) {
        require(_to != address(0), "DFY: Reward pawn reputation to the zero address");
        _;
    }

    modifier onlyEOA(address _to) {
        require(!_to.isContract(), "DFY: Reward pawn reputation to a contract address");
        _;
    }

    modifier onlyWhitelistedContractCaller(address _from) {
        // Caller must be a contract
        require(_from.isContract(), "DFY: Calling Reputation adjustment from a non-contract address");

        // Caller must be whitelisted
        require(whitelistedContractCaller[_from] == true, "DFY: Caller is not allowed");
        _;
    }

    /** 
    * @dev Add a contract address that use Reputation to whitelist
    * @param _caller is the contract address being whitelisted=
    */
    function addWhitelistedContractCaller(address _caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_caller.isContract(), "DFY: Setting reputation contract caller to a non-contract address");
        whitelistedContractCaller[_caller] = true;
    }

    /** 
    * @dev remove a contract address from whitelist
    * @param _caller is the contract address being removed
    */
    function removeWhitelistedContractCaller(address _caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete whitelistedContractCaller[_caller];
    }

    /** 
    * @dev check if an address is whitelisted
    * @param _contract is the address being verified
    */
    function isWhitelistedContractCaller(address _contract) external view returns (bool) {
        return whitelistedContractCaller[_contract];
    }

    /**
    * @dev Get the reputation score of an account
    */
    function getReputationScore(address _address) external virtual override view returns(uint32) {
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
        external override
        whenNotPaused isNotZeroAddress(_user) onlyEOA(_user) onlyWhitelistedContractCaller(_msgSender())
    {
        int8 pointsByReason     = _rewardByReason[_reasonType];
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