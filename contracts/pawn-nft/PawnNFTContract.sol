// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../evaluation/DFY-AccessControl.sol";
import "../evaluation/DFY_Physical_NFTs.sol";
import "../evaluation/EvaluationContract.sol";
import "../evaluation/IBEP20.sol";
import "./IPawnNFT.sol";

contract PawnNFTContract is 
    Ownable, Pausable,
    ReentrancyGuard,
    IPawnNFT, 
    Initializable, 
    UUPSUpgradeable, 
    ERC1155HolderUpgradeable, 
    PausableUpgradeable, 
    DFYAccessControl
{

    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint;
    using CountersUpgradeable for CountersUpgradeable.Counter;

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

    DFY_Physical_NFTs dfy_physical_nfts;
    AssetEvaluation assetEvaluation;



    function initialize() public initializer {
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
    uint256 public numberCollaterals;

    // Mapping collateralId => Collateral
    mapping (uint256 => Collateral) public collaterals;

    // Total offer
    uint256 public numberOffers;
    
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
    ) external override {
        /**
        TODO: Implementation

        Chú ý: Kiểm tra bên Physical NFT, so khớp số NFT quantity với _nftTokenQuantity
        Chỉ cho phép input <= amount của NFT
        */
    }

    function withdrawCollateral(
        uint256 _nftCollateralId
    ) external override 
    {

    }

    uint256 public numberOffers;
    struct CollateralOfferList {
        mapping (uint256 => Offer) offerMapping;
        uint256[] offerIdList;
        bool isInit;
    }
    mapping (uint256 => CollateralOfferList) public collateralOffersMapping;
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
    ) external override 
    {

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
    uint256 public numberContracts;    
    mapping (uint256 => Contract) public contracts;
    function acceptOffer(
        uint256 _nftCollateralId, 
        uint256 _offerId,
        uint256 _UID
    ) external override
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
        * @dev safe transfer BNB or ERC20
        * @param  asset is address of the cryptocurrency to be transferred
        * @param  from is the address of the transferor
        * @param  to is the address of the receiver
        * @param  amount is transfer amount
    */
    function safeTransfer(address asset, address from, address to, uint256 amount) internal {
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

    /**
        * @dev create contract between offer and collateral
        * @param  durationType is loan duration type of contract (WEEK/MONTH)
        * @param  duration is duration of contract
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
    )
    internal
    returns (uint256 _idx)
    {
        address evaluationContract = dfy_physical_nfts.tokenIdOfEvaluation[Collateral.nftTokenId].evaluationContract;
        
        assetEvaluation = AssetEvaluation(evaluationContract);
        
        uint256 evaluationAmount = assetEvaluation.tokenIdByEvaluation[Collateral.nftTokenId].price;
        
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
        newContract.terms.nftCollateralAmount = evaluationAmount;
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
        * @dev calculate contract duration
        * @param  durationType is loan duration type of contract (WEEK/MONTH)
        * @param  duration is duration of contract
    */
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

    /**
        * @dev calculate balance of wallet address 
        * @param  _token is address of token 
        * @param  from is address wallet
    */
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

    /**
        * @dev calculate fee of system
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
        * @dev close old Payment Request and Start New Payment Request
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
    ) external override 
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

    }

     /**
        * @dev get Contract must active
        * @param  _contractId is id of contract
    */
    function contractMustActive(
        uint256 _contractId
    ) internal view 
    returns (Contract storage _contract) {
        // Validate: Contract must active
        _contract = contracts[_contractId];
        require(_contract.status == ContractStatus.ACTIVE, 'contract-not-active');
    }


    function repayment(
        uint256 _contractId,
        uint256 _paidPenaltyAmount,
        uint256 _paidInterestAmount,
        uint256 _paidLoanAmount
    ) external override
    {

    }
    
    function collateralRiskLiquidationExecution(
        uint256 _contractId,
        uint256 _collateralPerRepaymentTokenExchangeRate,
        uint256 _collateralPerLoanAssetExchangeRate
    ) external override {
        //uint256 valueOfCollateralLiquidationThreshold = _contract.terms.nftCollateralEvaluatedValue * _contract.terms.liquidityThreshold / (100 * ZOOM);
    }

    function lateLiquidationExecution(
        uint256 _contractId
    ) external override
    {
        
    }

    function notPaidFullAtEndContractLiquidation(
        uint256 _contractId
    ) external override
    {
        
    }
}