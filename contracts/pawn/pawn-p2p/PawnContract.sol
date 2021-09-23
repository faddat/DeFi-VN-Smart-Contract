// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PawnLib.sol";
import "../reputation/IReputation.sol";

contract PawnContract is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    mapping (address => uint256) public whitelistCollateral;
    address public operator; 
    address public feeWallet = address(this);
    uint256 public penaltyRate;
    uint256 public systemFeeRate; 
    uint256 public lateThreshold;
    uint256 public prepaidFeeRate;
    uint256 public ZOOM;  
    bool public initialized = false;
    address public admin;
    // enum LoanDurationType {WEEK, MONTH}

    /**
     * @dev initialize function
     * @param _zoom is coefficient used to represent risk params
     */

    function initialize(
        uint256 _zoom
    ) external notInitialized {
        ZOOM = _zoom;
        initialized = true;
        admin = address(msg.sender);
    }

    function setOperator(address _newOperator) onlyAdmin external {
        operator = _newOperator;
    }

    function setFeeWallet(address _newFeeWallet) onlyAdmin external {
        feeWallet = _newFeeWallet;
    }

    function pause() onlyAdmin external {
        _pause();
    }

    function unPause() onlyAdmin external {
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

    function setWhitelistCollateral(address _token, uint256 _status) external onlyAdmin {
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
        require(operator == msg.sender, "operator");
        _;
    }

    modifier onlyAdmin() {
        require(admin == msg.sender, "admin");
        _;
    }

    function emergencyWithdraw(address _token)
    external onlyAdmin
    whenPaused {
        PawnLib.safeTransfer(_token, address(this), admin, PawnLib.calculateAmount(_token, address(this)));
    }

    /** ========================= COLLATERAL FUNCTIONS & STATES ============================= */
    uint256 public numberCollaterals;
    mapping (uint256 => Collateral) public collaterals;
    
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
        require(whitelistCollateral[_collateralAddress] == 1, 'n-sup-col');
        //validate: cannot use BNB as loanAsset
        require(_loanAsset != address(0), 'bnb');

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
            //Package must active
            PawnShopPackage storage pawnShopPackage = pawnShopPackages[uint256(_packageId)];
            require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'pack');

            _submitCollateralToPackage(_idx, uint256(_packageId));
            emit SubmitPawnShopPackage(uint256(_packageId), _idx, LoanRequestStatus.PENDING);
        }

        // transfer to this contract
        PawnLib.safeTransfer(_collateralAddress, msg.sender, address(this), _amount);

        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.BR_CREATE_COLLATERAL);
    }

    /**
    * @dev cancel collateral function and return back collateral
    * @param  _collateralId is id of collateral
    */
    function withdrawCollateral(
        uint256 _collateralId
    ) external whenNotPaused {
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.owner == msg.sender, 'owner');
        require(collateral.status == CollateralStatus.OPEN, 'col');

        PawnLib.safeTransfer(collateral.collateralAddress, address(this), collateral.owner, collateral.amount);

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

        delete collaterals[_collateralId];
        emit WithdrawCollateralEvent(_collateralId, msg.sender);

        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.BR_CANCEL_COLLATERAL);
    }

    /** ========================= OFFER FUNCTIONS & STATES ============================= */
    uint256 public numberOffers;

    mapping (uint256 => CollateralOfferList) public collateralOffersMapping;

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
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.OPEN, 'col');
        // validate not allow for collateral owner to create offer
        require(collateral.owner != msg.sender, 'owner');
        // Validate ower already approve for this contract to withdraw
        require(IERC20(collateral.loanAsset).allowance(msg.sender, address(this)) >= _loanAmount, 'not-apr');

        // Get offers of collateral
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        if (!collateralOfferList.isInit) {
            collateralOfferList.isInit = true;
        }
        // Create offer id       
        _idx = numberOffers;

        // Create offer data
        Offer storage _offer = collateralOfferList.offerMapping[_idx];

        _offer.isInit = true;
        _offer.owner = msg.sender;
        _offer.loanAmount = _loanAmount;
        _offer.interest = _interest;
        _offer.duration = _duration;
        _offer.loanDurationType = LoanDurationType(_loanDurationType);
        _offer.repaymentAsset = _repaymentAsset;
        _offer.repaymentCycleType = LoanDurationType(_repaymentCycleType);
        _offer.liquidityThreshold = _liquidityThreshold;
        _offer.status = OfferStatus.PENDING;

        collateralOfferList.offerIdList.push(_idx);

        ++numberOffers;

        emit CreateOfferEvent(_idx, _collateralId, _offer);
        
        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.LD_CREATE_OFFER);
    }

    /**
    * @dev cancel offer function, used for cancel offer
    * @param  _offerId is id of offer
    * @param _collateralId is id of collateral associated with offer
    */
    function cancelOffer(
        uint256 _offerId, 
        uint256 _collateralId
    ) external whenNotPaused {
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        require(collateralOfferList.isInit == true, 'col');
        Offer storage offer = collateralOfferList.offerMapping[_offerId];
        require(offer.isInit == true, 'offer-col');
        require(offer.owner == msg.sender, 'owner');
        require(offer.status == OfferStatus.PENDING, 'offer');
        delete collateralOfferList.offerMapping[_offerId];
        for (uint i = 0; i < collateralOfferList.offerIdList.length; i ++) {
            if (collateralOfferList.offerIdList[i] == _offerId) {
                collateralOfferList.offerIdList[i] = collateralOfferList.offerIdList[collateralOfferList.offerIdList.length - 1];
                break;
            }
        }

        delete collateralOfferList.offerIdList[collateralOfferList.offerIdList.length - 1];
        emit CancelOfferEvent(_offerId, _collateralId, msg.sender);
        
        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.LD_CANCEL_OFFER);
    }

    /** ========================= PAWNSHOP PACKAGE FUNCTIONS & STATES ============================= */
    uint256 public numberPawnShopPackages;
    mapping (uint256 => PawnShopPackage) public pawnShopPackages;

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
        LoanDurationType _repaymentCycleType,
        uint256 _loanToValue,
        uint256 _loanToValueLiquidationThreshold
    ) external whenNotPaused
    returns (uint256 _idx)
    {
        _idx = numberPawnShopPackages;

        // Validataion logic: whitelist collateral, ranges must have upper greater than lower, duration type
        for (uint256 i = 0; i < _collateralAcceptance.length; i++) {
            require(whitelistCollateral[_collateralAcceptance[i]] == 1, 'col');
        }

        require(_loanAmountRange.lowerBound < _loanAmountRange.upperBound, 'loan-rge');
        require(_durationRange.lowerBound < _durationRange.upperBound, 'dur-rge');
        require(_durationType < 2, 'dur-type');
        
        require(_loanToken != address(0), 'bnb');

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
        
        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.LD_CREATE_PACKAGE);
    }

    function activePawnShopPackage(uint256 _packageId)
    external whenNotPaused
    {
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.owner == msg.sender, 'owner');
        require(pawnShopPackage.status == PawnShopPackageStatus.INACTIVE, 'pack');

        pawnShopPackage.status = PawnShopPackageStatus.ACTIVE;
        emit ChangeStatusPawnShopPackage(_packageId, PawnShopPackageStatus.ACTIVE);
        
        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.LD_REOPEN_PACKAGE);
    }

    function deactivePawnShopPackage(uint256 _packageId)
    external whenNotPaused
    {
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.owner == msg.sender, 'owner');
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'pack');

        pawnShopPackage.status = PawnShopPackageStatus.INACTIVE;
        emit ChangeStatusPawnShopPackage(_packageId, PawnShopPackageStatus.INACTIVE);
        
        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.LD_CANCEL_PACKAGE);
    }

    /** ========================= SUBMIT & ACCEPT WORKFLOW OF PAWNSHOP PACKAGE FUNCTIONS & STATES ============================= */
    
    mapping (uint256 => CollateralAsLoanRequestListStruct) public collateralAsLoanRequestMapping; // Map from collateral to loan request
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
        require(collateral.owner == msg.sender, 'owner');
        require(collateral.status == CollateralStatus.OPEN, 'col');
        
        PawnShopPackage storage pawnShopPackage = pawnShopPackages[_packageId];
        require(pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'pack');

        // VALIDATE HAVEN'T SUBMIT TO PACKAGE YET
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        if (loanRequestListStruct.isInit == true) {
            LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
            require(statusStruct.isInit == false, 'subed');
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
        require(statusStruct.isInit == false);
        statusStruct.isInit = true;
        statusStruct.status = LoanRequestStatus.PENDING;
        loanRequestListStruct.pawnShopPackageIdList.push(_packageId);
    }

    function withdrawCollateralFromPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) whenNotPaused external {
        // Collateral must OPEN
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.OPEN, 'col');
        // Sender is collateral owner
        require(collateral.owner == msg.sender, 'owner');
        // collateral-package status must pending
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        LoanRequestStatusStruct storage loanRequestStatus = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(loanRequestStatus.status == LoanRequestStatus.PENDING, 'col-pack');

        _removeCollateralFromPackage(_collateralId, _packageId);
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.CANCEL);
    }

    function _removeCollateralFromPackage (
        uint256 _collateralId,
        uint256 _packageId
    ) internal {
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
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
        (
            PawnShopPackage storage pawnShopPackage,
            Collateral storage collateral,
            CollateralAsLoanRequestListStruct storage loanRequestListStruct,
            LoanRequestStatusStruct storage statusStruct
        ) = checkConditionCollateralPackage(_collateralId, _packageId, CollateralStatus.OPEN, LoanRequestStatus.PENDING);
        
        // Check for owner of packageId
        require(pawnShopPackage.owner == msg.sender || msg.sender == operator, 'owner-or-oper');

        // Execute accept => change status of loan request to ACCEPTED, wait for system to generate contract
        // Update status of loan request between _collateralId and _packageId to Accepted
        statusStruct.status = LoanRequestStatus.ACCEPTED;
        collateral.status = CollateralStatus.DOING;

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
        }        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.ACCEPTED);
    }

    function rejectCollateralOfPackage(
        uint256 _collateralId,
        uint256 _packageId
    ) external whenNotPaused
    {
        (
            PawnShopPackage storage pawnShopPackage,
            ,
            ,            
        ) = checkConditionCollateralPackage(_collateralId, _packageId, CollateralStatus.OPEN, LoanRequestStatus.PENDING);
        require(pawnShopPackage.owner == msg.sender);

        _removeCollateralFromPackage(_collateralId, _packageId);
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.REJECTED);
    }

    function checkConditionCollateralPackage(
        uint256 _collateralId,
        uint256 _packageId,
        CollateralStatus _requiredCollateralStatus,
        LoanRequestStatus _requiredLoanRequestStatus
    ) internal view returns (
        PawnShopPackage storage _pawnShopPackage, 
        Collateral storage _collateral, 
        CollateralAsLoanRequestListStruct storage _loanRequestListStruct, 
        LoanRequestStatusStruct storage _statusStruct
    ) {
        // Check for owner of packageId
        _pawnShopPackage = pawnShopPackages[_packageId];
        require(_pawnShopPackage.status == PawnShopPackageStatus.ACTIVE, 'pack');        
        // Check for collateral status is open
        _collateral = collaterals[_collateralId];
        require(_collateral.status == _requiredCollateralStatus, 'col');
        // Check for collateral-package status is PENDING (waiting for accept)
        _loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(_loanRequestListStruct.isInit == true, 'col-loan-req');
        _statusStruct = _loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(_statusStruct.isInit == true, 'col-loan-req-pack');
        require(_statusStruct.status == _requiredLoanRequestStatus, 'stt');
    }

    /** ========================= CONTRACT RELATED FUNCTIONS & STATES ============================= */
    uint256 public numberContracts;    
    mapping (uint256 => Contract) public contracts;
    
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
        require(msg.sender == collateral.owner, 'owner');
        require(collateral.status == CollateralStatus.OPEN, 'col');

        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_collateralId];
        require(collateralOfferList.isInit == true, 'col-off');
        Offer storage offer = collateralOfferList.offerMapping[_offerId];
        require(offer.isInit == true, 'not-sent');
        require(offer.status == OfferStatus.PENDING, 'unavail');

        uint256 contractId = createContract(_collateralId, collateral, -1, int256(_offerId), offer.loanAmount, offer.owner, offer.repaymentAsset, offer.interest, offer.loanDurationType, offer.liquidityThreshold);
        Contract storage newContract = contracts[contractId];
        // change status of offer and collateral
        offer.status = OfferStatus.ACCEPTED;
        collateral.status = CollateralStatus.DOING;

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

        // transfer loan asset to collateral owner
        PawnLib.safeTransfer(newContract.terms.loanAsset, newContract.terms.lender, newContract.terms.borrower, newContract.terms.loanAmount);

        // Adjust reputation score
        _reputation.adjustReputationScore(msg.sender, IReputation.ReasonType.BR_ACCEPT_OFFER);
        _reputation.adjustReputationScore(offer.owner, IReputation.ReasonType.BR_ACCEPT_OFFER);
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
        (
            PawnShopPackage storage pawnShopPackage,
            Collateral storage collateral,
            ,
            LoanRequestStatusStruct storage statusStruct
        ) = checkConditionCollateralPackage(_collateralId, _packageId, CollateralStatus.DOING, LoanRequestStatus.ACCEPTED);

        // Create Contract
        uint256 contractId = createContract(_collateralId, collateral, int256(_packageId), -1, _loanAmount, pawnShopPackage.owner, pawnShopPackage.repaymentAsset, pawnShopPackage.interest, pawnShopPackage.repaymentCycleType, pawnShopPackage.loanToValueLiquidationThreshold);
        Contract storage newContract = contracts[contractId];
        emit LoanContractCreatedEvent(msg.sender, contractId, newContract);

        // Change status of collateral loan request to package to CONTRACTED
        statusStruct.status == LoanRequestStatus.CONTRACTED;
        emit SubmitPawnShopPackage(_packageId, _collateralId, LoanRequestStatus.CONTRACTED);

        // Transfer loan token from lender to borrower
        PawnLib.safeTransfer(newContract.terms.loanAsset, newContract.terms.lender, newContract.terms.borrower, newContract.terms.loanAmount);
        
        // Adjust reputation score
        _reputation.adjustReputationScore(pawnShopPackage.owner, IReputation.ReasonType.LD_GENERATE_CONTRACT);
    }

    function createContract (
        uint256 _collateralId,
        Collateral storage _collateral,
        int256 _packageId,
        int256 _offerId,
        uint256 _loanAmount,
        address _lender,
        address _repaymentAsset,
        uint256 _interest,
        LoanDurationType _repaymentCycleType,
        uint256 _liquidityThreshold
    )
    internal
    returns (uint256 _idx)
    {
        _idx = numberContracts;
        Contract storage newContract = contracts[_idx];
        newContract.collateralId = _collateralId;
        newContract.offerId = _offerId;
        newContract.pawnShopPackageId = int256(_packageId);
        newContract.status = ContractStatus.ACTIVE;
        newContract.lateCount = 0;
        newContract.terms.borrower = _collateral.owner;
        newContract.terms.lender = _lender;
        newContract.terms.collateralAsset = _collateral.collateralAddress;
        newContract.terms.collateralAmount = _collateral.amount;
        newContract.terms.loanAsset = _collateral.loanAsset;
        newContract.terms.loanAmount = _loanAmount;
        newContract.terms.repaymentCycleType = _repaymentCycleType;
        newContract.terms.repaymentAsset = _repaymentAsset;
        newContract.terms.interest = _interest;
        newContract.terms.liquidityThreshold = _liquidityThreshold;
        newContract.terms.contractStartDate = block.timestamp;
        newContract.terms.contractEndDate = block.timestamp + PawnLib.calculateContractDuration(_collateral.expectedDurationType, _collateral.expectedDurationQty);
        newContract.terms.lateThreshold = lateThreshold;
        newContract.terms.systemFeeRate = systemFeeRate;
        newContract.terms.penaltyRate = penaltyRate;
        newContract.terms.prepaidFeeRate = prepaidFeeRate;
        ++numberContracts;
    }

    /** ================================ 3. PAYMENT REQUEST & REPAYMENT WORKLOWS ============================= */
    /** ===================================== 3.1. PAYMENT REQUEST ============================= */
    mapping (uint256 => PaymentRequest[]) public contractPaymentRequestMapping;
    
    event PaymentRequestEvent (
        uint256 contractId,
        PaymentRequest data
    );

    function closePaymentRequestAndStartNew(
        uint256 _contractId,
        uint256 _remainingLoan,
        uint256 _nextPhrasePenalty,
        uint256 _nextPhraseInterest,
        uint256 _dueDateTimestamp,
        PaymentRequestTypeEnum _paymentRequestType,
        bool _chargePrepaidFee

    ) external whenNotPaused onlyOperator {
        Contract storage currentContract = contractMustActive(_contractId);

        // Check if number of requests is 0 => create new requests, if not then update current request as LATE or COMPLETE and create new requests
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        if (requests.length > 0) {
            // not first phrase, get previous request
            PaymentRequest storage previousRequest = requests[requests.length - 1];
            
            // Validate: time must over due date of current payment
            require(block.timestamp >= previousRequest.dueDateTimestamp, 'time-not-due');

            // Validate: remaining loan must valid
            require(previousRequest.remainingLoan == _remainingLoan, 'remain');

            // Validate: Due date timestamp of next payment request must not over contract due date
            require(_dueDateTimestamp <= currentContract.terms.contractEndDate, 'contr-end');
            require(_dueDateTimestamp > previousRequest.dueDateTimestamp || _dueDateTimestamp == 0, 'less-th-prev');

            // update previous
            // check for remaining penalty and interest, if greater than zero then is Lated, otherwise is completed
            if (previousRequest.remainingInterest > 0 || previousRequest.remainingPenalty > 0) {
                previousRequest.status = PaymentRequestStatusEnum.LATE;
                // Update late counter of contract
                currentContract.lateCount += 1;

                // Check for late threshold reach
                if (currentContract.terms.lateThreshold <= currentContract.lateCount) {
                    // Execute liquid
                    _liquidationExecution(_contractId, ContractLiquidedReasonType.LATE);
                    return;
                }
            } else {
                previousRequest.status = PaymentRequestStatusEnum.COMPLETE;
            }

            // Check for last repayment, if last repayment, all paid
            if (block.timestamp > currentContract.terms.contractEndDate) {
                if (previousRequest.remainingInterest + previousRequest.remainingPenalty + previousRequest.remainingLoan > 0) {
                    // unpaid => liquid
                    _liquidationExecution(_contractId, ContractLiquidedReasonType.UNPAID);
                    return;
                } else {
                    // paid full => release collateral
                    _returnCollateralToBorrowerAndCloseContract(_contractId);
                    return;
                }
            }

            emit PaymentRequestEvent(_contractId, previousRequest);
        } else {
            // Validate: remaining loan must valid
            require(currentContract.terms.loanAmount == _remainingLoan, 'remain');

            // Validate: Due date timestamp of next payment request must not over contract due date
            require(_dueDateTimestamp <= currentContract.terms.contractEndDate, 'contr-end');
            require(_dueDateTimestamp > currentContract.terms.contractStartDate || _dueDateTimestamp == 0, 'less-th-prev');
            require(block.timestamp < _dueDateTimestamp || _dueDateTimestamp == 0, 'over');

            // Check for last repayment, if last repayment, all paid
            if (block.timestamp > currentContract.terms.contractEndDate) {
                // paid full => release collateral
                _returnCollateralToBorrowerAndCloseContract(_contractId);
                return;
            }
        }

        // Create new payment request and store to contract
        PaymentRequest memory newRequest = PaymentRequest({
            requestId: requests.length,
            paymentRequestType: _paymentRequestType,
            remainingLoan: _remainingLoan,
            penalty: _nextPhrasePenalty,
            interest: _nextPhraseInterest,
            remainingPenalty: _nextPhrasePenalty,
            remainingInterest: _nextPhraseInterest,
            dueDateTimestamp: _dueDateTimestamp,
            status: PaymentRequestStatusEnum.ACTIVE,
            chargePrepaidFee: _chargePrepaidFee
        });
        requests.push(newRequest);
        emit PaymentRequestEvent(_contractId, newRequest);
    }

    /** ===================================== 3.2. REPAYMENT ============================= */
    event RepaymentEvent (
        uint256 contractId,
        uint256 paidPenaltyAmount,
        uint256 paidInterestAmount,
        uint256 paidLoanAmount,
        uint256 paidPenaltyFeeAmount,
        uint256 paidInterestFeeAmount,
        uint256 prepaidAmount,
        uint256 paymentRequestId
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
        // Get contract & payment request
        Contract storage _contract = contractMustActive(_contractId);
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        require(requests.length > 0, 'paymnt-req');
        PaymentRequest storage _paymentRequest = requests[requests.length - 1];
        
        // Validation: Contract must not overdue
        require(block.timestamp <= _contract.terms.contractEndDate, 'contr-over');

        // Validation: current payment request must active and not over due
        require(_paymentRequest.status == PaymentRequestStatusEnum.ACTIVE, 'not-act');
        if (_paidPenaltyAmount + _paidInterestAmount > 0) {
            require(block.timestamp <= _paymentRequest.dueDateTimestamp, 'over-due');
        }

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
        uint256 _feePenalty = PawnLib.calculateSystemFee(_paidPenaltyAmount, _contract.terms.systemFeeRate, ZOOM);
        uint256 _feeInterest = PawnLib.calculateSystemFee(_paidInterestAmount, _contract.terms.systemFeeRate, ZOOM);

        uint256 _prepaidFee = 0;
        if (_paymentRequest.chargePrepaidFee) {
            _prepaidFee = PawnLib.calculateSystemFee(_paidLoanAmount, _contract.terms.prepaidFeeRate, ZOOM);
        }

        // Update paid amount on payment request
        _paymentRequest.remainingPenalty -= _paidPenaltyAmount;
        _paymentRequest.remainingInterest -= _paidInterestAmount;
        _paymentRequest.remainingLoan -= _paidLoanAmount;

        // emit event repayment
        emit RepaymentEvent(
            _contractId, 
            _paidPenaltyAmount, 
            _paidInterestAmount, 
            _paidLoanAmount, 
            _feePenalty, 
            _feeInterest, 
            _prepaidFee,
            _paymentRequest.requestId
        );

        // If remaining loan = 0 => paidoff => execute release collateral
        if (_paymentRequest.remainingLoan == 0 && _paymentRequest.remainingPenalty == 0 && _paymentRequest.remainingInterest == 0) {
            _returnCollateralToBorrowerAndCloseContract(_contractId);
        }

        if (_paidPenaltyAmount + _paidInterestAmount > 0) {
            // Transfer fee to fee wallet
            PawnLib.safeTransfer(_contract.terms.repaymentAsset, msg.sender, feeWallet, _feePenalty + _feeInterest);

            // Transfer penalty and interest to lender except fee amount
            PawnLib.safeTransfer(_contract.terms.repaymentAsset, msg.sender, _contract.terms.lender, _paidPenaltyAmount + _paidInterestAmount - _feePenalty - _feeInterest);   
        }

        if (_paidLoanAmount > 0) {
            // Transfer loan amount and prepaid fee to lender
            PawnLib.safeTransfer(_contract.terms.loanAsset, msg.sender, _contract.terms.lender, _paidLoanAmount + _prepaidFee);
        }
    }
    /** ===================================== 3.3. LIQUIDITY & DEFAULT ============================= */
    // enum ContractLiquidedReasonType { LATE, RISK, UNPAID }
    event ContractLiquidedEvent(
        uint256 contractId,
        uint256 liquidedAmount,
        uint256 feeAmount,
        ContractLiquidedReasonType reasonType
    );
    event LoanContractCompletedEvent(
        uint256 contractId
    );

    function collateralRiskLiquidationExecution(
        uint256 _contractId,
        uint256 _collateralPerRepaymentTokenExchangeRate,
        uint256 _collateralPerLoanAssetExchangeRate
    ) external whenNotPaused onlyOperator {
        // Validate: Contract must active
        Contract storage _contract = contractMustActive(_contractId);

        (uint256 remainingRepayment, uint256 remainingLoan) = calculateRemainingLoanAndRepaymentFromContract(_contractId, _contract);
        uint256 valueOfRemainingRepayment = (_collateralPerRepaymentTokenExchangeRate * remainingRepayment) / ZOOM;
        uint256 valueOfRemainingLoan = (_collateralPerLoanAssetExchangeRate * remainingLoan) / ZOOM;
        uint256 valueOfCollateralLiquidationThreshold = _contract.terms.collateralAmount * _contract.terms.liquidityThreshold / (100 * ZOOM);

        require(valueOfRemainingLoan + valueOfRemainingRepayment >= valueOfCollateralLiquidationThreshold, 'under-thres');

        // Execute: call internal liquidation
        _liquidationExecution(_contractId, ContractLiquidedReasonType.RISK);
        
    }

    function calculateRemainingLoanAndRepaymentFromContract(
        uint256 _contractId,
        Contract storage _contract
    ) internal view 
    returns (uint256 remainingRepayment, uint256 remainingLoan) {
        // Validate: sum of unpaid interest, penalty and remaining loan in value must reach liquidation threshold of collateral value
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        if (requests.length > 0) {
            // Have payment request
            PaymentRequest storage _paymentRequest = requests[requests.length - 1];
            remainingRepayment = _paymentRequest.remainingInterest + _paymentRequest.remainingPenalty;
            remainingLoan = _paymentRequest.remainingLoan;
        } else {
            // Haven't had payment request
            remainingRepayment = 0;
            remainingLoan = _contract.terms.loanAmount;
        }
    }

    function lateLiquidationExecution(
        uint256 _contractId
    ) external whenNotPaused {
        // Validate: Contract must active
        Contract storage _contract = contractMustActive(_contractId);

        // validate: contract have lateCount == lateThreshold
        require(_contract.lateCount >= _contract.terms.lateThreshold, 'not-reach');

        // Execute: call internal liquidation
        _liquidationExecution(_contractId, ContractLiquidedReasonType.LATE);
    }

    function contractMustActive(
        uint256 _contractId
    ) internal view 
    returns (Contract storage _contract) {
        // Validate: Contract must active
        _contract = contracts[_contractId];
        require(_contract.status == ContractStatus.ACTIVE, 'contr-act');
    }

    function notPaidFullAtEndContractLiquidation(
        uint256 _contractId
    ) external whenNotPaused {
        Contract storage _contract = contractMustActive(_contractId);
        // validate: current is over contract end date
        require(block.timestamp >= _contract.terms.contractEndDate, 'due');

        // validate: remaining loan, interest, penalty haven't paid in full
        (uint256 remainingRepayment, uint256 remainingLoan) = calculateRemainingLoanAndRepaymentFromContract(_contractId, _contract);
        require(remainingRepayment + remainingLoan > 0, 'paid');
        
        // Execute: call internal liquidation
        _liquidationExecution(_contractId, ContractLiquidedReasonType.LATE);
    }

    function _liquidationExecution(
        uint256 _contractId,
        ContractLiquidedReasonType _reasonType
    ) internal {
        Contract storage _contract = contracts[_contractId];

        // Execute: calculate system fee of collateral and transfer collateral except system fee amount to lender
        uint256 _systemFeeAmount = PawnLib.calculateSystemFee(_contract.terms.collateralAmount, _contract.terms.systemFeeRate, ZOOM);
        uint256 _liquidAmount = _contract.terms.collateralAmount - _systemFeeAmount;

        // Execute: update status of contract to DEFAULT, collateral to COMPLETE
        _contract.status = ContractStatus.DEFAULT;
        PaymentRequest[] storage _paymentRequests = contractPaymentRequestMapping[_contractId];
        PaymentRequest storage _lastPaymentRequest = _paymentRequests[_paymentRequests.length - 1];
        _lastPaymentRequest.status = PaymentRequestStatusEnum.DEFAULT;
        Collateral storage _collateral = collaterals[_contract.collateralId];
        _collateral.status = CollateralStatus.COMPLETED;

        // Emit Event ContractLiquidedEvent & PaymentRequest event
        emit ContractLiquidedEvent(
            _contractId,
            _liquidAmount,
            _systemFeeAmount,
            _reasonType
        );

        emit PaymentRequestEvent(_contractId, _lastPaymentRequest);

        // Transfer to lender liquid amount
        PawnLib.safeTransfer(_contract.terms.collateralAsset, address(this), _contract.terms.lender, _liquidAmount);

        // Transfer to system fee wallet fee amount
        PawnLib.safeTransfer(_contract.terms.collateralAsset, address(this), feeWallet, _systemFeeAmount);

        // Adjust reputation score
        _reputation.adjustReputationScore(_contract.terms.borrower, IReputation.ReasonType.BR_CONTRACT_DEFAULTED);

    }

    function _returnCollateralToBorrowerAndCloseContract(
        uint256 _contractId
    ) internal {
        Contract storage _contract = contracts[_contractId];

        // Execute: Update status of contract to COMPLETE, collateral to COMPLETE
        _contract.status = ContractStatus.COMPLETED;
        PaymentRequest[] storage _paymentRequests = contractPaymentRequestMapping[_contractId];
        PaymentRequest storage _lastPaymentRequest = _paymentRequests[_paymentRequests.length - 1];
        _lastPaymentRequest.status = PaymentRequestStatusEnum.COMPLETE;
        Collateral storage _collateral = collaterals[_contract.collateralId];
        _collateral.status = CollateralStatus.COMPLETED;

        // Emit event ContractCompleted
        emit LoanContractCompletedEvent(_contractId);
        emit PaymentRequestEvent(_contractId, _lastPaymentRequest);

        // Execute: Transfer collateral to borrower
        PawnLib.safeTransfer(_contract.terms.collateralAsset, address(this), _contract.terms.borrower, _contract.terms.collateralAmount);

        // Adjust reputation score
        _reputation.adjustReputationScore(_contract.terms.borrower, IReputation.ReasonType.BR_CONTRACT_COMPLETE);
    }

    function findContractOfCollateral(
        uint256 _collateralId,
        uint256 _contractStart,
        uint256 _contractEnd
    ) external view returns (int256 _idx) {
        _idx = -1;
        uint256 endIdx = _contractEnd;
        if (_contractEnd >= numberContracts - 1) {
            endIdx = numberContracts - 1;
        }
        for (uint i = _contractStart; i < endIdx; i ++) {
            Contract storage mContract = contracts[i];
            if (mContract.collateralId == _collateralId) {
                _idx = int256(i);
                break;
            }
        }
    }
    
    function releaseTrappedCollateralLockedWithoutContract(
        uint256 _collateralId,
        uint256 _packageId
    ) external onlyAdmin {
        // Validate: Collateral must Doing
        Collateral storage collateral = collaterals[_collateralId];
        require(collateral.status == CollateralStatus.DOING, 'col');

        // Check for collateral not being in any contract
        for (uint i = 0; i < numberContracts - 1; i ++) {
            Contract storage mContract = contracts[i];
            require(mContract.collateralId != _collateralId, 'col-in-cont');
        }

        // Check for collateral-package status is ACCEPTED
        CollateralAsLoanRequestListStruct storage loanRequestListStruct = collateralAsLoanRequestMapping[_collateralId];
        require(loanRequestListStruct.isInit == true, 'col-loan-req');
        LoanRequestStatusStruct storage statusStruct = loanRequestListStruct.loanRequestToPawnShopPackageMapping[_packageId];
        require(statusStruct.isInit == true, 'col-loan-req-pack');
        require(statusStruct.status == LoanRequestStatus.ACCEPTED, 'not-acpt');

        // Update status of loan request
        statusStruct.status = LoanRequestStatus.PENDING;
        collateral.status = CollateralStatus.OPEN;
    }

    event AdminChanged(address _from, address _to);

    function changeAdmin(address newAddress) external onlyAdmin {
        address oldAdmin = admin;
        admin = newAddress;

        emit AdminChanged(oldAdmin, newAddress);
    }

    /** ===================================== REPUTATION FUNCTIONS & STATES ===================================== */

    IReputation public _reputation;
    
    function setReputationContract(address _reputationAddress) external onlyAdmin {
        _reputation = IReputation(_reputationAddress);
    }
}
