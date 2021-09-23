// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IReputation {
    
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
        BR_CONTRACT_DEFAULTED,
        
        LD_REVIEWED_BY_BORROWER,
        LD_KYC,

        BR_REVIEWED_BY_LENDER,
        BR_KYC
    }
    
    /**
    * @dev Get the reputation score of an account
    */
    function getReputationScore(address _address) external view returns(uint32);

    function adjustReputationScore(address _user, ReasonType _reasonType) external;

}
