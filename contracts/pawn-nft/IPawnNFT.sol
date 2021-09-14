// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IPawnNFT {

    enum CollateralStatus {ON_PAWN_MARKET, IN_PAWN_CONTRACT}
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

    function createCollateral(
        uint256 _tokenId, 
        address _currency, 
        uint256 _amount,
        address _loanAsset,
        uint256 _duration,
        LoanDurationType _durationType) 
    external;

    function withdrawCollateral(
        uint256 _collateralId
    ) external;
}