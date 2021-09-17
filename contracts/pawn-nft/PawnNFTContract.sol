// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "../evaluation/DFY-AccessControl.sol";
import "../evaluation/DFY_Physical_NFTs.sol";
import "../evaluation/EvaluationContract.sol";
import "../evaluation/IBEP20.sol";
import "./IPawnNFT.sol";

contract PawnNFTContract is 
    IPawnNFT, 
    Initializable, 
    UUPSUpgradeable,
    OwnableUpgradeable,
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
    address public feeWallet = address(this);
    uint256 public penaltyRate;
    uint256 public systemFeeRate; 
    uint256 public lateThreshold;
    uint256 public prepaidFeeRate;
    uint256 public ZOOM;  
    bool public initialized = false;
    address public admin;

    DFY_Physical_NFTs dfy_physical_nfts;
    AssetEvaluation assetEvaluation;



    function initialize(uint256 _zoom) public initializer {
        __ERC1155Holder_init();
        __DFYAccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        ZOOM = _zoom;
        initialized = true;
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
        safeTransfer(_token, address(this), admin, calculateAmount(_token, address(this)));
    }

    /**
    * @dev safe transfer BNB or ERC20
    * @param  asset is address of the cryptocurrency to be transferred
    * @param  from is the address of the transferor
    * @param  to is the address of the receiver
    * @param  amount is transfer amount
    */
    function safeTransfer(
        address asset, 
        address from, 
        address to, 
        uint256 amount
    ) internal {
        if (asset == address(0)) {
            require(from.balance >= amount, 'not-enough-balance');
            // Handle BNB            
            if (to == address(this)) {
                // Send to this contract
            } else if (from == address(this)) {
                // Send from this contract
                (bool success, ) = to.call{value:amount}('');
                require(success, 'fail-transfer-bnb');
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
                require(IERC20(asset).allowance(from, address(this)) >= amount, 'not-enough-allowance');
                IERC20(asset).safeTransferFrom(from, to, amount);
            }
            require(IERC20(asset).balanceOf(to) - amount == prebalance, 'not-transfer-enough');
        }
    }

    function safeTranferNFTToken(address _nftToken, address _from, address _to, uint256 _id, uint256 _amount) internal {
        
        // check address token
        require(_nftToken != address(0), "Address token must be different address(0).");

        // check address from
        require(_from != address(0), "Address from must be different address(0).");

        // check address from
        require(_to != address(0), "Address to must be different address(0).");

        // Check approve
        require(IERC1155Upgradeable(_nftToken).isApprovedForAll(_from, address(this)), "You dont approve token.");

        // Check amount token
        require(_amount > 0, "Amount must be grean than 0.");

        // Check balance of from,
        require(IERC1155Upgradeable(_nftToken).balanceOf(_from,_id) >= _amount, "Your balance not enough.");

        // Transfer token
        IERC1155Upgradeable(_nftToken).safeTransferFrom(_from,_to,_id,_amount,"");
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
        require(whitelistCollateral[_nftContract] == 1, "Not support collateral.");

        // Check NFT token id
        require(_nftTokenId >= 0, "Token id dose not exists.");

        // Check loan amount
        require(_loanAmount > 0, "Loan amount must be greater than 0.");

        // Check loan asset
        require(_loanAsset != address(0), "Address loan must be different address(0).");

        // Check quantity NFT token
        require(_nftTokenQuantity > 0, "Token quantity must be grean than 0.");

        // Check duration quantity
        require(_expectedDurationQty > 0, "Duration quantity must be grean than 0.");

        // Create Collateral Id
        uint256 collateralId = numberCollaterals.current();

        // Transfer token
        safeTranferNFTToken(_nftContract, msg.sender, address(this), _nftTokenId, _nftTokenQuantity);

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
        uint256 _nftCollateralId
    ) external override 
    {

    }

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
        // Check NFT collateral id
        require(_nftCollateralId >= 0, "NFT collateral does not exists.");

        // Check repayment asset
        require(_repaymentAsset != address(0), "Address repayment asset must be different address(0).");

        // Check loan amount
        require(_loanToValue > 0, "Loan to value must be grean that 0.");

        // Check loan amount
        require(_loanAmount > 0, "Loan amount must be grean that 0.");

        // Check interest
        require(_interest > 0, "Interest must be grean that 0.");

        // Check duration liquidityThreshold
        require(_liquidityThreshold > 0, "Liquidity threshold must be grean that 0.");

        // Check duration liquidityThreshold to LTV
        require(_liquidityThreshold > _loanToValue, "Liquidity threshold must be grean that LTV.");

        // Check loan duration type;
        require(_loanDurationType == LoanDurationType.WEEK || _loanDurationType == LoanDurationType.MONTH, "Loan duration type does not exists.");

        // Check repayment cycle type
        require(_repaymentCycleType == LoanDurationType.WEEK || _repaymentCycleType == LoanDurationType.MONTH, "Loan duration type does not exists.");

        // Get collateral
        Collateral storage _collateral = collaterals[_nftCollateralId];

        // Check owner collateral
        require(_collateral.owner != msg.sender, "You can not offer.");

        // Check status collateral
        require(_collateral.status == CollateralStatus.OPEN, "You can not offer collateral.");

        // Check approve 
        require(IERC20Upgradeable(_collateral.loanAsset).allowance(msg.sender, address(this)) >= _loanAmount, "You not approve.");
        
        // Gennerate Offer Id
        uint256 offerId = numberOffers.current();

        // Get offers of collateral
        CollateralOfferList storage _collateralOfferList = collateralOffersMapping[_nftCollateralId];

        if (!_collateralOfferList.isInit) {
            _collateralOfferList.isInit = true;
        }

        // Gennerate offer id
        uint256 offerId = numberOffers.current();

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

    function cancelOffer(
        uint256 _offerId,
        uint256 _nftCollateralId
    ) external override 
    {

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
    ) external override whenNotPaused {

        Collateral storage collateral = collaterals[_nftCollateralId];
        // Check owner of collateral
        require(msg.sender == collateral.owner, 'owner');
        // Check for collateralNFT status is OPEN
        require(collateral.status == CollateralStatus.OPEN, 'collateral');

        CollateralOfferList storage collateralOfferList = collateralOffersMapping[_nftCollateralId];
        require(collateralOfferList.isInit == true, 'collateral-offers');
        // Check for offer status is PENDING
        Offer storage offer = collateralOfferList.offerMapping[_offerId];
        require(offer.isInit == true, 'not-sent');
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
                Offer storage thisOffer = collateralOfferList.offerMapping[thisOfferId];
                emit OfferEvent(i, _nftCollateralId, thisOffer);
                delete collateralOfferList.offerMapping[thisOfferId];
            }
        }
        delete collateralOfferList.offerIdList;
        collateralOfferList.offerIdList.push(_offerId);

        emit LoanContractCreatedEvent(msg.sender, contractId, newContract, _UID);

        // Transfer loan asset to collateral owner
        safeTransfer(newContract.terms.loanAsset, newContract.terms.lender, newContract.terms.borrower, newContract.terms.loanAmount);
    }

    /**
    * @dev create contract between offer and collateral
    * @param  _nftCollateralId is id of Collateral
    * @param  _collateral is Collateral
    * @param  _offerId is offer
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
        int256 _offerId,
        uint256 _loanAmount,
        address _lender,
        address _repaymentAsset,
        uint256 _interest,
        LoanDurationType _repaymentCycleType,
        uint256 _liquidityThreshold
    ) internal returns (uint256 _idx) {
        
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
        newContract.terms.contractEndDate = block.timestamp + calculateContractDuration(_collateral.durationType, _collateral.expectedDurationQty);
        newContract.terms.lateThreshold = lateThreshold;
        newContract.terms.systemFeeRate = systemFeeRate;
        newContract.terms.penaltyRate = penaltyRate;
        newContract.terms.prepaidFeeRate = prepaidFeeRate;
        ++numberContracts;
    }

    /**
    * @dev Calculate the duration of the contract
    * @param  durationType is loan duration type of contract (WEEK/MONTH)
    * @param  duration is duration of contract
    */
    function calculateContractDuration(
        LoanDurationType durationType, 
        uint256 duration
    ) internal pure returns (uint256 inSeconds){
        if (durationType == LoanDurationType.WEEK) {
            inSeconds = 7 * 24 * 3600 * duration;
        } else {
            inSeconds = 30 * 24 * 3600 * duration; 
        }
    }

    /**
    * @dev Calculate balance of wallet address 
    * @param  _token is address of token 
    * @param  from is address wallet
    */
    function calculateAmount(
        address _token, 
        address from
    ) internal view returns (uint256 _amount) {
        if (_token == address(0)) {
            // BNB
            _amount = from.balance;
        } else {
            // ERC20
            _amount = IERC20(_token).balanceOf(from);
        }
    }

    /**
    * @dev Calculate fee of system
    * @param  amount amount charged to the system
    * @param  feeRate is system fee rate
    */
    function calculateSystemFee(
        uint256 amount, 
        uint256 feeRate
    ) internal view returns (uint256 feeAmount) {
        feeAmount = (amount * feeRate) / (ZOOM * 100);
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
    ) external override whenNotPaused onlyOperator {
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
    function contractMustActive(
        uint256 _contractId
    ) internal view returns (Contract storage _contract) {
        // Validate: Contract must active
        _contract = contracts[_contractId];
        require(_contract.status == ContractStatus.ACTIVE, 'contract-not-active');
    }

    /**
    * @dev Perform contract liquidation
    * @param  _contractId is id of contract
    * @param  _reasonType is id of contract
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
        Collateral storage _collateral = collaterals[_contract.collateralId];
        _collateral.status = CollateralStatus.COMPLETED;           

        // Emit Event ContractLiquidedEvent & PaymentRequest event
        emit ContractLiquidedEvent(
            _contractId,
            0,
            0,
            _reasonType
        );
        // Transfer to lender collateral
        safeTranferNFTToken(_contract.terms.nftCollateralAsset, address(this), _contract.terms.lender, _contract.terms.nftCollateralAmount );
    }

    function _returnCollateralToBorrowerAndCloseContract(
        uint256 _contractId
    ) internal {
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
    ) external override whenNotPaused {
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
        uint256 _feePenalty = calculateSystemFee(_paidPenaltyAmount, _contract.terms.systemFeeRate);
        uint256 _feeInterest = calculateSystemFee(_paidInterestAmount, _contract.terms.systemFeeRate);

        uint256 _prepaidFee = 0;
        if (_paymentRequest.chargePrepaidFee) {
            _prepaidFee = calculateSystemFee(_paidLoanAmount, _contract.terms.prepaidFeeRate);
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
            safeTransfer(_contract.terms.repaymentAsset, msg.sender, feeWallet, _feePenalty + _feeInterest);

            // Transfer penalty and interest to lender except fee amount
            safeTransfer(_contract.terms.repaymentAsset, msg.sender, _contract.terms.lender, _paidPenaltyAmount + _paidInterestAmount - _feePenalty - _feeInterest);   
        }

        if (_paidLoanAmount > 0) {
            // Transfer loan amount and prepaid fee to lender
            safeTransfer(_contract.terms.loanAsset, msg.sender, _contract.terms.lender, _paidLoanAmount + _prepaidFee);
        }
    }
    
    function collateralRiskLiquidationExecution(
        uint256 _contractId,
        uint256 _collateralPerRepaymentTokenExchangeRate,
        uint256 _collateralPerLoanAssetExchangeRate
    ) external override {
        //uint256 valueOfCollateralLiquidationThreshold = _contract.terms.nftCollateralEvaluatedValue * _contract.terms.liquidityThreshold / (100 * ZOOM);
    }

    /**
    * @dev liquidate the contract if the borrower has not paid in full at the end of the contract
    * @param _contractId is id of contract
    */
    function lateLiquidationExecution(
        uint256 _contractId
    ) external override {
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
    function notPaidFullAtEndContractLiquidation(
        uint256 _contractId
    ) external override {
        Contract storage _contract = contractMustActive(_contractId);
        // validate: current is over contract end date
        require(block.timestamp >= _contract.terms.contractEndDate, 'not-over-due');

        // validate: remaining loan, interest, penalty haven't paid in full
        (uint256 remainingRepayment, uint256 remainingLoan) = calculateRemainingLoanAndRepaymentFromContract(_contractId, _contract);
        require(remainingRepayment + remainingLoan > 0, 'paid-full');
        
        // Execute: call internal liquidation
        _liquidationExecution(_contractId, ContractLiquidedReasonType.LATE);
    }
}