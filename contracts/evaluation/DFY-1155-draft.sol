// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./DFY-AccessControl.sol";

contract DFY1155 is ERC1155Upgradeable, DFYAccessControl, PausableUpgradeable, ERC1155BurnableUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address;

    CountersUpgradeable.Counter public tokenCount;

    mapping(uint => string) public IpfsCidMapping;
    mapping(uint => address) public TokenCreator;

    string public name;
    string public symbol;

    string private _tokenBaseUri;

    // Assuming baseURI = "https://ipfs.io/ipfs/"

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
        return bytes(IpfsCidMapping[tokenId]).length > 0;
    }

    function setBaseURI(string memory _uri) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBaseURI(_uri);
    }

    // function setURI(string memory newuri) public onlyRole(URI_SETTER_ROLE) {
    //     _setURI(newuri);
    // }

    function uri(uint tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");

        string memory baseUri = _baseURI();
        return bytes(baseUri).length > 0 ? string(abi.encodePacked(baseUri, IpfsCidMapping[tokenId])) : "";
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // function mint(address account, uint256 id, uint256 amount, bytes memory data)
    //     public
    //     onlyRole(MINTER_ROLE)
    // {
    //     _mint(account, id, amount, data);
    // }

    function mint(address account, uint256 amount, string memory cid, bytes memory data) 
        public
        onlyRole(EVALUATOR_ROLE) 
        returns (uint256 tokenId)
    {
        tokenId = tokenCount.current();

        IpfsCidMapping[tokenId] = cid;
        TokenCreator[tokenId] = account;
        _mint(account, tokenId, amount, data);

        tokenCount.increment();

        return tokenId;
    }

    // function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
    //     public
    //     onlyRole(MINTER_ROLE)
    // {
    //     _mintBatch(to, ids, amounts, data);
    // }

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