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
    mapping(address => uint32) public referralsReward;

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

    constructor(address _DFYToken) {
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
    ) external requireOpen{
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


        if (referral != address(0)
        && referral != msg.sender
        && referrals[msg.sender][referral]
        && referralsReward[referral] < 25000
        ) {

            uint256 referralNumber = (outputDFYAmount.mul(11)).div(
                100
            );
            require(
                DFYToken.transfer(referral, referralNumber),
                "DFY transfer referral fail"
            );
            emit BuyIDO(
                token,
                msg.sender,
                amount,
                outputDFYAmount,
                referral,
                referralNumber,
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
}
