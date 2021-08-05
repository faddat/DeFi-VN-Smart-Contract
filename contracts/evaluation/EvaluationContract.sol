// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
// import "@openzeppelin/contracts/access/AccessControl.sol";
import "./DFY-1155.sol";

contract AssetEvaluation is ERC1155Holder {
    using Counters for Counters.Counter;
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    Counters.Counter public totalAssets;

    DFY1155 public dfy1155;

    // Assuming _assetBaseUri = "https://ipfs.io/ipfs/"

    string private _assetBaseUri;
    address public contractAdmin;

    // creator => (assetId => Asset)
    mapping(address => mapping(uint256 => Asset)) public assetList;

    // assetId => Evaluation[]
    mapping(uint => Evaluation[]) public EvaluationsByAsset;

    // evaluator address => has minter role
    mapping(address => bool) public WhiteListedEvaluator;

    // TODO: reduce status to Open, Evaluated, NFT_created
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

    modifier OnlyAdmin() {
        require(msg.sender == contractAdmin, "Only Admin can perform this action");
        _;
    }

    constructor(
        string memory _uri, 
        address _dfy1155_contract_address
    ) {
        contractAdmin = msg.sender;
        _setAssetBaseURI(_uri);

        dfy1155 = DFY1155(_dfy1155_contract_address);
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

    // function ChangeNftContractAddress(address _newAddress) external OnlyAdmin returns (bool) {}

    /**
    * @dev Asset creation request by customer
    * @dev msg.sender is the asset creator's address
    */

    function CreateAssetRequest(string memory _cid) external {
        // TODO: Require validation of msg.sender

        uint _assetId = totalAssets.current();
        assetList[msg.sender][_assetId] = Asset({
                                                assetDataCID: _cid,
                                                creator: msg.sender,
                                                status: AssetStatus.OPEN
                                            });

        emit AssetCreated(_assetId, assetList[msg.sender][_assetId]);

        totalAssets.increment();
    }

    /**
    * @dev Asset evaluation by evaluator
    * @dev msg.sender is evaluator address
    * @param _assetId is the ID of the asset in AssetList
    * @param _currency is address of the token who create the asset
    * @param _price value of the asset, given by the Evaluator
    */
    function EvaluateAsset(uint _assetId, address _currency, uint _price) external {
        // TODO
        // Require validation of msg.sender
        // Require msg.sender must be Whitelisted
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
    function AcceptEvaluation(address _creator, uint _assetId, uint _evaluationIndex) external {
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

    modifier OnlyMinter() {
        require(dfy1155.hasRole(MINTER_ROLE, msg.sender), "Only Minter can mint");
        _;
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

    function CreateNftToken(address _creator, uint _assetId, uint _evaluationIndex) external OnlyMinter {
        Evaluation memory evaluation = EvaluationsByAsset[_assetId][_evaluationIndex];

        require(msg.sender == evaluation.evaluator, "Evaluator address does not match");

        Asset storage asset = assetList[_creator][_assetId];

        uint mintedTokenId = dfy1155.mint(_creator, 1, asset.assetDataCID, "");

        asset.status = AssetStatus.NFT_CREATED;

        emit NftCreationSuccessful(_creator, mintedTokenId, asset.assetDataCID, asset.status);
    }

    /**
    * @dev Add an Evaluator to Whitelist and grant him Minter role.
    * @param _evaluator is the address of an Evaluator
    */

    function AddEvaluator(address _evaluator) external OnlyAdmin {
        WhiteListedEvaluator[_evaluator] = true;

        // Grant Minter role to evaluator
        dfy1155.grantRole(MINTER_ROLE, _evaluator);

        // Approve

        emit WhiteListEvaluatorRegistrationSuccessful(_evaluator);
    }

    /** 
    * @dev Remove an Evaluator from Whitelist
    */
    function RemoveEvaluator(address _evaluator) external OnlyAdmin{

    }

    /** 
    * @dev Add an Evaluated token to Whitelist
    */
    function AddEvaluatedToken(uint _tokenId) external {

    }

    /** 
    * @dev Remove a Evaluated token from Whitelist
    */
    function RemoveEvaluatedToken(uint _tokenId) external {

    }
}