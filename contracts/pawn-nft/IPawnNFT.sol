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
    * @param _collection is address NFT token collection
    * @param _nftTokenId is token id of NFT
    * @param _loanAmount is amount collateral
    * @param _loanAsset is address of loan token
    * @param _nftTokenQuantity is quantity NFT token
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
        uint256 _loanToValue,
        uint256 _loanAmount,
        uint256 _interest,
        uint256 _duration,
        uint256 _liquidityThreshold,
        LoanDurationType _loanDurationType,
        LoanDurationType _repaymentCycleType
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
        int256 pawnShopPackageId;
        ContractTerms terms;
        ContractStatus status;
        uint8 lateCount;
    }

    function acceptOffer(
        uint256 _nftCollateralId, 
        uint256 _offerId
    ) external;


    /** ========================= REPAYMENT ============================= */
    
    /**
    * @dev close payment request and start new payment request 
    * @param _contractId is id collateral
    * @param _remainingLoan is address token repayment
    */ 

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

    function closePaymentRequestAndStartNew(
        uint256 _contractId,
        uint256 _remainingLoan,
        uint256 _nextPhrasePenalty,
        uint256 _nextPhraseInterest,
        uint256 _dueDateTimestamp,
        PaymentRequestTypeEnum _paymentRequestType,
        bool _chargePrepaidFee
    ) external;

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