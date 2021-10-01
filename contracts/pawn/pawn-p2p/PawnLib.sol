// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum LoanDurationType {WEEK, MONTH}
enum CollateralStatus {OPEN, DOING, COMPLETED, CANCEL}
struct Collateral {
    address owner;
    uint256 amount;
    address collateralAddress;
    address loanAsset;
    uint256 expectedDurationQty;
    LoanDurationType expectedDurationType;
    CollateralStatus status;
}

enum OfferStatus {PENDING, ACCEPTED, COMPLETED, CANCEL}
struct CollateralOfferList {
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
    bool isInit;
}

enum PawnShopPackageStatus {ACTIVE, INACTIVE}
enum PawnShopPackageType {AUTO, SEMI_AUTO}
struct Range {
    uint256 lowerBound;
    uint256 upperBound;
}

struct PawnShopPackage {
    address owner;
    PawnShopPackageStatus status;
    PawnShopPackageType packageType;
    address loanToken;
    Range loanAmountRange;
    address[] collateralAcceptance;
    uint256 interest;
    uint256 durationType;
    Range durationRange;
    address repaymentAsset;
    LoanDurationType repaymentCycleType;
    uint256 loanToValue;
    uint256 loanToValueLiquidationThreshold;
}

enum LoanRequestStatus {PENDING, ACCEPTED, REJECTED, CONTRACTED, CANCEL}
struct LoanRequestStatusStruct {
    bool isInit;
    LoanRequestStatus status;
}
struct CollateralAsLoanRequestListStruct {
    mapping (uint256 => LoanRequestStatusStruct) loanRequestToPawnShopPackageMapping; // Mapping from package to status
    uint256[] pawnShopPackageIdList;
    bool isInit;
}

enum ContractStatus {ACTIVE, COMPLETED, DEFAULT}
struct ContractTerms {
    address borrower;
    address lender;
    address collateralAsset;
    uint256 collateralAmount;
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
    uint256 collateralId;
    int256 offerId;
    int256 pawnShopPackageId;
    ContractTerms terms;
    ContractStatus status;
    uint8 lateCount;
}

enum PaymentRequestStatusEnum {ACTIVE, LATE, COMPLETE, DEFAULT}
enum PaymentRequestTypeEnum {INTEREST, OVERDUE, LOAN}
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

enum ContractLiquidedReasonType { LATE, RISK, UNPAID }


library PawnLib {
    using SafeERC20 for IERC20;
    
    function safeTransfer(address asset, address from, address to, uint256 amount) internal {
        if (asset == address(0)) {
            require(from.balance >= amount, 'balance');
            // Handle BNB            
            if (to == address(this)) {
                // Send to this contract
            } else if (from == address(this)) {
                // Send from this contract
                (bool success, ) = to.call{value:amount}('');
                require(success, 'fail-trans-bnb');
            } else {
                // Send from other address to another address
                require(false, 'not-allow-transfer');
            }
        } else {
            // Handle ERC20
            uint256 prebalance = IERC20(asset).balanceOf(to);
            require(IERC20(asset).balanceOf(from) >= amount, 'not-enough-balance');
            if (from == address(this)) {
                // transfer direct to to
                IERC20(asset).safeTransfer(to, amount);
            } else {
                require(IERC20(asset).allowance(from, address(this)) >= amount, 'not-allowance');
                IERC20(asset).safeTransferFrom(from, to, amount);
            }
            require(IERC20(asset).balanceOf(to) - amount == prebalance, 'not-trans-enough');
        }
    }

    function calculateAmount(address _token, address from) 
    internal view returns (uint256 _amount) {
        if (_token == address(0)) {
            // BNB
            _amount = from.balance;
        } else {
            // ERC20
            _amount = IERC20(_token).balanceOf(from);
        }
    }

    function calculateSystemFee(
        uint256 amount, 
        uint256 feeRate,
        uint256 zoom
    ) internal pure returns (uint256 feeAmount) {
        feeAmount = (amount * feeRate) / (zoom * 100);
    }

    function calculateContractDuration(LoanDurationType durationType, uint256 duration)
    internal pure
    returns (uint256 inSeconds)
    {
        if (durationType == LoanDurationType.WEEK) {
            inSeconds = 7 * 24 * 3600 * duration;
        } else {
            inSeconds = 30 * 24 * 3600 * duration;
        }
    }
}