pragma solidity ^0.7.0;

import "@vittominacori/erc20-token/contracts/ERC20Base.sol";

contract DFY is ERC20Base {

    constructor () ERC20Base(
        "DeFi For You", 
        "#DFY", 
        18, 
        1e27, 
        1e27, 
        false
    ) {}
}
