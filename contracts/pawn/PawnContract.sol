// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract PawnContract is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    mapping (address => uint256) whitelistCollateral;
    address public operator; 
    uint256 public penaltyRate;
    uint256 public systemFeeRate; 
    uint256 public lateThreshold;
    uint256 public prepaidFeeRate;
    uint256 public ZOOM;  
    bool public initialized = false;
    address public admin;
    enum RepaymentCycleType {WEEK, MONTH}
    enum LoanDurationType {WEEK, MONTH}

    /**
     * @dev initialize function
     * @param _zoom is coefficient used to represent risk params
     */

    function initialize(uint256 _zoom
    ) external notInitialized {
        ZOOM = _zoom;
        initialized = true;
    }

    function setOperator(address _newOperator) onlyAdmin external {
        operator = _newOperator;
    }

    function pause() onlyOperator external {
        _pause();
    }

    function unPause() onlyOperator external {
        _unpause();
    }

    /**
    * @dev set fee for each token
    * @param _feeRate is percentage of tokens to pay for the transaction
    */

    function setSystemFeeRate(uint256 _feeRate) external onlyAdmin {
        systemFeeRate = _feeRate;
    }

    /**
    * @dev set fee for each token
    * @param _feeRate is percentage of tokens to pay for the penalty
    */
    function setPenaltyRate(uint256 _feeRate) external onlyAdmin {
        penaltyRate = _feeRate;
    }

    /**
    * @dev set fee for each token
    * @param _threshold is number of time allowed for late repayment
    */
    function setLateThreshold(uint256 _threshold) external onlyAdmin {
        lateThreshold = _threshold;
    }

    function setPrepaidFeeRate(uint256 _feeRate) external onlyAdmin {
        prepaidFeeRate = _feeRate;
    }

    function setWhitelistCollateral(address _token, uint256 _status) external onlyOperator{
        whitelistCollateral[_token] = _status;
    }

    modifier notInitialized() {
        require(!initialized, "initialized");
        _;
    }

    modifier isInitialized() {
        require(initialized, "not-initialized");
        _;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "caller is not the operator");
        _;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "caller is not the admin");
        _;
    }

    function emergencyWithdraw(address _token)
    external onlyAdmin
    whenPaused {
        if (_token == address (0)) {
            payable(address(this)).transfer(address(this).balance);
        } else {
            IERC20(_token).transfer(address(this), IERC20(_token).balanceOf(address(this)));
        }
    }

    /** ========================= COLLATERAL FUNCTIONS & STATES ============================= */
    uint256 public numberCollaterals;
    mapping (uint256 => Collateral) public collaterals;
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

    event CreateCollateralEvent(
        uint256 collateralId,
        Collateral data
    );

    event WithdrawCollateralEvent(
        uint256 collateralId,
        address collateralOwner
    );

    /**
    * @dev create Collateral function, collateral will be stored in this contract
    * @param _collateralAddress is address of collateral
    * @param _packageId is id of pawn shop package
    * @param _amount is amount of token
    * @param _loanAsset is address of loan token
    * @param _expectedDurationQty is expected duration
    * @param _expectedDurationType is expected duration type
    */
    function createCollateral(
        address _collateralAddress,
        int256 _packageId,
        uint256 _amount,
        address _loanAsset,
        uint256 _expectedDurationQty,
        LoanDurationType _expectedDurationType
    ) external whenNotPaused payable
    returns (uint256 _idx)
    {
        //check whitelist collateral token
        require(whitelistCollateral[_collateralAddress] == 1, 'not-support-collateral');

        if (_collateralAddress != address(0)) {
            // transfer to this contract
            uint256 preCollateralBalance = ERC20(_collateralAddress).balanceOf(address(this));
            require(ERC20(_collateralAddress).balanceOf(address(this)) - preCollateralBalance == _amount, 'not-enough-collateral');
            ERC20(_collateralAddress).safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            _amount = msg.value;
        }
        //id of collateral
        _idx = numberCollaterals;

        //create new collateral
        Collateral storage newCollateral = collaterals[_idx];
        newCollateral.owner = msg.sender;
        newCollateral.amount = _amount;
        newCollateral.collateralAddress = _collateralAddress;
        newCollateral.loanAsset = _loanAsset;
        newCollateral.status = CollateralStatus.OPEN;
        newCollateral.expectedDurationQty = _expectedDurationQty;
        newCollateral.expectedDurationType = _expectedDurationType;

        ++numberCollaterals;

        emit CreateCollateralEvent(_idx, newCollateral);

        if (_packageId >= 0) {
            //package must active
            PawnShopPackage storage pawnShopPackage = pawnShopPackages[uint256(_packageId)];
            require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'package-not-support');

            _submitCollateralToPackage(_idx, uint256(_packageId));
            emit SubmitPawnShopPackage(uint256(_packageId), _idx, LoanRequestStatus.PENDING);
        }
    }

    /**
    * @dev cancel collateral function and return back collateral
    * @param  _collateralId is id of collateral
    */
    function withdrawCollateral(uint256 _collateralId) external {
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.owner == msg.sender, 'not-owner-of-this-collateral');
        require(collateral.status == CollateralStatus.OPEN, 'collateral-not-open');

        // Remove relation of collateral and offers
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        if (collateralOfferList.isInit == true) {
            for (uint i = 0; i < collateralOfferList.offerIdList.length; i ++) {
                uint256 offerId = collateralOfferList.offerIdList[i];
                Offer storage offer = collateralOfferList.offerMapping[offerId];
                emit CancelOfferEvent(offerId, _collateralId, offer.owner);
            }
            delete collateralOffersMapping[_collateralId];
        }

        if (collateral.collateralAddress != address(0)) {
            // transfer collateral to collateral's owner
            require(ERC20(collateral.collateralAddress).transfer(collateral.owner, collateral.amount), 'transfer-collateral-fail');     // Carefully check for security of this
        } else {
            payable(collateral.owner).transfer(collateral.amount);  // Carefully check for security of this
        }
        delete collaterals[_collateralId];
        emit WithdrawCollateralEvent(_collateralId, msg.sender);
    }

    /** ========================= OFFER FUNCTIONS & STATES ============================= */
    uint256 public numberOffers;
    enum OfferStatus {PENDING, ACCEPTED, COMPLETED, CANCEL}
    struct CollateralOfferList {
        mapping (uint256 => Offer) offerMapping;
        uint256[] offerIdList;
        bool isInit;
    }
    mapping (uint256 => CollateralOfferList) public collateralOffersMapping;
    struct Offer {
        address owner;
        address repaymentAsset;
        uint256 loanAmount;
        uint256 interest;
        uint256 duration;
        OfferStatus status;
        LoanDurationType loanDurationType;
        RepaymentCycleType repaymentCycleType;
        uint256 liquidityThreshold;
        bool isInit;
    }

    event CreateOfferEvent(
        uint256 offerId,
        uint256 collateralId,
        Offer data
    );

    event CancelOfferEvent(
        uint256 offerId,
        uint256 collateralId,
        address offerOwner
    );

    /**
    * @dev create Collateral function, collateral will be stored in this contract
    * @param _collateralId is id of collateral
    * @param _repaymentAsset is address of repayment token
    * @param _duration is duration of this offer
    * @param _loanDurationType is type for calculating loan duration
    * @param _repaymentCycleType is type for calculating repayment cycle
    * @param _liquidityThreshold is ratio of assets to be liquidated
    */

    function createOffer(
        uint256 _collateralId,
        address _repaymentAsset,
        uint256 _loanAmount,
        uint256 _duration,
        uint256 _interest,
        uint256 _loanDurationType,
        uint256 _repaymentCycleType,
        uint256 _liquidityThreshold
    )
    external whenNotPaused
    returns (uint256 _idx)
    {
        Collateral memory collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.OPEN, 'collateral-not-open');
        // validate not allow for collateral owner to create offer
        require(collateral.owner != msg.sender, 'collateral-owner-match-sender');
        // TODO: Validate logic of offer must match with collateral: loan amount, asset, ...
        // TODO: Validate ower already approve for this contract to withdraw

        Offer storage newOffer = _createOffer(
            _collateralId, 
            _repaymentAsset, 
            _loanAmount, 
            _duration, 
            _interest, 
            _loanDurationType, 
            _repaymentCycleType, 
            _liquidityThreshold
        );

        emit CreateOfferEvent(_idx, _collateralId, newOffer);
    }

    function _createOffer(
        uint256 _collateralId,
        address _repaymentAsset,
        uint256 _loanAmount,
        uint256 _duration,
        uint256 _interest,
        uint256 _loanDurationType,
        uint256 _repaymentCycleType,
        uint256 _liquidityThreshold
    ) internal returns (Offer storage _offer) {
        // Get offers of collateral
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        if (!collateralOfferList.isInit) {
            collateralOfferList.isInit = true;
        }
        // Create offer id       
        uint256 _idx = numberOffers;

        // Create offer data
        Offer storage newOffer = collateralOfferList.offerMapping[_idx];
        require (newOffer.isInit == false, 'internal-exception - _createOffer - newOffer.isInit');

        newOffer.isInit = true;
        newOffer.owner = msg.sender;
        newOffer.loanAmount = _loanAmount;
        newOffer.interest = _interest;
        newOffer.duration = _duration;
        newOffer.loanDurationType = LoanDurationType(_loanDurationType);
        newOffer.repaymentAsset = _repaymentAsset;
        newOffer.repaymentCycleType = RepaymentCycleType(_repaymentCycleType);
        newOffer.liquidityThreshold = _liquidityThreshold;
        newOffer.status = OfferStatus.PENDING;

        collateralOfferList.offerIdList.push(_idx);

        ++numberOffers;

        return newOffer;
    }

    /**
    * @dev cancel offer function, used for cancel offer
    * @param  _offerId is id of offer
    * @param _collateralId is id of collateral associated with offer
    */
    function cancelOffer(uint256 _offerId, uint256 _collateralId) 
    external {
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        require(collateralOfferList.isInit == true, 'collateral-not-have-any-offer');
        Offer storage offer = collateralOfferList.offerMapping[_offerId];
        require(offer.isInit == true, 'offer-not-sent-to-collateral');
        require(offer.owner == msg.sender, 'not-owner-of-offer');
        require(offer.status == OfferStatus.PENDING, 'offer-executed');
        _cancelOffer(_offerId, collateralOfferList);
        emit CancelOfferEvent(_offerId, _collateralId, msg.sender);
    }

    function _cancelOffer(
        uint256 _offerId, 
        CollateralOfferList storage _offerList
    ) internal {
        delete _offerList.offerMapping[_offerId];
        for (uint i = 0; i < _offerList.offerIdList.length; i ++) {
            if (_offerList.offerIdList[i] == _offerId) {
                _offerList.offerIdList[i] = _offerList.offerIdList[_offerList.offerIdList.length - 1];
                break;
            }
        }

        delete _offerList.offerIdList[_offerList.offerIdList.length - 1];
    }

    /** ========================= PAWNSHOP PACKAGE FUNCTIONS & STATES ============================= */
    uint256 public numberPawnShopPackages;
    mapping (uint256 => PawnShopPackage) public pawnShopPackages;

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
        RepaymentCycleType repaymentCycleType;
        uint256 loanToValue;
        uint256 loanToValueLiquidationThreshold;
    }

    event CreatePawnShopPackage(
        uint256 packageId,
        PawnShopPackage data
    );

    event ChangeStatusPawnShopPackage(
        uint256 packageId,
        PawnShopPackageStatus status         
    );

    function createPawnShopPackage(
        PawnShopPackageType _packageType,
        address _loanToken,
        Range calldata _loanAmountRange,
        address[] calldata _collateralAcceptance,
        uint256 _interest,
        uint256 _durationType,
        Range calldata _durationRange,
        address _repaymentAsset,
        RepaymentCycleType _repaymentCycleType,
        uint256 _loanToValue,
        uint256 _loanToValueLiquidationThreshold
    ) external whenNotPaused
    returns (uint256 _idx)
    {
        _idx = numberPawnShopPackages;

        // Validataion logic: whitelist collateral, ranges must have upper greater than lower, duration type
        for (uint256 i = 0; i < _collateralAcceptance.length; i++) {
            require(whitelistCollateral[_collateralAcceptance[i]] == 1, 'not-support-collateral');
        }

        require(_loanAmountRange.lowerBound < _loanAmountRange.upperBound, 'loan-range-invalid');
        require(_durationRange.lowerBound < _durationRange.upperBound, 'duration-range-invalid');
        require(_durationType == uint256(LoanDurationType.MONTH) || _durationType == uint256(LoanDurationType.WEEK), 'duration-type-invalid');

        //create new collateral
        PawnShopPackage storage newPackage = pawnShopPackages[_idx];
        newPackage.owner = msg.sender;
        newPackage.status = PawnShopPackageStatus.ACTIVE;
        newPackage.packageType = _packageType;
        newPackage.loanToken = _loanToken;
        newPackage.loanAmountRange = _loanAmountRange;
        newPackage.collateralAcceptance = _collateralAcceptance;
        newPackage.interest = _interest;
        newPackage.durationType = _durationType;
        newPackage.durationRange = _durationRange;
        newPackage.repaymentAsset = _repaymentAsset;
        newPackage.repaymentCycleType = _repaymentCycleType;
        newPackage.loanToValue = _loanToValue;
        newPackage.loanToValueLiquidationThreshold = _loanToValueLiquidationThreshold;

        ++numberPawnShopPackages;
        emit CreatePawnShopPackage(
            _idx, 
            newPackage
        );
    }

    function activePawnShopPackage(uint256 _packageId)
    external whenNotPaused
    {
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.owner == msg.sender, 'not-owner-of-this-package');
        require(pawnShopPackage.status == PawnShopPackageStatus.INACTIVE, 'package-not-inactive');

        pawnShopPackage.status = PawnShopPackageStatus.ACTIVE;
        emit ChangeStatusPawnShopPackage(_packageId, PawnShopPackageStatus.ACTIVE);
    }

    function deactivePawnShopPackage(uint256 _packageId)
    external
    {
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.owner == msg.sender, 'not-owner-of-this-package');
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'package-not-active');

        pawnShopPackage.status = PawnShopPackageStatus.INACTIVE;
        emit ChangeStatusPawnShopPackage(_packageId, PawnShopPackageStatus.INACTIVE);
    }

    /** ========================= SUBMIT & ACCEPT WORKFLOW OF PAWNSHOP PACKAGE FUNCTIONS & STATES ============================= */
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
    mapping (uint256 => CollateralAsLoanRequestListStruct) collateralAsLoanRequestMapping; // Map from collateral to loan request
    event SubmitPawnShopPackage(
        uint256 packageId,
        uint256 collateralId,
        LoanRequestStatus status
    );

    /**
    * @dev Submit Collateral to Package function, collateral will be submit to pawnshop package
    * @param _collateralId is id of collateral
    * @param _packageId is id of pawn shop package
    */
    function submitCollateralToPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) external whenNotPaused
    {
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.owner == msg.sender, 'not-owner-of-collateral');
        require(collateral.status == CollateralStatus.OPEN, 'collateral-not-open');
        
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'package-not-open');

        // VALIDATE HAVEN'T SUBMIT TO PACKAGE YET
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        if (loanRequestListStruct.isInit == true) {
            LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
            require(statusStruct.isInit == false, 'already-submit-to-package');
        }

        // Save
        _submitCollateralToPackage(_collateralId, _packageId);
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.PENDING);
    }

    function _submitCollateralToPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) internal {
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        if (!loanRequestListStruct.isInit) {
            loanRequestListStruct.isInit = true;
        }
        LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(statusStruct.isInit == false, 'internal-exception:_submitCollateralToPackage - statusStruct.isInit');
        statusStruct.isInit = true;
        statusStruct.status = LoanRequestStatus.PENDING;
        loanRequestListStruct.pawnShopPackageIdList.push(_packageId);
    }

    function withdrawCollateralFromPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) external whenNotPaused {
        //TODO: VALIDATE
        _removeCollateralFromPackage(_collateralId, _packageId);
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.CANCEL);
    }

    function _removeCollateralFromPackage (
        uint256 _collateralId,
        uint256 _packageId
    ) internal {
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(loanRequestListStruct.isInit == true, 'Internal Exception - loanRequestListStruct');
        require(loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId].isInit == true, 'Internal Exception - statusStruct');
        delete loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];

        for (uint i = 0; i < loanRequestListStruct.pawnShopPackageIdList.length - 1; i++){
            if (loanRequestListStruct.pawnShopPackageIdList[i] == _packageId) {
                loanRequestListStruct.pawnShopPackageIdList[i] = loanRequestListStruct.pawnShopPackageIdList[loanRequestListStruct.pawnShopPackageIdList.length - 1];
                break;
            }
        }
        delete loanRequestListStruct.pawnShopPackageIdList[loanRequestListStruct.pawnShopPackageIdList.length - 1];
    }

    function acceptCollateralOfPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) external whenNotPaused
    {
        // Check for owner of packageId
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.owner == msg.sender, 'not-owner-of-this-package');
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'package-not-inactive');        
        // Check for collateral status is open
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.OPEN, 'collateral-not-open');
        // Check for collateral-package status is PENDING (waiting for accept)
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(loanRequestListStruct.isInit == true, 'collateral-havent-had-any-loan-request');
        LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(statusStruct.isInit == true, 'collateral-havent-had-loan-request-for-this-package');
        require(statusStruct.status == LoanRequestStatus.PENDING, 'collateral-loan-request-for-this-package-not-PENDING');

        // Execute accept => change status of loan request to ACCEPTED, wait for system to generate contract
        _acceptCollateralOfPackage(_collateralId, _packageId);
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.ACCEPTED);
    }

    function _acceptCollateralOfPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) internal {
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(loanRequestListStruct.isInit == true, 'Internal Exception - _acceptCollateralOfPackage - loanRequestListStruct.isInit');
        LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(statusStruct.isInit == true, 'Internal Exception - _acceptCollateralOfPackage - statusStruct.isInit');

        // Update status of loan request between _collateralId and _packageId to Accepted
        statusStruct.status = LoanRequestStatus.ACCEPTED;

        // Remove status of loan request between _collateralId and other packageId then emit event Cancel
        for (uint i = 0; i < loanRequestListStruct.pawnShopPackageIdList.length - 1; i++) {
            uint256 packageId = loanRequestListStruct.pawnShopPackageIdList[i];
            if (packageId != _packageId) {
                // Remove status
                delete loanRequestListStruct.loanRequestToPawnShopPackageMapping[packageId];
                emit SubmitPawnShopPackage(packageId, _collateralId, LoanRequestStatus.CANCEL);
            }
        }
        delete loanRequestListStruct.pawnShopPackageIdList;
        loanRequestListStruct.pawnShopPackageIdList.push(_packageId);

        // Remove relation of collateral and offers
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        if (collateralOfferList.isInit == true) {
            for (uint i = 0; i < collateralOfferList.offerIdList.length; i ++) {
                uint256 offerId = collateralOfferList.offerIdList[i];
                Offer storage offer = collateralOfferList.offerMapping[offerId];
                emit CancelOfferEvent(offerId, _collateralId, offer.owner);
            }
            delete collateralOffersMapping[_collateralId];
        }
    }

    function rejectCollateralOfPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) external whenNotPaused
    {
        // Check for owner of packageId
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.owner == msg.sender, 'not-owner-of-this-package');
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'package-not-inactive');        
        // Check for collateral status is open
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.OPEN, 'collateral-not-open');
        // Check for collateral-package status is PENDING (waiting for accept)
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(loanRequestListStruct.isInit == true, 'collateral-havent-had-any-loan-request');
        LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(statusStruct.isInit == true, 'collateral-havent-had-loan-request-for-this-package');
        require(statusStruct.status == LoanRequestStatus.PENDING, 'collateral-loan-request-for-this-package-not-PENDING');
        
        _removeCollateralFromPackage(_collateralId, _packageId);
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.REJECTED);
    }

    /** ========================= CONTRACT RELATED FUNCTIONS & STATES ============================= */
    uint256 public numberContracts;    
    mapping (uint256 => Contract) public contracts;
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
        RepaymentCycleType repaymentCycleType;
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

    /** ================================ 1. ACCEPT OFFER (FOR P2P WORKFLOWS) ============================= */
    event LoanContractCreatedEvent(
        address fromAddress,
        uint256 contractId,
        Contract data
    );

    /**
        * @dev accept offer and create contract between collateral and offer
        * @param  _collateralId is id of collateral
        * @param  _offerId is id of offer
        */
    function acceptOffer(uint256 _collateralId, uint256 _offerId) external whenNotPaused {
        Collateral storage collateral = collaterals[_collateralId];
        require(msg.sender == collateral.owner, 'not-collateral-owner');
        require(collateral.status == CollateralStatus.OPEN, 'collateral-not-open');

        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        require(collateralOfferList.isInit == true, 'collateral-not-have-any-offer');
        Offer storage offer = collateralOfferList.offerMapping[_offerId];
        require(offer.isInit == true, 'offer-not-sent-to-collateral');
        require(offer.status == OfferStatus.PENDING, 'offer-unavailable');

        uint256 contractId = createContractFromOffer(_collateralId, collateral, _offerId, offer);
        Contract storage newContract = contracts[contractId];
        // change status of offer and collateral
        offer.status = OfferStatus.ACCEPTED;
        collateral.status = CollateralStatus.DOING;

        // transfer loan asset to collateral owner
        ERC20(newContract.terms.loanAsset).safeTransferFrom(newContract.terms.lender, newContract.terms.borrower, newContract.terms.loanAmount);

        // Cancel other offer sent to this collateral
        for (uint256 i = 0; i < collateralOfferList.offerIdList.length; i++) {
            uint256 thisOfferId = collateralOfferList.offerIdList[i];
            if (thisOfferId != _offerId) {
                Offer storage thisOffer = collateralOfferList.offerMapping[thisOfferId];
                emit CancelOfferEvent(i, _collateralId, thisOffer.owner);

                delete collateralOfferList.offerMapping[thisOfferId];
            }
        }
        delete collateralOfferList.offerIdList;
        collateralOfferList.offerIdList.push(_offerId);

        emit LoanContractCreatedEvent(msg.sender, contractId, newContract);
    }

    /**
        * @dev create contract between collateral and offer
        * @param  _collateralId is id of collateral
        * @param  _offerId is id of offer
        */

    function createContractFromOffer (
        uint256 _collateralId,
        Collateral storage _collateral,
        uint256 _offerId,
        Offer storage _offer
    )
    internal
    returns (uint256 _idx)
    {
        _idx = numberContracts;
        Contract storage newContract = contracts[_idx];
        newContract.collateralId = _collateralId;
        newContract.offerId = int256(_offerId);
        newContract.pawnShopPackageId = -1;
        newContract.status = ContractStatus.ACTIVE;
        newContract.lateCount = 0;
        newContract.terms.borrower = _collateral.owner;
        newContract.terms.lender = _offer.owner;
        newContract.terms.collateralAsset = _collateral.collateralAddress;
        newContract.terms.collateralAmount = _collateral.amount;
        newContract.terms.loanAsset = _collateral.loanAsset;
        newContract.terms.loanAmount = _offer.loanAmount;
        newContract.terms.repaymentAsset = _offer.repaymentAsset;
        newContract.terms.interest = _offer.interest;
        newContract.terms.repaymentCycleType = _offer.repaymentCycleType;
        newContract.terms.liquidityThreshold = _offer.liquidityThreshold;
        newContract.terms.contractStartDate = block.timestamp;
        newContract.terms.contractEndDate = block.timestamp + calculateContractDuration(_offer.loanDurationType, _offer.duration);
        newContract.terms.lateThreshold = lateThreshold;
        newContract.terms.systemFeeRate = systemFeeRate;
        newContract.terms.penaltyRate = penaltyRate;
        newContract.terms.prepaidFeeRate = prepaidFeeRate;
        ++numberContracts;
    }

    uint256 number_seconds_per_week = 7 * 10; // 7 * 24 * 3600
    uint256 number_seconds_per_month = 30 * 10; // 30 * 24 * 3600
    function calculateContractDuration(LoanDurationType durationType, uint256 duration)
    internal view
    returns (uint256 inSeconds)
    {
        if (durationType == LoanDurationType.WEEK) {
            inSeconds = number_seconds_per_week * duration;
        } else {
            inSeconds = number_seconds_per_month * duration;
        }
    }

    /** ================================ 2. ACCEPT COLLATERAL (FOR PAWNSHOP PACKAGE WORKFLOWS) ============================= */
    /**
    * @dev create contract between package and collateral
    * @param  _collateralId is id of collateral
    * @param  _packageId is id of package
    * @param  _loanAmount is number of loan amout for lend
    * @param  _exchangeRate is exchange rate between collateral asset and loan asset, use for validate loan amount again loan to value configuration of package
    */
    function generateContractForCollateralAndPackage(
        uint256 _collateralId,
        uint256 _packageId,
        uint256 _loanAmount,
        uint256 _exchangeRate
    ) external whenNotPaused onlyOperator
    {
        // Package must active
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'package-not-inactive');        
        // Check for collateral status is DOING
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.DOING, 'collateral-not-open');
        // Check for collateral-package status is ACCEPTED (waiting for accept)
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(loanRequestListStruct.isInit == true, 'collateral-havent-had-any-loan-request');
        LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(statusStruct.isInit == true, 'collateral-havent-had-loan-request-for-this-package');
        require(statusStruct.status == LoanRequestStatus.ACCEPTED, 'collateral-loan-request-for-this-package-not-ACCEPTED');
        // TODO: Validation loan amount calculate from _exchangeRate must same with loan to value of package

        // Create Contract
        uint256 contractId = createContractFromPackage(_collateralId, collateral, _packageId, pawnShopPackage, _loanAmount);
        Contract storage newContract = contracts[contractId];
        emit LoanContractCreatedEvent(msg.sender, contractId, newContract);

        // Transfer loan token from lender to borrower
        ERC20(newContract.terms.loanAsset).safeTransferFrom(newContract.terms.lender, newContract.terms.borrower, newContract.terms.loanAmount);

        // Change status of collateral loan request to package to CONTRACTED
        statusStruct.status == LoanRequestStatus.CONTRACTED;
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.CONTRACTED);
    }

    /**
        * @dev create contract between collateral and offer
        * @param  _collateralId is id of collateral
        * @param  _packageId is id of package
        */

    function createContractFromPackage (
        uint256 _collateralId,
        Collateral storage _collateral,
        uint256 _packageId,
        PawnShopPackage storage _package,
        uint256 _loanAmount
    )
    internal
    returns (uint256 _idx)
    {
        _idx = numberContracts;
        Contract storage newContract = contracts[_idx];
        newContract.collateralId = _collateralId;
        newContract.offerId = -1;
        newContract.pawnShopPackageId = int256(_packageId);
        newContract.status = ContractStatus.ACTIVE;
        newContract.lateCount = 0;
        newContract.terms.borrower = _collateral.owner;
        newContract.terms.lender = _package.owner;
        newContract.terms.collateralAsset = _collateral.collateralAddress;
        newContract.terms.collateralAmount = _collateral.amount;
        newContract.terms.loanAsset = _collateral.loanAsset;
        newContract.terms.loanAmount = _loanAmount;
        newContract.terms.repaymentAsset = _package.repaymentAsset;
        newContract.terms.interest = _package.interest;
        newContract.terms.repaymentCycleType = _package.repaymentCycleType;
        newContract.terms.liquidityThreshold = _package.loanToValueLiquidationThreshold;
        newContract.terms.contractStartDate = block.timestamp;
        newContract.terms.contractEndDate = block.timestamp + calculateContractDuration(_collateral.expectedDurationType, _collateral.expectedDurationQty);
        newContract.terms.lateThreshold = lateThreshold;
        newContract.terms.systemFeeRate = systemFeeRate;
        newContract.terms.penaltyRate = penaltyRate;
        newContract.terms.prepaidFeeRate = prepaidFeeRate;
        ++numberContracts;
    }

    /** ================================ 3. PAYMENT REQUEST & REPAYMENT WORKLOWS ============================= */
    /** ===================================== 3.1. PAYMENT REQUEST ============================= */
    mapping (uint256 => PaymentRequest[]) contractPaymentRequestMapping;
    enum PaymentRequestStatusEnum {ACTIVE, LATE, COMPLETE}
    enum PaymentRequestTypeEnum {MONTHLY, OVERDUE_MONTHLY}
    struct PaymentRequest {
        uint256 requestId;
        PaymentRequestTypeEnum paymentRequestType;
        uint256 remainingLoan;
        uint256 penalty;
        uint256 interest;
        uint256 remainingPenalty;
        uint256 remainingInterest;
        uint256 dueDateTimestamp;
        PaymentRequestStatusEnum status;
    }

    event PaymentRequestEvent (
        uint256 contractId,
        PaymentRequest data
    );

    /**
        End lend period settlement and generate invoice for next period
     */
    function closePaymentRequestAndStartNew(
        uint256 _contractId,
        uint256 _remainingLoan,
        uint256 _nextPhrasePenalty,
        uint256 _nextPhraseInterest,
        uint256 _dueDateTimestamp,
        PaymentRequestTypeEnum _paymentRequestType

    ) external whenNotPaused onlyOperator {
        // TODO: Validate
        // - Validate time must over due date
        // - Contract valid
        // - Operator valid
        // - remaining loan, valid

        Contract storage currentContract = contracts[_contractId];
        // Check if number of requests is 0 => create new requests, if not then update current request as LATE or COMPLETE and create new requests
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        if (requests.length > 0) {
            // not first phrase, update previous
            // check for remaining penalty and interest, if greater than zero then is Lated, otherwise is completed
            PaymentRequest storage previousRequest = requests[requests.length - 1];
            if (previousRequest.remainingInterest > 0 || previousRequest.remainingPenalty > 0) {
                previousRequest.status = PaymentRequestStatusEnum.LATE;
                // Update late counter of contract
                currentContract.lateCount += 1;
            } else {
                previousRequest.status = PaymentRequestStatusEnum.COMPLETE;
            }
        }

        // Check for liquidity
        if (currentContract.terms.lateThreshold == currentContract.lateCount) {
            // TODO: Execute liquid
        } else {
            // Create new payment request and store to contract
            PaymentRequest memory newRequest = PaymentRequest({
                requestId: requests.length,
                paymentRequestType: _paymentRequestType,
                remainingLoan: _remainingLoan, // TODO: Recheck what is best way to get remaining loan, should not get from external
                penalty: _nextPhrasePenalty,
                interest: _nextPhraseInterest,
                remainingPenalty: _nextPhrasePenalty,
                remainingInterest: _nextPhraseInterest,
                dueDateTimestamp: _dueDateTimestamp,
                status: PaymentRequestStatusEnum.ACTIVE
            });
            requests.push(newRequest);
            emit PaymentRequestEvent(_contractId, newRequest);
        }
    }

    /** ===================================== 3.2. REPAYMENT ============================= */
    event RepaymentEvent (
        uint256 contractId,
        uint256 paidPenaltyAmount,
        uint256 paidInterestAmount,
        uint256 paidLoanAmount,
        uint256 paidPenaltyFeeAmount,
        uint256 paidInterestFeeAmount,
        uint256 prepaidAmount
    );

    /**
        End lend period settlement and generate invoice for next period
     */
    function repayment(
        uint256 _contractId,
        uint256 _paidPenaltyAmount,
        uint256 _paidInterestAmount,
        uint256 _paidLoanAmount
    ) external whenNotPaused {
        // TODO: Validation: Contract exists, status of contract must be active and in progress, current payment request must be in correct status

        // Get contract & payment request
        Contract storage _contract = contracts[_contractId];
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        PaymentRequest storage _paymentRequest = requests[requests.length - 1];

        // Calculate paid amount / remaining amount, if greater => get paid amount
        if (_paidPenaltyAmount > _paymentRequest.remainingPenalty) {
            _paidPenaltyAmount = _paymentRequest.remainingPenalty;
        }

        if (_paidInterestAmount > _paymentRequest.remainingInterest) {
            _paidInterestAmount = _paymentRequest.remainingInterest;
        }

        if (_paidLoanAmount > _paymentRequest.remainingLoan) {
            _paidLoanAmount = _paymentRequest.remainingLoan;
        }

        // Calculate fee amount based on paid amount
        uint256 _feePenalty = calculateSystemFee(_contract.terms.repaymentAsset, _paidPenaltyAmount, _contract.terms.systemFeeRate);
        uint256 _feeInterest = calculateSystemFee(_contract.terms.repaymentAsset, _paidInterestAmount, _contract.terms.systemFeeRate);
        uint256 _prepaidFee = calculateSystemFee(_contract.terms.loanAsset, _paidLoanAmount, _contract.terms.prepaidFeeRate);

        // TODO: Transfer from caller to borrower (include prepaid fee)

        // TODO: Transfer fee from caller to this contract (penalty fee and interest fee)

        // Update paid amount on payment request
        _paymentRequest.remainingPenalty -= _paidPenaltyAmount;
        _paymentRequest.remainingInterest -= _paidInterestAmount;
        _paymentRequest.remainingLoan -= _paidLoanAmount;

        // TODO: If remaining loan = 0 => paidoff => execute release collateral

        // TODO: emit event repayment
        emit RepaymentEvent(
            _contractId, 
            _paidPenaltyAmount, 
            _paidInterestAmount, 
            _paidLoanAmount, 
            _feePenalty, 
            _feeInterest, 
            _prepaidFee
        );
    }

    function calculateSystemFee(
        address token, 
        uint256 amount, 
        uint256 feeRate
    ) internal returns (uint256 feeAmount) {
        // TODO:
    }


    /** ================ OLD VERSION ======== */

    event Liquidity(
        address transferTo,
        uint256 amount,
        uint256 status
    );

    /**
       * @dev executeLiquidity is function used for asset liquidation
       * @param  _contractId is id contract
       */

    function executeLiquidity(uint256 _contractId)
    internal
    {
        // Contract storage _contract = contracts[_contractId];
        // Offer storage offer = offers[_contract.offerId];
        // Collateral storage collateral = collaterals[_contract.collateralId];
        // //get current status of repayment phase
        // RepaymentPhase memory repaymentPhase = repaymentPhases[_contractId][_contract.currentRepaymentPhase];

        // //the borrower has paid off all the debt
        // if (repaymentPhase.remainingInterest + repaymentPhase.remainingLoan + repaymentPhase.remainingFines == 0) {
        //     //transfer collateral asset back to collateral's owner
        //     if (collateral.collateralAddress != address(0)) {
        //         IERC20(collateral.collateralAddress).transfer(collateral.owner, collateral.amount);
        //     } else {
        //         payable(collateral.owner).transfer(collateral.amount);
        //     }
        //     emit Liquidity(collateral.owner, collateral.amount, 1);
        // } else {
        //     //the borrower hasn't paid off all the debt
        //     if (collateral.collateralAddress != address(0)) { // transfer collateral to offer's owner
        //         IERC20(collateral.collateralAddress).transfer(offer.owner, collateral.amount);
        //     } else {
        //         payable(offer.owner).transfer(collateral.amount);
        //     }
        //     emit Liquidity(offer.owner, collateral.amount, 0);
        // }

        // //change status of contract, collateral, offer
        // _contract.status = ContractStatus.COMPLETED;
        // collateral.status = CollateralStatus.COMPLETED;
        // offer.status = OfferStatus.COMPLETED;
    }

    /**
     * @dev liquidity is the function for Admin execute contract liquidation
     * @param  _contractId is the id of contract
     */
    // function liquidity(uint256 _contractId)
    // external onlyOperator
    // whenNotPaused {
    //     executeLiquidity(_contractId);
    // }
}
