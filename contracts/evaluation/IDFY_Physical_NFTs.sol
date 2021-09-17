// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IDFY_Physical_NFTs {

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
}