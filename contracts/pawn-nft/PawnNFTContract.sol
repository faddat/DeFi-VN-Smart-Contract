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

    function acceptOffer(
        uint256 _nftCollateralId, 
        uint256 _offerId,
        uint256 _UID
    ) external override
    {

    }

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