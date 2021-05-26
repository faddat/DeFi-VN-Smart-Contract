// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20CustomToken is ERC20 {

    constructor (string memory tokenName, string memory tokenSymbol) public ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
    }
}
