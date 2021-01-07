// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IdoDFY is Ownable {
    using SafeMath for uint256;
    IERC20 private DFYToken;

    struct ExchangePair {
        uint256 output;
        uint256 input;
        bool status;
    }

    mapping(address => mapping(address => bool)) public referrals;
    mapping(address => uint256) public referralRewardTotal;
    mapping(address => uint32) public referralUserTotal;

    mapping(address => uint256) public boughtAmountTotals;

    enum Stage {Unpause, Pause}

    Stage public stage;

    modifier requireOpen {
        require(stage == Stage.Unpause, "Stage close");
        _;
    }

    mapping(address => ExchangePair) public exchangePairs;
    address[] public supportedTokens;

    event UpdateExchangePair(
        address token,
        uint256 input,
        uint256 output,
        uint256 time
    );

    constructor(address _DFYToken) public {
        DFYToken = IERC20(address(_DFYToken));
        stage = Stage.Pause;
    }

    function setStage(Stage _stage) public onlyOwner{
        stage=_stage;
    }

    function updateExchangePair(
        address token,
        uint256 output,
        uint256 input
    ) public onlyOwner {
        require(token != address(0), "Token invalid");
        if (!exchangePairs[token].status) {
            supportedTokens.push(token);
        }
        exchangePairs[token] = ExchangePair(output, input, true);
        emit UpdateExchangePair(token, input, output, block.timestamp);
    }

    event DeleteExchangePair(address token, uint256 time);

    function deleteExchangePair(address token) public onlyOwner {
        require(exchangePairs[token].status, "Status invalid");
        delete exchangePairs[token];

        address[] storage addressTokens;

        for (uint i = 0; i < supportedTokens.length; i++) {
            if(supportedTokens[i] != token) {
                addressTokens.push(supportedTokens[i]);
            }
        }
        supportedTokens = addressTokens;

        emit DeleteExchangePair(token, block.timestamp);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    event BuyIDO(
        address token,
        address user,
        uint256 amount,
        uint256 dfyAmount,
        address referral,
        uint256 referralAmount,
        uint256 time
    );

    function buyIdo(
        address token,
        uint256 amount,
        address referral
    ) external requireOpen {
        require(exchangePairs[token].status, "Exchange pair is not exist!");

        IERC20 transferToken = IERC20(token);

        require(
            transferToken.balanceOf(msg.sender) >= amount,
            "Token insufficient"
        );

        uint256 outputDFYAmount =
        (exchangePairs[token].output.mul(amount)).div(
            exchangePairs[token].input
        );

        require(
            boughtAmountTotals[msg.sender] + outputDFYAmount < 500000*(10 ** 18),
            "Amount is exceeded!"
        );

        boughtAmountTotals[msg.sender] += outputDFYAmount;

        require(
            DFYToken.balanceOf(address(this)) >= outputDFYAmount,
            "DFY insufficient"
        );

        require(
            transferToken.transferFrom(msg.sender, owner(), amount),
            "Token transfer fail"
        );

        require(
            DFYToken.approve(msg.sender, outputDFYAmount),
            "DFY approve failed!"
        );

        require(
            DFYToken.transfer(msg.sender, outputDFYAmount),
            "DFY transfer fail"
        );

        uint256 referralReceiveAmount = 0;
        if (referral != address(0)
        && referral != msg.sender
        && !referrals[msg.sender][referral]
        && referralUserTotal[msg.sender] < 10) {
            referralReceiveAmount = (outputDFYAmount.mul(15)).div(
                100
            );

            if(referralRewardTotal[msg.sender] + referralReceiveAmount > 750000*(10 ** 18)) {
                referralReceiveAmount = 500000*(10 ** 18) - referralReceiveAmount;
            }

            referralRewardTotal[msg.sender] += referralReceiveAmount;
            referralUserTotal[msg.sender] += 1;

            referrals[msg.sender][referral] = true;
        }

        if (referralReceiveAmount > 0) {

            require(
                DFYToken.approve(referral, referralReceiveAmount),
                "DFY approve ref failed!"
            );

            require(
                DFYToken.transfer(referral, referralReceiveAmount),
                "DFY transfer referral fail"
            );
            emit BuyIDO(
                token,
                msg.sender,
                amount,
                outputDFYAmount,
                referral,
                referralReceiveAmount,
                block.timestamp
            );
        }
        emit BuyIDO(
            token,
            msg.sender,
            amount,
            outputDFYAmount,
            address(0),
            0,
            block.timestamp
        );
    }

    function getTokenSupport() public view returns (address[] memory) {
        return supportedTokens;
    }

    function getExchangePair(address _tokenAddress) public view returns (address tokenAddress, uint256 output, uint256 input, bool status) {
        return (_tokenAddress, exchangePairs[_tokenAddress].output, exchangePairs[_tokenAddress].input, exchangePairs[_tokenAddress].status);
    }
}
