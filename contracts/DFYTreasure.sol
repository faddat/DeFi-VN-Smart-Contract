pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/TokenTimelock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DFYTreasure is TokenTimelock {

    constructor () public TokenTimelock (
        IERC20(0x7d3257f000b73d3ebad2bc7bf48b6850ad6f567e), // token
        0x4F9119eb566d1b8cBE7C866424217e8E69757048, // beneficiary
        1766073607) {
    }
}
