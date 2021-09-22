// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IDFY_Physical_NFTs {
    
    struct NFTEvaluation{
        address evaluationContract;
        uint256 evaluationId;
    }

    function mint(
        address _assetOwner, 
        address _evaluator, 
        uint256 _evaluatontId, 
        uint256 _amount, 
        string memory _cid, 
        bytes memory _data
    ) 
        external
        returns (uint256 tokenId);

    function getEvaluationOfToken(uint256 _tokenId) external returns (NFTEvaluation memory);
}