// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IPawnNFT {

    /** ========================= Collateral ============================= */
    
    // Enum 
    enum LoanDurationType {WEEK, MONTH}
    enum CollateralStatus {OPEN, DOING, COMPLETED, CANCEL}
    enum OfferStatus {PENDING, ACCEPTED, COMPLETED, CANCEL}
    enum ContractStatus {ACTIVE, COMPLETED, DEFAULT}
    enum PaymentRequestStatusEnum {ACTIVE, LATE, COMPLETE, DEFAULT}
    enum PaymentRequestTypeEnum {INTEREST, OVERDUE, LOAN}
    enum ContractLiquidedReasonType { LATE, RISK, UNPAID }

    struct Collateral {
        address owner;
        address nftContract;
        uint256 nftTokenId;
        uint256 loanAmount;
        address loanAsset;
        uint256 nftTokenQuantity;
        uint256 expectedDurationQty;
        LoanDurationType durationType;
        CollateralStatus status;
    }

    /**
    * @dev create collateral function, collateral will be stored in this contract
    * @param _nftContract is address NFT token collection
    * @param _nftTokenId is token id of NFT
    * @param _loanAmount is amount collateral
    * @param _loanAsset is address of loan token
    * @param _nftTokenQuantity is quantity NFT token
    * @param _expectedDurationQty is expected duration
    * @param _durationType is expected duration type
    * @param _UID is UID pass create collateral to event collateral
    */

    function createCollateral(
        address _nftContract,
        uint256 _nftTokenId,
        uint256 _loanAmount,
        address _loanAsset,
        uint256 _nftTokenQuantity,
        uint256 _expectedDurationQty,
        LoanDurationType _durationType,
        uint256 _UID
    ) 
    external;

    /**
    * @dev withdrawCollateral function, collateral will be delete stored in contract
    * @param _nftCollateralId is id of collateral
    */
    function withdrawCollateral(
        uint256 _nftCollateralId
    ) external;

    /** ========================= OFFER ============================= */

    struct CollateralOfferList {
        //offerId => Offer
        mapping (uint256 => Offer) offerMapping;
        uint256[] offerIdList;
        bool isInit;
    }

    struct Offer {
        address owner;
        address repaymentAsset;
        uint256 loanAmount;
        uint256 interest;
        uint256 duration;
        OfferStatus status;
        LoanDurationType loanDurationType;
        LoanDurationType repaymentCycleType;
        uint256 liquidityThreshold;
    }

    /**
    * @dev create offer to collateral
    * @param _nftCollateralId is id collateral
    * @param _repaymentAsset is address token repayment
    * @param _loanAmount is amount token of loan
    * @param _interest is interest of loan
    * @param _duration is duration of loan
    * @param _liquidityThreshold is liquidity threshold of loan
    * @param _loanDurationType is duration type of loan 
    * @param _repaymentCycleType is repayment type of loan 
    */

    function createOffer(
        uint256 _nftCollateralId,
        address _repaymentAsset,
        uint256 _loanAmount,
        uint256 _interest,
        uint256 _duration,
        uint256 _liquidityThreshold,
        LoanDurationType _loanDurationType,
        LoanDurationType _repaymentCycleType,
        uint256 _UID
    ) external;

    /**
    * @dev cancel offer
    * @param _offerId is id offer
    * @param _nftCollateralId is id NFT collateral
    */
    function cancelOffer(
        uint256 _offerId,
        uint256 _nftCollateralId
    ) external;

    /** ========================= ACCEPT OFFER ============================= */
    
    struct ContractTerms {
        address borrower;
        address lender;
        uint256 nftTokenId;
        address nftCollateralAsset;
        uint256 nftCollateralAmount;
        address loanAsset;
        uint256 loanAmount;
        address repaymentAsset;
        uint256 interest;
        LoanDurationType repaymentCycleType;
        uint256 liquidityThreshold;
        uint256 contractStartDate;
        uint256 contractEndDate;
        uint256 lateThreshold;
        uint256 systemFeeRate;
        uint256 penaltyRate;
        uint256 prepaidFeeRate;
    }
    
    struct Contract {
        uint256 nftCollateralId;
        int256 offerId;
        ContractTerms terms;
        ContractStatus status;
        uint8 lateCount;
    }

    function acceptOffer(
        uint256 _nftCollateralId, 
        uint256 _offerId,
        uint256 _UID
    ) external;


    /** ========================= REPAYMENT ============================= */
    

    struct PaymentRequest {
        uint256 requestId;
        PaymentRequestTypeEnum paymentRequestType;
        uint256 remainingLoan;
        uint256 penalty;
        uint256 interest;
        uint256 remainingPenalty;
        uint256 remainingInterest;
        uint256 dueDateTimestamp;
        bool chargePrepaidFee;
        PaymentRequestStatusEnum status;
    }

    /**
    * @dev End lend period settlement and generate invoice for next period
    * @param _contractId is id contract
    * @param _remainingLoan is remaining Loan of borrower
    * @param _nextPhrasePenalty is next Phrase Penalty
    * @param _nextPhraseInterest is token next Phrase Interest
    * @param _dueDateTimestamp is due DateTimestamp
    * @param _paymentRequestType is type of payment request
    * @param _chargePrepaidFee is charge Prepaid Fee
    */
    function closePaymentRequestAndStartNew(
        uint256 _contractId,
        uint256 _remainingLoan,
        uint256 _nextPhrasePenalty,
        uint256 _nextPhraseInterest,
        uint256 _dueDateTimestamp,
        PaymentRequestTypeEnum _paymentRequestType,
        bool _chargePrepaidFee
    ) external;

    /**
    * @dev Borrowers make repayments
    * @param _contractId is id contract
    * @param _paidPenaltyAmount is paid Penalty Amount 
    * @param _paidInterestAmount is paid Interest Amount
    * @param _paidLoanAmount is paidLoanAmount
    */
    function repayment(
        uint256 _contractId,
        uint256 _paidPenaltyAmount,
        uint256 _paidInterestAmount,
        uint256 _paidLoanAmount
    ) external;

    function collateralRiskLiquidationExecution(
        uint256 _contractId,
        uint256 _collateralPerRepaymentTokenExchangeRate,
        uint256 _collateralPerLoanAssetExchangeRate
    ) external;

    function lateLiquidationExecution(
        uint256 _contractId
    ) external;

    function notPaidFullAtEndContractLiquidation(
        uint256 _contractId
    ) external;
}