pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/TokenTimelock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DFYTreasure is TokenTimelock {

    constructor () public TokenTimelock (
        IERC20(0x7D3257f000B73D3eBaD2bC7BF48B6850AD6F567e), // token
        0x4F9119eb566d1b8cBE7C866424217e8E69757048, // beneficiary
        1766073607) {
    }
}
