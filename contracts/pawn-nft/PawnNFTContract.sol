// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../evaluation/DFY-AccessControl.sol";
import "../evaluation/DFY_Physical_NFTs.sol";
import "../evaluation/IBEP20.sol";
import "./IPawnNFT.sol";

contract PawnNFTContract is 
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

    function initialize() public initializer {
        __ERC1155Holder_init();
        __DFYAccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function supportsInterface(bytes4 interfaceId) 
    public view 
    override(ERC1155ReceiverUpgradeable, AccessControlUpgradeable) 
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function createCollateral(
        uint256 _tokenId, 
        address _currency, 
        uint256 _amount,
        address _loanAsset,
        uint256 _duration,
        LoanDurationType _durationType
    ) external override {
        /**
        TODO: Implementation
        */
    }
}