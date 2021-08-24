// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
// import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./DFY-AccessControl.sol";
import "./DFY-1155-draft.sol";

contract AssetEvaluation is ERC1155HolderUpgradeable, PausableUpgradeable, DFYAccessControl {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint;
    
    CountersUpgradeable.Counter public totalAssets;
    DFY1155 public dfy1155;

    // Assuming _assetBaseUri = "https://ipfs.io/ipfs/"
    string private _assetBaseUri;

    // creator => (assetId => Asset)
    mapping(address => mapping(uint256 => Asset)) public assetList; // Public for debugging, should be changed to private later.

    // Mapping from creator address to assetId in his/her possession
    mapping(address => mapping(uint256 => bool)) private _assetsOfCreator;

    // mapping of creator address to asset count
    mapping(address => uint256) private _assetCountByCreator;

    // Mapping from assetId to index of the creator asset list
    mapping(uint256 => uint256) private _ownedAssetIndex;

    // creator => uint[]
    mapping(address => uint256[]) public assetListByCreator;

    // assetId => Evaluation[]
    mapping(uint256 => Evaluation[]) public EvaluationsByAsset;

    // evaluator address => has minter role
    mapping(address => bool) public WhiteListedEvaluator;

    function initialize(
        string memory _uri,
        address _dfy1155_contract_address
    ) public initializer {
        __ERC1155Holder_init();
        __DFYAccessControl_init();
        __Pausable_init();

        _setAssetBaseURI(_uri);

        _setNFTAddress(_dfy1155_contract_address);
    }

    enum AssetStatus {OPEN, EVALUATED, NFT_CREATED}

    struct Asset {
        string assetDataCID;
        address creator;
        AssetStatus status;
    }

    enum EvaluationStatus {CREATED, APPROVED, REJECTED}

    struct Evaluation {
        address evaluator;
        address token;
        uint price;        
        EvaluationStatus status;
    }

    event AssetCreated (
        uint assetId,
        Asset asset
    );
    event AssetEvaluated(
        uint assetId,
        Asset asset,
        Evaluation evaluation
    );
    event NftCreationSuccessful(
        address creator,
        uint tokenID,
        string cid,
        AssetStatus status
    );
    event WhiteListEvaluatorRegistrationSuccessful(
        address evaluator
    );

    modifier OnlyEOA() {
        require(!msg.sender.isContract(), "Caller address must not be a contract address");
        _;
    }

    function setBaseURI(string memory _uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAssetBaseURI(_uri);
    }

    function _setAssetBaseURI(string memory _uri) internal {
        require(bytes(_uri).length > 0, "Asset data URI must not be empty");
        _assetBaseUri = _uri;
    }

    function _assetBaseURI() internal view returns (string memory) {
        return _assetBaseUri;
    }

    function assetURI(address _creator, uint _assetId) external view returns (string memory) {
        return bytes(_assetBaseUri).length > 0 ? string(abi.encodePacked(_assetBaseUri, assetList[_creator][_assetId].assetDataCID)) : "";
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155ReceiverUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
    * @dev Set the current NFT contract address to a new address
    * @param _newAddress is the address of the new NFT contract
    */
    function setNftContractAddress(address _newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Verify if the new address is a contract or not
        require(_newAddress.isContract(), "Input address is not a contract address");
        
        _setNFTAddress(_newAddress);
    }

    function _setNFTAddress(address _newAddress) internal {
        dfy1155 = DFY1155(_newAddress);
    }

    /**
    * @dev Asset creation request by customer
    * @dev msg.sender is the asset creator's address
    * @param _cid is the CID string of the asset's JSON file stored on IFPS
    */
    function createAssetRequest(string memory _cid) external OnlyEOA {
        // TODO: Require validation of msg.sender
        // msg.sender must not be a contract address

        uint256 _assetId = totalAssets.current();
        
        assetList[msg.sender][_assetId] = Asset({
                                                assetDataCID: _cid,
                                                creator: msg.sender,
                                                status: AssetStatus.OPEN
                                            });
        
        _assetsOfCreator[msg.sender][_assetId] = true;
        _assetCountByCreator[msg.sender] += 1;

        // map the _assetId to the index in the list of owned assets
        _ownedAssetIndex[_assetId] = assetListByCreator[msg.sender].length;

        // update list of assets that are possessed by this creator
        assetListByCreator[msg.sender].push(_assetId);

        emit AssetCreated(_assetId, assetList[msg.sender][_assetId]);

        totalAssets.increment();
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

    function _isAssetOfCreator(address _creator, uint256 _assetId) internal view returns (bool) {
        return _assetsOfCreator[_creator][_assetId];
    }

    /** 
    * @dev Remove an asset from the owner's collection
    */
    function removeAssetFromCreator(address _creator, uint256 _assetId) external {
        // TODO: Data validation
        // Only _creator can remove his/her own assets
        require(_creator == _msgSender(), "Only the owner can remove his/her own asset");

        // Asset must exist and must be in _creator's possession -> check _assetId's existence
        require(_isAssetOfCreator(_creator, _assetId), "The asset does not belong to this owner");

        // load the assets owned by this creator
        uint256[] storage _ownedAssets = assetListByCreator[_creator];

        // get the index of _assetId in creator's asset list
        uint256 _index = _ownedAssetIndex[_assetId];

        // get the last index of the asset array
        uint256 _lastIndex = _ownedAssets.length - 1;

        // Get the asset at the last position of the array
        uint256 _lastAssetId = _ownedAssets[_lastIndex];

        if(_index != _lastIndex) {
            // If the _index is not the _lastIndex            
            // swap the assetId at found index with the one at the last position of the array
            _ownedAssets[_lastIndex] = _ownedAssets[_index];
            _ownedAssets[_index] = _lastAssetId;

            // update index of swapped asset
            _ownedAssetIndex[_lastAssetId] = _index;
        }
        
        _ownedAssets.pop();        
        delete _ownedAssetIndex[_assetId];
        delete _assetsOfCreator[_creator][_assetId];
        delete assetList[_creator][_assetId];
        _assetCountByCreator[msg.sender]--;
    }

    /**
    * @dev Asset evaluation by evaluator
    * @dev msg.sender is evaluator address
    * @param _assetId is the ID of the asset in AssetList
    * @param _currency is address of the token who create the asset
    * @param _price value of the asset, given by the Evaluator
    */
    function evaluateAsset(uint _assetId, address _currency, uint _price) external onlyRole(EVALUATOR_ROLE) {
        // TODO
        // Require validation of msg.sender
        // Require validation of asset via _assetId

        uint _nextEvaluation = EvaluationsByAsset[_assetId].length;
        
        // Add evaluation data to mapping
        EvaluationsByAsset[_assetId][_nextEvaluation] = Evaluation({
                                                            evaluator: msg.sender,
                                                            token: _currency,
                                                            price: _price,
                                                            status: EvaluationStatus.CREATED
                                                        });

        // Evaluation memory _evaluation = Evaluation({
        //                             evaluator: msg.sender,
        //                             token: _currency,
        //                             price: _price,
        //                             status: EvaluationStatus.CREATED
        //                         });
        
        // Add evaluation data to mapping
        // EvaluationsByAsset[_assetId].push(_evaluation);

        // _asset.status = AssetStatus.EVALUATED;

        // emit EvaluationSentSuccessful(_creator, msg.sender, _assetId, _asset.assetDataCID, _asset.status);
    }

    /** 
    * @dev Customer accept evaluation data from evaluator
    * @param _creator is address of the Customer who create the asset
    * @param _assetId is the ID of the asset in AssetList
    * @param _evaluationIndex is the look up index of the Evaluation data in EvaluationsByAsset list
    */
    function acceptEvaluation(address _creator, uint _assetId, uint _evaluationIndex) external {
        Asset storage _asset = assetList[_creator][_assetId];
        
        // approve an evaluation by looking for its index in the array.
        Evaluation storage _evaluation = EvaluationsByAsset[_assetId][_evaluationIndex];
        _evaluation.status = EvaluationStatus.APPROVED;
        
        // reject all other evaluation
        for(uint i = 0; i < EvaluationsByAsset[_assetId].length; i++) {
            if(i != _evaluationIndex) {
                EvaluationsByAsset[_assetId][i].status = EvaluationStatus.REJECTED;
            }
        }

        _asset.status = AssetStatus.EVALUATED;

        // emit AssetEvaluated(
        //     _evaluationIndex,
        //     _creator, 
        //     EvaluationsByAsset[_assetId][_evaluationIndex].evaluator, 
        //     EvaluationsByAsset[_assetId][_evaluationIndex].price
        // );

        emit AssetEvaluated(_assetId, _asset, _evaluation);
    }
    
    /**
    * @dev After an evaluation is approved, the Evaluator who submit
    * @dev evaluation data will call this function to generate an NFT token
    * @dev and transfer its ownership to Asset Creator's address.
    *
    * @param _creator is the customer address who created the asset
    * @param _assetId is the ID of the asset being converted to NFT token
    * @param _evaluationIndex is the look up index of the Evaluation data in the EvaluationsByAsset list
    */

    // function createNftToken(address _creator, uint _assetId, uint _evaluationIndex) external onlyRole(EVALUATOR_ROLE) {
    //     Evaluation memory evaluation = EvaluationsByAsset[_assetId][_evaluationIndex];

    //     require(msg.sender == evaluation.evaluator, "Evaluator address does not match");

    //     Asset storage asset = assetList[_creator][_assetId];

    //     uint mintedTokenId = dfy1155.mint(_creator, 1, asset.assetDataCID, "");

    //     asset.status = AssetStatus.NFT_CREATED;

    //     emit NftCreationSuccessful(_creator, mintedTokenId, asset.assetDataCID, asset.status);
    // }

    // /**
    // * @dev Add an Evaluator to Whitelist and grant him Minter role.
    // * @param _evaluator is the address of an Evaluator
    // */

    // function addEvaluator(address _account) external onlyRole(PROGRAM_ADMIN_ROLE) {
    //     // Grant Evaluator role
    //     setEvaluatorRole(_account);

    //     // Approve
    //     emit WhiteListEvaluatorRegistrationSuccessful(_account);
    // }

    // /** 
    // * @dev Remove an Evaluator from Whitelist
    // */
    // function removeEvaluator(address _evaluator) external OnlyAdmin{

    // }

    /** 
    * @dev Add an Evaluated token to Whitelist
    */
    function addEvaluatedToken(uint _tokenId) external {

    }

    /** 
    * @dev Remove a Evaluated token from Whitelist
    */
    function removeEvaluatedToken(uint _tokenId) external {

    }
}