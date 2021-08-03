// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract AssetEvaluation is ERC1155Holder {
    using Counters for Counters.Counter;

    Counters.Counter public totalAssets;

    IERC1155 public DFY1155;

    string private _assetBaseUri;
    address public contractAdmin;

    // creator => (assetId => Asset)
    mapping(address => mapping(uint256 => Asset)) public assetList;

    // assetId => Evaluation[]
    mapping(uint => Evaluation[]) public EvaluationsByAsset;

    enum AssetStatus {CREATED, OPEN, EVALUATED, EVALUATION_APPROVED, NFT_CREATED}

    struct Asset {
        string assetExtId;
        string assetDataCID;
        address creator;
        // bool isEvaluated;
        // bool isEvaluationApproved;
        AssetStatus status;
    }

    enum EvaluationStatus {CREATED, APPROVED, REJECTED}

    struct Evaluation {
        address evaluator;
        uint price;
        EvaluationStatus status;
    }

    event AssetCreationSuccessful(
        address creator,
        uint assetId,
        string cid,
        AssetStatus status
    );
    event AssetEvaluationSuccessful(
        address creator,
        address evaluator,
        uint assetId,
        string cid,
        AssetStatus status
    );
    event EvaluationApprovalSuccessful(
        address creator,
        address evaluator,
        uint price
    );
    event NftCreationSuccessful(
        address creator,
        uint tokenID,
        AssetStatus status
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

        DFY1155 = IERC1155(_dfy1155_contract_address);
    }

    function _setAssetBaseURI(string memory _uri) internal {
        require(bytes(_uri).length > 0, "Asset data URI must not be empty");
        _assetBaseUri = _uri;
    }

    function _assetBaseURI() internal view returns (string memory) {
        return _assetBaseUri;
    }

    // function ChangeNftContractAddress(address _newAddress) external OnlyAdmin returns (bool) {}

    /**
    * @dev Asset creation request by customer
    * @dev msg.sender is the asset creator's address
    */

    function CreateAssetRequest(string memory _assetExtId,string memory _cid) external {
        // TODO: Require validation of msg.sender

        uint _assetId = totalAssets.current();
        assetList[msg.sender][_assetId] = Asset({
                                                assetExtId: _assetExtId,
                                                assetDataCID: _cid,
                                                creator: msg.sender,
                                                status: AssetStatus.CREATED
                                            });

        emit AssetCreationSuccessful(msg.sender, _assetId, _cid, AssetStatus.CREATED);

        totalAssets.increment();
    }

    /**
    * @dev Asset evaluation by evaluator
    * @dev msg.sender is evaluator address
    */

    function EvaluateAsset(address _creator, uint _assetId, uint _price) external {
        // TODO: Require validation of msg.sender

        Asset storage _asset = assetList[_creator][_assetId];
        
        Evaluation memory _evaluation = Evaluation({
                                    evaluator: msg.sender,
                                    price: _price,
                                    status: EvaluationStatus.CREATED
                                });

        // Add evaluation data to mapping
        EvaluationsByAsset[_assetId].push(_evaluation);

        _asset.status = AssetStatus.EVALUATED;

        emit AssetEvaluationSuccessful(_creator, msg.sender, _assetId, _asset.assetDataCID, _asset.status);
    }

    /** 
    * @dev Customer accept evaluation data from evaluator
    */

    function AcceptEvaluation(address _creator, uint _assetId, uint _evaluationIndex) external {
        Asset storage _asset = assetList[_creator][_assetId];
        
        // approve an evaluation by looking for its index in the array.
        EvaluationsByAsset[_assetId][_evaluationIndex].status = EvaluationStatus.APPROVED;
        
        // reject all other evaluation
        for(uint i = 0; i < EvaluationsByAsset[_assetId].length; i++) {
            if(i != _evaluationIndex) {
                EvaluationsByAsset[_assetId][i].status = EvaluationStatus.REJECTED;
            }
        }

        _asset.status = AssetStatus.EVALUATION_APPROVED;

        emit EvaluationApprovalSuccessful(_creator, EvaluationsByAsset[_assetId][_evaluationIndex].evaluator, EvaluationsByAsset[_assetId][_evaluationIndex].price);

        // TODO: Mint token NFT

        // grant minter role to Evaluator whose evaluation data has been approved
        // DFY1155. EvaluationsByAsset[_assetId][_evaluationIndex].evaluator
        
    }

    /**
    * @dev After an evaluation is approved, the Evaluator who submit
    * @dev evaluation data will call this function to generate an NFT token
    */
    
    function CreateNftToken() external {

    }

    /**
    * @dev Add an Evaluator to Whitelist
    */

    function AddEvaluator(address _evaluator) external {

    }

    /** 
    * @dev Remove an Evaluator from Whitelist
    */
    function RemoveEvaluator(address _evaluator) external {

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