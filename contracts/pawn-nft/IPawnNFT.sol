// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IPawnNFT {

    /** === Collateral === */

    // Enum status collateral
    enum CollateralStatus {ON_PAWN_MARKET, IN_PAWN_CONTRACT}

    // Enum tyoe loan duration
    enum LoanDurationType {WEEK, MONTH}

    struct Collateral {
        address owner;
        uint256 tokenId;
        uint256 loanAmount;
        address loanAsset;
        uint256 expectedDurationQty;
        LoanDurationType expectedDurationType;
        CollateralStatus status;
    }

    /**
    * @dev create collateral function, collateral will be stored in this contract
    * @param _tokenId is token id of NFT
    * @param _amount is amount collateral
    * @param _loanAsset is address of loan token
    * @param _duration is expected duration
    * @param _durationType is expected duration type
    */
    function createCollateral(
        uint256 _tokenId, 
        uint256 _amount,
        address _loanAsset,
        uint256 _duration,
        LoanDurationType _durationType) 
    external;

    /**
    * @dev withdrawCollateral function, collateral will be delete stored in contract
    * @param _collateralId is id of collateral
    */
    function withdrawCollateral(
        uint256 _collateralId
    ) external;

    /** === offer === */
    
    // Enum status offer
    enum OfferStatus {OPEN, ACCEPTED, REJECTED, CANCELLED}

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
    * @param _collateralId is id collateral
    * @param _repaymentAsset is address token repayment
    * @param _loanToValue is value collateral of loan
    * @param _repaymentAsset is token repayment
    */
    function createOffer(
        uint256 _collateralId,
        address _repaymentAsset,
        uint256 _loanToValue,
        uint256 _loanAmount,
        uint256 _interest,
        uint256 _duration,
        uint256 _liquidityThreshold,
        LoanDurationType _loanDurationType,
        LoanDurationType _repaymentCycleType,
    ) external;

    function cancelOffer(
        uint256 _offerId,
        uint256 _collateralId,
    ) external;
}