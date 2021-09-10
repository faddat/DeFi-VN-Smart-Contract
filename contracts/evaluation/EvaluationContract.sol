// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
// import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./DFY-AccessControl.sol";
import "./DFY_Physical_NFTs.sol";
import "./IBEP20.sol";



contract AssetEvaluation is UUPSUpgradeable,ERC1155HolderUpgradeable, PausableUpgradeable, DFYAccessControl{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint;

    // Total asset
    CountersUpgradeable.Counter public totalAssets;

    // DFY Token;
    IBEP20 public ibepDFY;

    // NFT Token;
    DFY_Physical_NFTs public dfy_physical_nfts;

    // Address admin
    address private addressAdmin;

    // Assuming _assetBaseUri = "https://ipfs.io/ipfs"
    string private _assetBaseUri;

    // Mapping list asset
    // AssetId => Asset
    mapping (uint256 => Asset) public assetList;

    // Mapping from creator to asset
    // Creator => listAssetId
    mapping (address => uint256[]) public assetListByCreator; 

    // Mapping from creator address to assetId in his/her possession
    // Creator => (assetId => bool)
    mapping (address => mapping (uint256 => bool)) private _assetsOfCreator;

    // Total evaluation
    CountersUpgradeable.Counter public totalEvaluation;

    // Mapping list evaluation
    // EvaluationId => evaluation
    mapping (uint256 => Evaluation) public evaluationList;

    // Mapping from asset to list evaluation
    // AssetId => listEvaluationId
    mapping (uint256 => uint256[]) public evaluationByAsset;

    // Mapping from evaluator to evaluation
    // Evaluator => listEvaluation
    mapping (address => uint256[]) public evaluationListByEvaluator;

    // Mapping tokenId to asset
    // TokenId => asset
    mapping (uint256 => Asset) public tokenIdByAsset;

    // Mapping tokenId to evaluation
    // TokenId => evaluation
    mapping (uint256 => Evaluation) public tokenIdByEvaluation;

    function initialize(
        string memory _uri,
        address _dfy1155_physical_nft_address,
        address _ibep20_DFY_address
    ) public initializer {
        __ERC1155Holder_init();
        __DFYAccessControl_init();
        __Pausable_init();

        _setAssetBaseURI(_uri);

        _setNFTAddress(_dfy1155_physical_nft_address);

        _setTokenIBEP20Address(_ibep20_DFY_address);

        _setAddressAdmin(msg.sender);
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Enum status asset
    enum AssetStatus {OPEN, EVALUATED, NFT_CREATED}

    // Asset
    struct Asset {
        string assetDataCID;
        address creator;
        AssetStatus status;
    }

    // Enum status evaluation
    enum EvaluationStatus {EVALUATED, EVALUATION_ACCEPTED, EVALUATION_REJECTED, NFT_CREATED}

    // Evaluation
    struct Evaluation {
        uint256 assetId;
        address evaluator;
        address token;
        uint256 price;
        EvaluationStatus status;
    }

    event AssetCreated (
        uint256 assetId,
        Asset asset
    );

    event AssetEvaluated(
        uint256 evaluationId,
        uint256 assetId,
        Asset asset,
        Evaluation evaluation
    );

    event ApproveEvaluator(
        address evaluator
    );

    modifier OnlyEOA() {
        require(!msg.sender.isContract(), "Caller address must not be a contract address.");
        _;
    }

    // Function set base uri
    function setBaseURI(string memory _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAssetBaseURI(_uri);
    }

    // Function set asset base uri
    function _setAssetBaseURI(string memory _uri) internal {
        require(bytes(_uri).length > 0, "Asset data URI must not be empty.");
        _assetBaseUri = _uri;
    }

    // Function  
    function assetURI(uint256 _assetId) external view returns (string memory){
        return bytes(_assetBaseUri).length > 0 ? string(abi.encodePacked(_assetBaseUri, assetList[_assetId].assetDataCID)) : "";
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155ReceiverUpgradeable, AccessControlUpgradeable) returns (bool){
        return super.supportsInterface(interfaceId);
    }


    /**
    * @dev Set the current NFT contract address to a new address
    * @param _newAddress is the address of the new NFT contract
    */
    function setNftContractAddress(address _newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Verify if the new address is a contract or not
        require(_newAddress.isContract(), "Input address is not a contract address.");
        
        _setNFTAddress(_newAddress);
    }

    function _setNFTAddress(address _newAddress) internal {
        dfy_physical_nfts = DFY_Physical_NFTs(_newAddress);
    }

    /**
    * @dev Set the current NFT contract address to a new address
    * @param _newAddress is the address of the new NFT contract
    */
    function setTokenIBEP20Address(address _newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Verify if the new address is a contract or not
        require(_newAddress.isContract(), "Input address is not a contract address.");
        
        _setTokenIBEP20Address(_newAddress);
    }

    function _setTokenIBEP20Address(address _newAddress) internal {
        ibepDFY = IBEP20(_newAddress);
    }

    
    function _setAddressAdmin(address _newAddress) internal {
        addressAdmin = _newAddress;
    }

    /**
    * @dev Asset creation request by customer
    * @dev msg.sender is the asset creator's address
    * @param _cid is the CID string of the asset's JSON file stored on IFPS
    */
    function createAssetRequest(string memory _cid) external OnlyEOA {
        // TODO: Require validation of msg.sender
        // msg.sender must not be a contract address

        // Require length _cid >0
        require(bytes(_cid).length > 0, "Asset data CID must not be empty.");

        // Create asset id
        uint256 _assetId = totalAssets.current();

        // Add asset from asset list
        assetList[_assetId] =  Asset({
                                assetDataCID: _cid,
                                creator: msg.sender,
                                status: AssetStatus.OPEN
                            });
        
        // Add asset id from list asset id of owner
        assetListByCreator[msg.sender].push(_assetId);

        // Update status from asset id of owner 
        _assetsOfCreator[msg.sender][_assetId] = true;

        // Update total asset
        totalAssets.increment();

        emit AssetCreated(_assetId, assetList[_assetId]);
    }

    /**
    * @dev Return a list of asset created by _creator 
    * @param _creator address representing the creator / owner of the assets.
    */
    function getAssetsByCreator(address _creator) external view returns (uint[] memory) {
        // TODO: Input data validation
        require(_creator != address(0), "There is no asset associated with the zero address");

        return assetListByCreator[_creator];
    }

    // Function check asset of creator
    function _isAssetOfCreator(address _creator, uint256 _assetId) internal view returns (bool) {
        return _assetsOfCreator[_creator][_assetId];
    }

    /**
    * @dev Asset evaluation by evaluator
    * @dev msg.sender is evaluator address
    * @param _assetId is the ID of the asset in AssetList
    * @param _currency is address of the token who create the asset
    * @param _price value of the asset, given by the Evaluator
    */
    function evaluateAsset(uint256 _assetId, address _currency, uint256 _price) external OnlyEOA onlyRole(EVALUATOR_ROLE) {
        // TODO
        // Require validation of msg.sender
        require(msg.sender != address(0),"Calling from the zero address.");

        // Require address currency is contract
        require(_currency.isContract(), "Address token is not defined.");

        // Require validation is creator asset
        require(!_isAssetOfCreator(msg.sender, _assetId), "You cant evaluted your asset.");

        // Require validation of asset via _assetId
        require(_assetId >=0 ,"Invalid asset or asset does not exist.");

        // Get asset to asset id;
        Asset memory _asset = assetList[_assetId];

        // Check asset is exists
        require(bytes(_asset.assetDataCID).length >0, "Asset does not exists.");

        // check status asset
        require(_asset.status == AssetStatus.OPEN, "This asset evaluated.");

        // Create evaluation id
        uint256 _evaluationId = totalEvaluation.current();
        
        // Add evaluation to evaluationList 
        evaluationList[_evaluationId] = Evaluation({
                                                assetId: _assetId,
                                                evaluator: msg.sender,
                                                token: _currency,
                                                price: _price,
                                                status: EvaluationStatus.EVALUATED
                                            });
        
        
        // Add evaluation id to list evaluation of asset
        evaluationByAsset[_assetId].push(_evaluationId);

        // Add evaluation id to list evaluation of evaluator 
        evaluationListByEvaluator[msg.sender].push(_evaluationId);

        // Update total evaluation
        totalEvaluation.increment();

        emit AssetEvaluated(_evaluationId,_assetId,_asset,evaluationList[_evaluationId]);
    }

    /** 
    * @dev Customer accept evaluation data from evaluator
    * @param _assetId is the ID of the asset in AssetList
    * @param _evaluationId is the look up index of the Evaluation data in EvaluationsByAsset list
    */
    function acceptOrRejectEvaluation(uint256 _assetId,uint256 _evaluationId, uint8 _evalutionStatus) external OnlyEOA{
        
        // Check creator is address 0
        require(msg.sender!=address(0),"Address creator must be different from 0.");

        // Check asset id
        require(_assetId >=0 ,"Invalid asset or asset does not exist.");

        // Check evaluation index
        require(_evaluationId >=0 ,"Invalid evaluation or evaluation does not exist.");

        // Get asset to asset id;
        Asset memory _asset = assetList[_assetId];

        // Check asset to creator
        require(_asset.creator == msg.sender, "You can only accept or reject your evaluation asset");

        // Check evaluation status
        require(_evalutionStatus > 0 && _evalutionStatus < 3, "You can on ly choose status EVALUATION_ACCEPTED or EVALUATION_REJECTED.");

        // Check asset is exists
        require(_asset.status == AssetStatus.OPEN, "Asset does not allow evaluation.");

        // approve an evaluation by looking for its index in the array.
        Evaluation memory _evaluation = evaluationList[_evaluationId];
        
        require(_evaluation.status == EvaluationStatus.EVALUATED,"You cant accept or reject this evaluation.");

        if(_evalutionStatus == 1){
            _acceptEvaluation(_assetId,_evaluationId );
        }else{
            _rejectEvaluation(_assetId, _evaluationId);
        }
       
    }

    function _acceptEvaluation(uint256 _assetId, uint256 _evaluationId) internal {

        Asset storage _asset = assetList[_assetId];

        Evaluation storage _evaluation = evaluationList[_evaluationId];

        _evaluation.status = EvaluationStatus.EVALUATION_ACCEPTED;
        
        // reject all other evaluation of asset
        for(uint i = 0; i < evaluationByAsset[_assetId].length; i++) {
            if(evaluationByAsset[_assetId][i] != _evaluationId) {
                uint256  _evaluationIdReject = evaluationByAsset[_assetId][i];
                _rejectEvaluation(_assetId, _evaluationIdReject);
            }
        }

        _asset.status = AssetStatus.EVALUATED;

         emit AssetEvaluated(_evaluationId, _assetId, _asset , _evaluation);
    }

    function _rejectEvaluation(uint256 _assetId, uint256 _evaluationId) internal {

        Asset storage _asset = assetList[_assetId];

        Evaluation storage _evaluation = evaluationList[_evaluationId];
        
        _evaluation.status = EvaluationStatus.EVALUATION_REJECTED;

        emit AssetEvaluated(_evaluationId,_assetId, _asset, _evaluation);
    }

    
    /**
    * @dev After an evaluation is approved, the Evaluator who submit
    * @dev evaluation data will call this function to generate an NFT token
    * @dev and transfer its ownership to Asset Creator's address.
    *
    * @param _creator is the customer address who created the asset
    * @param _assetId is the ID of the asset being converted to NFT token
    * @param _evaluationId is the look up index of the Evaluation data in the EvaluationsByAsset list
    */

    function createNftToken(address _owner, uint256 _assetId, uint256 _evaluationId, uint256 _mintingFee) external OnlyEOA onlyRole(EVALUATOR_ROLE) {
        
        // Check creator
        require(_owner!=address(0),"Address creator must be different from 0.");

        // Check asset id
        require(_assetId >=0 ,"Invalid asset or asset does not exist.");

        // Check evaluationId
        require(_evaluationId >=0 ,"Invalid evaluation or evaluation does not exist.");

        Evaluation storage _evaluation = evaluationList[_evaluationId];

        // Check status evaluation
        require(_evaluation.status == EvaluationStatus.EVALUATION_ACCEPTED,"Evaluation is not acceptable");

        // Check evaluator
        require(msg.sender == _evaluation.evaluator, "Evaluator address does not match");

        Asset storage _asset = assetList[_assetId];

        // Check status asset
        require(_asset.status == AssetStatus.EVALUATED);

        // Check balance
        require(ibepDFY.balanceOf(msg.sender) >= (_mintingFee*1 ether), "Your balance is not enough.");
        

        require(ibepDFY.allowance(msg.sender, address(this)) >= (_mintingFee * 1 ether), "You have not authorized the smart contract.");

        // Create NFT
        uint256 mintedTokenId = dfy_physical_nfts.mint(_owner, msg.sender, 1, _asset.assetDataCID, "");

        // Tranfer minting fee to admin
        ibepDFY.transferFrom(msg.sender,addressAdmin , _mintingFee*1 ether);

        // Update status asset
        _asset.status = AssetStatus.NFT_CREATED;

        // Update status evaluation
        _evaluation.status = EvaluationStatus.NFT_CREATED;

        // Add token id to list asset of owner
        tokenIdByAsset[mintedTokenId] = _asset;

        // Add token id to list nft of evaluator
        tokenIdByEvaluation[mintedTokenId] = _evaluation;

    }

    /**
    * @dev Add an Evaluator to Whitelist and grant him Minter role.
    * @param _account is the address of an Evaluator
    */ 
    function addEvaluator(address _account) external onlyRole(OPERATOR_ROLE) {
        // Grant Evaluator role
        setEvaluatorRole(_account);

        // Approve
        emit ApproveEvaluator(_account);
    }

}