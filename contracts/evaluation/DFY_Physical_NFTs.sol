// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./DFY-AccessControl.sol";

contract DFY_Physical_NFTs is ERC1155Upgradeable, DFYAccessControl, PausableUpgradeable, ERC1155BurnableUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;

    CountersUpgradeable.Counter public totalToken;
    
    // Mapping list tokenId
    // tokenId => cid
    mapping(uint256 => string) public tokenIdListToCID;

    // Mapping tokenId to owner
    // tokentId => address
    mapping(uint256 => address) public tokenIdByOwner;

    // Mapping address by tokenId
    // Owner => listTokenId
    mapping (address => uint256[]) public tokenIdListByOwner;

    // Mapping evaluator to NFT 
    // address evaluator => listTokenId
    mapping (address => uint256[] ) public tokenIdListByEvaluator;

    string public name;
    string public symbol;

    string private _tokenBaseUri;

    event NFTCreated(
        address assetOwner,
        uint256 tokenID,
        string cid
    );

    function initialize(
        string memory _name,
        string memory _symbol,
        string memory _uri
    ) public initializer {
        __ERC1155_init("");
        __DFYAccessControl_init();
        __Pausable_init();
        __ERC1155Burnable_init();

        name = _name;
        symbol = _symbol;
        
        _setBaseURI(_uri);
    }

    function _setBaseURI(string memory _uri) internal {
        require(bytes(_uri).length > 0, "BaseURI must not be blank");
        _tokenBaseUri = _uri;
    }

    function _baseURI() internal view returns (string memory) {
        return _tokenBaseUri;
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return bytes(tokenIdListToCID[tokenId]).length > 0;
    }

    function setBaseURI(string memory _uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBaseURI(_uri);
    }

    function uri(uint tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");

        string memory baseUri = _baseURI();
        return bytes(baseUri).length > 0 ? string(abi.encodePacked(baseUri, tokenIdListToCID[tokenId])) : "";
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function mint(address _assetOwner, address _evaluator, uint256 _amount, string memory _cid, bytes memory _data) 
        public
        onlyRole(EVALUATOR_ROLE) 
        returns (uint256 tokenId)
    {
        // Gennerate tokenId
        tokenId = totalToken.current();

        // Add mapping tokenId to CID
        tokenIdListToCID[tokenId] = _cid;

        // Add mapping tokenId to address owner
        tokenIdByOwner[tokenId] = _assetOwner;

        // Add tokenId to list tokenId by owner
        tokenIdListByOwner[_assetOwner].push(tokenId);

        // Add tokenId to list tokenId by evaluator
        tokenIdListByEvaluator[_evaluator].push(tokenId);

        // Mint nft
        _mint(_assetOwner, tokenId, _amount, _data);

        // Update tokenId count
        totalToken.increment();

        emit NFTCreated(_assetOwner, tokenId, _cid);

        return tokenId;
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}