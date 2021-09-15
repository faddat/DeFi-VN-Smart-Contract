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
        uint256 nftTokenId;
        address nftCollection;
        uint256 loanAmount;
        address loanAsset;
        uint256 nftTokenQuantity;
        uint256 expectedDurationQty;
        LoanDurationType expectedDurationType;
        CollateralStatus status;
    }

    /**
    * @dev create collateral function, collateral will be stored in this contract
    * @param _nftTokenId is token id of NFT
    * @param _loanAmount is amount collateral
    * @param _loanAsset is address of loan token
    * @param _expectedDurationQty is expected duration
    * @param _durationType is expected duration type
    */

    function createCollateral(
        address _collection,
        uint256 _nftTokenId, 
        uint256 _loanAmount,
        address _loanAsset,
        uint256 _nftTokenQuantity,
        uint256 _expectedDurationQty,
        LoanDurationType _durationType) 
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
        uint256 loanToValue;
        uint256 loanAmount;
        uint256 interest;
        uint256 duration;
        OfferStatus status;
        LoanDurationType loanDrationType;
        LoanDurationType repaymentCycleType;
        uint256 liquidityThreshold;
        bool isInit;
    }

    /**
    * @dev create offer to collateral
    * @param _nftCollateralId is id collateral
    * @param _repaymentAsset is address token repayment
    * @param _loanToValue is value collateral of loan
    * @param _repaymentAsset is token repayment
    */

    function createOffer(
        uint256 _nftCollateralId,
        address _repaymentAsset,
        uint256 _loanToValue,
        uint256 _loanAmount,
        uint256 _interest,
        uint256 _duration,
        uint256 _liquidityThreshold,
        LoanDurationType _loanDurationType,
        LoanDurationType _repaymentCycleType
    ) external;

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
       // int256 pawnShopPackageId; //bỏ trường này
        ContractTerms terms;
        ContractStatus status;
        uint8 lateCount;
    }

    function acceptOffer(
        uint256 _nftCollateralId, 
        uint256 _offerId
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