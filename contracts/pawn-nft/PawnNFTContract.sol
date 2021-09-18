// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../evaluation/DFY-AccessControl.sol";
import "../evaluation/IDFY_Physical_NFTs.sol";
import "../evaluation/DFY_Physical_NFTs.sol";
import "../evaluation/EvaluationContract.sol";
import "../evaluation/IBEP20.sol";
import "./IPawnNFT.sol";
import "./PawnNFTLib.sol";

contract PawnNFTContract is 
    IPawnNFT, 
    Initializable, 
    UUPSUpgradeable,
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable, 
    ERC1155HolderUpgradeable,
    DFYAccessControl
{

    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    mapping (address => uint256) public whitelistCollateral;
    address public operator;
    address public feeWallet;
    uint256 public penaltyRate;
    uint256 public systemFeeRate;
    uint256 public lateThreshold;
    uint256 public prepaidFeeRate;
    uint256 public ZOOM;
    address public admin;

    // DFY_Physical_NFTs dfy_physical_nfts;
    // AssetEvaluation assetEvaluation;

    function initialize(uint256 _zoom) public initializer {
        __ERC1155Holder_init();
        __DFYAccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        ZOOM = _zoom;
        admin = address(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function supportsInterface(bytes4 interfaceId) 
        public view 
        override(ERC1155ReceiverUpgradeable, AccessControlUpgradeable) 
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setOperator(address _newOperator) onlyRole(DEFAULT_ADMIN_ROLE) external {
        operator = _newOperator;
    }

    function setFeeWallet(address _newFeeWallet) onlyRole(DEFAULT_ADMIN_ROLE) external {
        feeWallet = _newFeeWallet;
    }

    function pause() onlyRole(DEFAULT_ADMIN_ROLE) external {
        _pause();
    }

    function unPause() onlyRole(DEFAULT_ADMIN_ROLE) external {
        _unpause();
    }

    /**
    * @dev set fee for each token
    * @param _feeRate is percentage of tokens to pay for the transaction
    */
    function setSystemFeeRate(uint256 _feeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        systemFeeRate = _feeRate;
    }

    /**
    * @dev set fee for each token
    * @param _feeRate is percentage of tokens to pay for the penalty
    */
    function setPenaltyRate(uint256 _feeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        penaltyRate = _feeRate;
    }

    /**
    * @dev set fee for each token
    * @param _threshold is number of time allowed for late repayment
    */
    function setLateThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lateThreshold = _threshold;
    }

    function setPrepaidFeeRate(uint256 _feeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        prepaidFeeRate = _feeRate;
    }

    function setWhitelistCollateral(address _token, uint256 _status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistCollateral[_token] = _status;
    }

    function emergencyWithdraw(address _token)
        external 
        whenPaused 
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        PawnNFTLib.safeTransfer(_token, address(this), admin, PawnNFTLib.calculateAmount(_token, address(this)));
    }

    /** ========================= EVENT ============================= */
    //create collateral & withdraw
    event CollateralEvent(
        uint256 nftCollateralId,
        Collateral data,
        uint256 UID
    );
    
    //create offer & cancel
    event OfferEvent(
        uint256 offerId,
        uint256 nftCollateralId,
        Offer data,
        uint256 UID
    );

    //accept offer
    event LoanContractCreatedEvent(
        address fromAddress,
        uint256 contractId,   
        Contract data,
        uint256 UID
    );

    //repayment
    event PaymentRequestEvent (
        uint256 contractId,
        PaymentRequest data
    );

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

    //liquidity & defaul
     event ContractLiquidedEvent(
        uint256 contractId,
        uint256 liquidedAmount,
        uint256 feeAmount,
        ContractLiquidedReasonType reasonType
    );

    event LoanContractCompletedEvent(
        uint256 contractId
    );

    event CancelOfferEvent(
        uint256 offerId,
        uint256 nftCollateralId,
        address offerOwner,
        uint256 UID
    );

    // Total collateral
    CountersUpgradeable.Counter public numberCollaterals;

    // Mapping collateralId => Collateral
    mapping (uint256 => Collateral) public collaterals;

    // Total offer
    CountersUpgradeable.Counter public numberOffers;
    
    // Mapping collateralId => list offer of collateral
    mapping (uint256 => CollateralOfferList) public collateralOffersMapping;

    // Total contract
    uint256 public numberContracts;

    // Mapping contractId => Contract
    mapping (uint256 => Contract) public contracts;

    // Mapping contract Id => array payment request
    mapping (uint256 => PaymentRequest[]) public contractPaymentRequestMapping;

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
    ) external override whenNotPaused nonReentrant {
        /**
        TODO: Implementation

        Chú ý: Kiểm tra bên Physical NFT, so khớp số NFT quantity với _nftTokenQuantity
        Chỉ cho phép input <= amount của NFT
        */

        // Check white list nft contract
        require(whitelistCollateral[_nftContract] == 1, "NOT_SUPPORT.");

        // Check loan amount
        require(_loanAmount > 0, "ZERO_LOAN_AMOUNT.");

        // Check loan asset
        require(_loanAsset != address(0), "ZERO_ADDRESS_LOAN_ASSET.");

        // Check duration quantity
        require(_expectedDurationQty > 0, "ZERO_DURATION.");

        // Create Collateral Id
        uint256 collateralId = numberCollaterals.current();

        // Transfer token
        PawnNFTLib.safeTranferNFTToken(_nftContract, msg.sender, address(this), _nftTokenId, _nftTokenQuantity);

        // Create collateral
        collaterals[collateralId] = Collateral({
                                                owner: msg.sender,
                                                nftContract: _nftContract,
                                                nftTokenId: _nftTokenId,
                                                loanAmount: _loanAmount,
                                                loanAsset: _loanAsset,
                                                nftTokenQuantity: _nftTokenQuantity,
                                                expectedDurationQty: _expectedDurationQty,
                                                durationType: _durationType,
                                                status: CollateralStatus.OPEN
                                                });
        
        // Update number colaterals
        numberCollaterals.increment();

        emit CollateralEvent(collateralId, collaterals[collateralId],_UID);
                                                
    }

    function withdrawCollateral(
        uint256 _nftCollateralId,
        uint256 _UID
    ) external override whenNotPaused
    {
        Collateral storage _collateral = collaterals[_nftCollateralId];

        // Check owner collateral
        require(_collateral.owner == msg.sender, "NOT_OWNER");

        // Check status collateral
        require(_collateral.status == CollateralStatus.OPEN, "COLLATERAL_NOT_OPEN.");

        // Return NFT token to owner
        PawnNFTLib.safeTranferNFTToken(_collateral.nftContract, address(this), _collateral.owner, _collateral.nftTokenId, _collateral.nftTokenQuantity);

        // Remove relation of collateral and offers
        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_nftCollateralId];
        if (collateralOfferList.isInit == true) {
            for (uint i = 0; i < collateralOfferList.offerIdList.length; i ++) {
                uint256 offerId = collateralOfferList.offerIdList[i];
                Offer storage offer = collateralOfferList.offerMapping[offerId];
                emit CancelOfferEvent(offerId, _nftCollateralId, offer.owner, _UID);
            }
            delete collateralOffersMapping[_nftCollateralId];
        }

        // Update collateral status
        _collateral.status = CollateralStatus.CANCEL;

        emit CollateralEvent(_nftCollateralId, _collateral, _UID);


        delete collaterals[_nftCollateralId];

    }

    /**
    * @dev create offer to collateral
    * @param _nftCollateralId is id collateral
    * @param _repaymentAsset is address token repayment
    * @param _loanToValue is LTV token of loan
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
        LoanDurationType _repaymentCycleType,
        uint256 _UID
    ) external override whenNotPaused
    {
        // Get collateral
        Collateral storage _collateral = collaterals[_nftCollateralId];

        // Check owner collateral
        require(_collateral.owner != msg.sender, "OFFER_OWNED_ASSET"); // You can not offer.

        // Check status collateral
        require(_collateral.status == CollateralStatus.OPEN, "OFFER_NOT_ALLOWED"); // You can not offer collateral.

        // Check approve 
        require(IERC20Upgradeable(_collateral.loanAsset).allowance(msg.sender, address(this)) >= _loanAmount, "INSUFFICIENT_BALANCE"); // You not approve.

        // Check repayment asset
        require(_repaymentAsset != address(0), "INVALID_REPAYMENT"); // Address repayment asset must be different address(0).

        // Check loan amount
        require(_loanToValue > 0, "ZERO_LTV"); // Loan to value must be grean that 0.

        // Check loan amount
        require(_loanAmount > 0, "ZERO_LOAN"); //Loan amount must be grean that 0.

        // Check interest
        require(_interest > 0, "ZERO_INTEREST"); //Interest must be grean that 0.

        // Check duration liquidityThreshold to LTV
        require(_liquidityThreshold > _loanToValue, "INVALID_LIQUIDITY_THRESHOLD"); // Liquidity threshold must be grean that LTV.
        
        // Gennerate Offer Id
        uint256 offerId = numberOffers.current();

        // Get offers of collateral
        CollateralOfferList storage _collateralOfferList = collateralOffersMapping[_nftCollateralId];

        if (!_collateralOfferList.isInit) {
            _collateralOfferList.isInit = true;
        }

        _collateralOfferList.offerMapping[offerId] = Offer({
            owner: msg.sender,
            repaymentAsset: _repaymentAsset,
            loanToValue: _loanToValue,
            loanAmount: _loanAmount,
            interest: _interest,
            duration: _duration,
            status: OfferStatus.PENDING,
            loanDurationType: _loanDurationType,
            repaymentCycleType: _repaymentCycleType,
            liquidityThreshold: _liquidityThreshold
        });
        _collateralOfferList.offerIdList.push(offerId);

        _collateralOfferList.isInit = true;

        // Update number offer
        numberOffers.increment();

        emit OfferEvent(offerId, _nftCollateralId, _collateralOfferList.offerMapping[offerId], _UID);
    }

    function cancelOffer(uint256 _offerId, uint256 _nftCollateralId, uint256 _UID) external override whenNotPaused {
        
        // Get offer
        CollateralOfferList storage _collateralOfferList = collateralOffersMapping[_nftCollateralId];

        // Check Offer Collater isnit
        require(_collateralOfferList.isInit == true, 'COLLATERAL_INIT_FALSE.');

        // Get offer
        Offer storage _offer = _collateralOfferList.offerMapping[_offerId];

        // Check owner offer
        require(_offer.owner == msg.sender, 'NOT_OWNER.');

        // Check status offer
        require(_offer.status == OfferStatus.PENDING, 'NOT_CANCEL.');

        delete _collateralOfferList.offerMapping[_offerId];
        for (uint i = 0; i < _collateralOfferList.offerIdList.length; i ++) {
            if (_collateralOfferList.offerIdList[i] == _offerId) {
                _collateralOfferList.offerIdList[i] = _collateralOfferList.offerIdList[_collateralOfferList.offerIdList.length - 1];
                break;
            }
        }

        delete _collateralOfferList.offerIdList[_collateralOfferList.offerIdList.length - 1];
        emit CancelOfferEvent(_offerId, _nftCollateralId, msg.sender,_UID);
    }

    /** ================================ ACCEPT OFFER ============================= */
    /**
    * @dev accept offer and create contract between collateral and offer
    * @param  _nftCollateralId is id of collateral NFT
    * @param  _offerId is id of offer
    */
    function acceptOffer(
        uint256 _nftCollateralId, 
        uint256 _offerId,
        uint256 _UID
    ) 
        external 
        override 
        whenNotPaused 
    {

        Collateral storage collateral = collaterals[_nftCollateralId];
        // Check owner of collateral
        require(msg.sender == collateral.owner, 'owner');
        // Check for collateralNFT status is OPEN
        require(collateral.status == CollateralStatus.OPEN, 'collateral');

        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_nftCollateralId];
        require(collateralOfferList.isInit == true, 'collateral-offers');
        // Check for offer status is PENDING
        Offer storage offer = collateralOfferList.offerMapping[_offerId];

        require(offer.status == OfferStatus.PENDING, 'unavailable');

        uint256 contractId = createContract(_nftCollateralId, collateral, _offerId, offer.loanAmount, offer.owner, offer.repaymentAsset, offer.interest, offer.loanDurationType, offer.liquidityThreshold);
        Contract storage newContract = contracts[contractId];
        // Change status of offer and collateral
        offer.status = OfferStatus.ACCEPTED;
        collateral.status = CollateralStatus.DOING;

        // Cancel other offer sent to this collateral
        for (uint256 i = 0; i < collateralOfferList.offerIdList.length; i++) {
            uint256 thisOfferId = collateralOfferList.offerIdList[i];
            if (thisOfferId != _offerId) {
                //Offer storage thisOffer = collateralOfferList.offerMapping[thisOfferId];
                emit CancelOfferEvent(thisOfferId, _nftCollateralId,offer.owner,_UID);
                delete collateralOfferList.offerMapping[thisOfferId];
            }
        }
        delete collateralOfferList.offerIdList;
        collateralOfferList.offerIdList.push(_offerId);

        emit LoanContractCreatedEvent(msg.sender, contractId, newContract, _UID);

        // Transfer loan asset to collateral owner
        PawnNFTLib.safeTransfer(newContract.terms.loanAsset, newContract.terms.lender, newContract.terms.borrower, newContract.terms.loanAmount);
    }

    /**
    * @dev create contract between offer and collateral
    * @param  _nftCollateralId is id of Collateral
    * @param  _collateral is Collateral
    * @param  _offerId is id of offer
    * @param  _loanAmount is loan amount 
    * @param  _lender is address of lender
    * @param  _repaymentAsset is address of pay token
    * @param  _interest is interest rate payable
    * @param  _repaymentCycleType is repayment cycle type (WEEK/MONTH)
    * @param  _liquidityThreshold is rate will liquidate the contract
    */
    function createContract (
        uint256 _nftCollateralId,
        Collateral storage _collateral,
        uint256 _offerId,
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
        newContract.nftCollateralId = _nftCollateralId;
        newContract.offerId = _offerId;
        newContract.status = ContractStatus.ACTIVE;
        newContract.lateCount = 0;
        newContract.terms.borrower = _collateral.owner;
        newContract.terms.lender = _lender;
        newContract.terms.nftTokenId = _collateral.nftTokenId;
        newContract.terms.nftCollateralAsset = _collateral.nftContract;
        newContract.terms.nftCollateralAmount = _collateral.nftTokenQuantity;
        newContract.terms.loanAsset = _collateral.loanAsset;
        newContract.terms.loanAmount = _loanAmount;
        newContract.terms.repaymentCycleType = _repaymentCycleType;
        newContract.terms.repaymentAsset = _repaymentAsset;
        newContract.terms.interest = _interest;
        newContract.terms.liquidityThreshold = _liquidityThreshold;
        newContract.terms.contractStartDate = block.timestamp;
        newContract.terms.contractEndDate = block.timestamp + PawnNFTLib.calculateContractDuration(_collateral.durationType, _collateral.expectedDurationQty);
        newContract.terms.lateThreshold = lateThreshold;
        newContract.terms.systemFeeRate = systemFeeRate;
        newContract.terms.penaltyRate = penaltyRate;
        newContract.terms.prepaidFeeRate = prepaidFeeRate;
        ++numberContracts;
    }

    /**
    * @dev Close old Payment Request and Start New Payment Request
    * @param  _contractId is id of contract
    * @param  _remainingLoan is remaining loan of contract
    * @param  _nextPhrasePenalty is fines for the next period
    * @param  _nextPhraseInterest is interest for the next period
    * @param  _dueDateTimestamp is due date timestamp of payment request
    * @param  _paymentRequestType is payment request type 
    * @param  _chargePrepaidFee is prepaid fee payment request
    */
    function closePaymentRequestAndStartNew(
        uint256 _contractId,
        uint256 _remainingLoan,
        uint256 _nextPhrasePenalty,
        uint256 _nextPhraseInterest,
        uint256 _dueDateTimestamp,
        PaymentRequestTypeEnum _paymentRequestType,
        bool _chargePrepaidFee
    ) 
        external 
        override 
        whenNotPaused 
        onlyRole(OPERATOR_ROLE) 
    {
        //Get contract
        Contract storage currentContract = contractMustActive(_contractId);

        // Check if number of requests is 0 => create new requests, if not then update current request as LATE or COMPLETE and create new requests
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        if (requests.length > 0) {
            // not first phrase, get previous request
            PaymentRequest storage previousRequest = requests[requests.length - 1];
            
            // Validate: time must over due date of current payment
            require(block.timestamp >= previousRequest.dueDateTimestamp, 'time-not-over-due');

            // Validate: remaining loan must valid
            require(previousRequest.remainingLoan == _remainingLoan, 'remaining-loan');

            // Validate: Due date timestamp of next payment request must not over contract due date
            require(_dueDateTimestamp <= currentContract.terms.contractEndDate, 'contract-end-date');
            require(_dueDateTimestamp > previousRequest.dueDateTimestamp || _dueDateTimestamp == 0, 'less-than-previous');

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
            require(currentContract.terms.loanAmount == _remainingLoan, 'remaining-loan');

            // Validate: Due date timestamp of next payment request must not over contract due date
            require(_dueDateTimestamp <= currentContract.terms.contractEndDate, 'contract-end-date');
            require(_dueDateTimestamp > currentContract.terms.contractStartDate || _dueDateTimestamp == 0, 'less-than-previous');
            require(block.timestamp < _dueDateTimestamp || _dueDateTimestamp == 0, 'already-over');

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


    /**
    * @dev get Contract must active
    * @param  _contractId is id of contract
    */
    function contractMustActive(uint256 _contractId) internal view returns (Contract storage _contract) {
        // Validate: Contract must active
        _contract = contracts[_contractId];
        require(_contract.status == ContractStatus.ACTIVE, 'contract-not-active');
    }

    /**
    * @dev Perform contract liquidation
    * @param  _contractId is id of contract
    * @param  _reasonType is type of reason for liquidation of the contract
    */
    function _liquidationExecution(
        uint256 _contractId,
        ContractLiquidedReasonType _reasonType
    ) internal {
        Contract storage _contract = contracts[_contractId];

        // Execute: update status of contract to DEFAULT, collateral to COMPLETE
        _contract.status = ContractStatus.DEFAULT;
        PaymentRequest[] storage _paymentRequests = contractPaymentRequestMapping[_contractId];
        PaymentRequest storage _lastPaymentRequest = _paymentRequests[_paymentRequests.length - 1];
        _lastPaymentRequest.status = PaymentRequestStatusEnum.DEFAULT;
        Collateral storage _collateral = collaterals[_contract.nftCollateralId];
        _collateral.status = CollateralStatus.COMPLETED;           

        // Emit Event ContractLiquidedEvent
        emit ContractLiquidedEvent(
            _contractId,
            0,
            0,
            _reasonType
        );
        // Transfer to lender collateral
        PawnNFTLib.safeTranferNFTToken(_contract.terms.nftCollateralAsset, address(this), _contract.terms.lender,_contract.terms.nftTokenId, _contract.terms.nftCollateralAmount );
    }

    /**
    * @dev return collateral to borrower and close contract
    * @param  _contractId is id of contract
    */
    function _returnCollateralToBorrowerAndCloseContract(
        uint256 _contractId
    ) internal 
    {
        Contract storage _contract = contracts[_contractId];
        Collateral storage _collateral = collaterals[_contract.nftCollateralId];

        // Execute: Update status of contract to COMPLETE, collateral to COMPLETE
        _contract.status = ContractStatus.COMPLETED;
        PaymentRequest[] storage _paymentRequests = contractPaymentRequestMapping[_contractId];
        PaymentRequest storage _lastPaymentRequest = _paymentRequests[_paymentRequests.length - 1];
        _lastPaymentRequest.status = PaymentRequestStatusEnum.COMPLETE;
        _collateral.status = CollateralStatus.COMPLETED;

        // Emit Event ContractLiquidedEvent
        emit LoanContractCompletedEvent(_contractId);

        // Execute: Transfer collateral to borrower
        PawnNFTLib.safeTranferNFTToken(_contract.terms.nftCollateralAsset,  address(this), _contract.terms.borrower, _contract.terms.nftTokenId,  _contract.terms.nftCollateralAmount );

    }

    /**
    * @dev the borrower repays the debt
    * @param  _contractId is id of contract
    * @param  _paidPenaltyAmount is paid penalty amount
    * @param  _paidInterestAmount is paid interest amount
    * @param  _paidLoanAmount is paid loan amount
    */
    function repayment(
        uint256 _contractId,
        uint256 _paidPenaltyAmount,
        uint256 _paidInterestAmount,
        uint256 _paidLoanAmount
    ) external override whenNotPaused 
    {
        // Get contract & payment request
        Contract storage _contract = contractMustActive(_contractId);
        PaymentRequest[] storage requests = contractPaymentRequestMapping[_contractId];
        require(requests.length > 0, 'payment-request');
        PaymentRequest storage _paymentRequest = requests[requests.length - 1];
        
        // Validation: Contract must not overdue
        require(block.timestamp <= _contract.terms.contractEndDate, 'contract-over');

        // Validation: current payment request must active and not over due
        require(_paymentRequest.status == PaymentRequestStatusEnum.ACTIVE, 'not-active');
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
        uint256 _feePenalty = PawnNFTLib.calculateSystemFee(_paidPenaltyAmount, _contract.terms.systemFeeRate, ZOOM);
        uint256 _feeInterest = PawnNFTLib.calculateSystemFee(_paidInterestAmount, _contract.terms.systemFeeRate, ZOOM);

        uint256 _prepaidFee = 0;
        if (_paymentRequest.chargePrepaidFee) {
            _prepaidFee = PawnNFTLib.calculateSystemFee(_paidLoanAmount, _contract.terms.prepaidFeeRate, ZOOM);
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
        if (_paymentRequest.remainingLoan == 0 && _paymentRequest.remainingPenalty == 0 && _paymentRequest.remainingInterest == 0)
            _returnCollateralToBorrowerAndCloseContract(_contractId);

        uint256 _totalFee;
        uint256 _totalTransferAmount;

        if (_paidPenaltyAmount + _paidInterestAmount > 0) {
            // Transfer fee to fee wallet
            _totalFee = _feePenalty + _feeInterest;
            PawnNFTLib.safeTransfer(_contract.terms.repaymentAsset, msg.sender, feeWallet, _totalFee);

            // Transfer penalty and interest to lender except fee amount
            _totalTransferAmount = _paidPenaltyAmount + _paidInterestAmount - _feePenalty - _feeInterest;
            PawnNFTLib.safeTransfer(_contract.terms.repaymentAsset, msg.sender, _contract.terms.lender, _totalTransferAmount);   
        }

        if (_paidLoanAmount > 0) {
            // Transfer loan amount and prepaid fee to lender
            _totalTransferAmount = _paidLoanAmount + _prepaidFee;
            PawnNFTLib.safeTransfer(_contract.terms.loanAsset, msg.sender, _contract.terms.lender, _totalTransferAmount);
        }
    }
    
    function collateralRiskLiquidationExecution(
        uint256 _contractId,
        uint256 _collateralPerRepaymentTokenExchangeRate,
        uint256 _collateralPerLoanAssetExchangeRate
    ) 
        external 
        override 
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
    //     // Validate: Contract must active
    //     Contract storage _contract = contractMustActive(_contractId);
    //     Collateral storage _collateral = collaterals[_contract.nftCollateralId];

    //     //get Address of EvaluationContract 
    //     (address _evaluationContract, uint256 _evaluationId ) = DFY_Physical_NFTs(_collateral.nftContract).tokenIdOfEvaluation(_collateral.nftTokenId);
        
    //     //get price of Evaluation from EvaluationContract
    //     uint256 price = AssetEvaluation(_evaluationContract).tokenIdByEvaluation(_collateral.nftTokenId)[0];
        
    //     (uint256 remainingRepayment, uint256 remainingLoan) = calculateRemainingLoanAndRepaymentFromContract(_contractId, _contract);
    //     uint256 valueOfRemainingRepayment = (_collateralPerRepaymentTokenExchangeRate * remainingRepayment) / ZOOM;
    //     uint256 valueOfRemainingLoan = (_collateralPerLoanAssetExchangeRate * remainingLoan) / ZOOM;
    //     uint256 valueOfCollateralLiquidationThreshold = price * _contract.terms.liquidityThreshold / (100 * ZOOM);

    //     require(valueOfRemainingLoan + valueOfRemainingRepayment >= valueOfCollateralLiquidationThreshold, 'under-threshold');

    //     // Execute: call internal liquidation
    //     _liquidationExecution(_contractId, ContractLiquidedReasonType.RISK);
    }

    /**
    * @dev liquidate the contract if the borrower has not paid in full at the end of the contract
    * @param _contractId is id of contract
    */
    function lateLiquidationExecution(uint256 _contractId) external override whenNotPaused {

        // Validate: Contract must active
        Contract storage _contract = contractMustActive(_contractId);

        // validate: contract have lateCount == lateThreshold
        require(_contract.lateCount >= _contract.terms.lateThreshold, 'not-reach');

        // Execute: call internal liquidation
        _liquidationExecution(_contractId, ContractLiquidedReasonType.LATE);
    }

    /**
    * @dev liquidate the contract if the borrower has not paid in full at the end of the contract
    * @param _contractId is id of contract
    */
    function notPaidFullAtEndContractLiquidation(uint256 _contractId) external override whenNotPaused{

        Contract storage _contract = contractMustActive(_contractId);
        // validate: current is over contract end date
        require(block.timestamp >= _contract.terms.contractEndDate, 'not-over-due');

        // validate: remaining loan, interest, penalty haven't paid in full
        (
            uint256 remainingRepayment, 
            uint256 remainingLoan
        ) = calculateRemainingLoanAndRepaymentFromContract(_contractId, _contract);
        
        require(remainingRepayment + remainingLoan > 0, 'paid-full');
        
        // Execute: call internal liquidation
        _liquidationExecution(_contractId, ContractLiquidedReasonType.LATE);
    }

    function calculateRemainingLoanAndRepaymentFromContract(
        uint256 _contractId,
        Contract storage _contract
    ) 
        internal 
        view 
        returns (
            uint256 remainingRepayment, 
            uint256 remainingLoan
        )
    {
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
}