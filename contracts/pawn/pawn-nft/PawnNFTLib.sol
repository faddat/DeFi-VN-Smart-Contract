// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "./IPawnNFT.sol";

library PawnNFTLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
    * @dev safe transfer BNB or ERC20
    * @param  asset is address of the cryptocurrency to be transferred
    * @param  from is the address of the transferor
    * @param  to is the address of the receiver
    * @param  amount is transfer amount
    */
    function safeTransfer(
        address asset, 
        address from, 
        address to, 
        uint256 amount
    ) internal {
        if (asset == address(0)) {
            require(from.balance >= amount, 'not-enough-balance');
            // Handle BNB            
            if (to == address(this)) {
                // Send to this contract
            } else if (from == address(this)) {
                // Send from this contract
                (bool success, ) = to.call{value:amount}('');
                require(success, 'fail-transfer-bnb');
            } else {
                // Send from other address to another address
                require(false, 'not-allow-transfer');
            }
        } else {
            // Handle ERC20
            uint256 prebalance = IERC20Upgradeable(asset).balanceOf(to);
            require(IERC20Upgradeable(asset).balanceOf(from) >= amount, 'not-enough-balance');
            if (from == address(this)) {
                // transfer direct to to
                IERC20Upgradeable(asset).safeTransfer(to, amount);
            } else {
                require(IERC20Upgradeable(asset).allowance(from, address(this)) >= amount, 'not-enough-allowance');
                IERC20Upgradeable(asset).safeTransferFrom(from, to, amount);
            }
            require(IERC20Upgradeable(asset).balanceOf(to) - amount == prebalance, 'not-transfer-enough');
        }
    }

    function safeTranferNFTToken(address _nftToken, address _from, address _to, uint256 _id, uint256 _amount) internal {
        
        // check address token
        require(_nftToken != address(0), "Address token must be different address(0).");

        // check address from
        require(_from != address(0), "Address from must be different address(0).");

        // check address from
        require(_to != address(0), "Address to must be different address(0).");

        // Check amount token
        require(_amount > 0, "Amount must be grean than 0.");

        // Check balance of from,
        require(IERC1155Upgradeable(_nftToken).balanceOf(_from,_id) >= _amount, "Your balance not enough.");

        // Transfer token
        IERC1155Upgradeable(_nftToken).safeTransferFrom(_from,_to,_id,_amount,"");
    }

    /**
    * @dev Calculate the duration of the contract
    * @param  durationType is loan duration type of contract (WEEK/MONTH)
    * @param  duration is duration of contract
    */
    function calculateContractDuration(IPawnNFT.LoanDurationType durationType, uint256 duration) 
        internal 
        pure 
        returns (uint256 inSeconds) 
    {
        if (durationType == IPawnNFT.LoanDurationType.WEEK) {
            // inSeconds = 7 * 24 * 3600 * duration;
            inSeconds = duration * 600; //=> Using test
        } else {
            // inSeconds = 30 * 24 * 3600 * duration;
            inSeconds = duration * 900; //=> Using test
        }
    }

    /**
    * @dev Calculate balance of wallet address 
    * @param  _token is address of token 
    * @param  from is address wallet
    */
    function calculateAmount(
        address _token, 
        address from
    ) internal view returns (uint256 _amount) {
        if (_token == address(0)) {
            // BNB
            _amount = from.balance;
        } else {
            // ERC20
            _amount = IERC20Upgradeable(_token).balanceOf(from);
        }
    }

    /**
    * @dev Calculate fee of system
    * @param  amount amount charged to the system
    * @param  feeRate is system fee rate
    */
    function calculateSystemFee(
        uint256 amount, 
        uint256 feeRate,
        uint256 zoom
    ) internal pure returns (uint256 feeAmount) {
        feeAmount = (amount * feeRate) / (zoom * 100);
    }
}