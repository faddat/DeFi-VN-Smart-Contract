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
    ) external override
    {
    }

    /**
    * @dev safe transfer BNB or ERC20
    * @param  asset is address of the cryptocurrency to be transferred
    * @param  from is the address of the transferor
    * @param  to is the address of the receiver
    * @param  amount is transfer amount
    */
    function safeTransfer(address asset, address from, address to, uint256 amount) internal {
    } 

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
    }

    /**
    * @dev calculate balance of wallet address 
    * @param  _token is address of token 
    * @param  from is address wallet
    */
    function calculateAmount(address _token, address from) 
    internal view returns (uint256 _amount) {
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
        // feeAmount = (amount * feeRate) / (ZOOM * 100);
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

    function _liquidationExecution(
        uint256 _contractId,
        ContractLiquidedReasonType _reasonType
    ) internal {

    }

    function _returnCollateralToBorrowerAndCloseContract(
        uint256 _contractId
    ) internal {
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