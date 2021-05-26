// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IdoDFY is Ownable {
    constructor(
        address _DFYToken,
        uint256 _buyMinimum,
        uint256 _buyMaximum,
        uint256 _maxPersonRef,
        uint256 _maxRewardFromRef,
        uint256 _refRewardPercent,
        uint _start,
        uint _end
    ) public {
        DFYToken = IERC20(address(_DFYToken));
        stage = Stage.Unpause;
        buyMinimum = _buyMinimum;
        buyMaximum = _buyMaximum;
        maxPersonRef = _maxPersonRef;
        maxRewardFromRef = _maxRewardFromRef;
        refRewardPercent = _refRewardPercent;
        start = _start;
        end = _end;
        isPublic = false;
    }

    uint256 public buyMinimum;
    uint256 public buyMaximum;
    uint256 public refRewardPercent;
    uint256 public maxPersonRef;
    uint256 public maxRewardFromRef;
    uint public start;
    uint public end;

    using SafeMath for uint256;
    IERC20 private DFYToken;

    struct ExchangePair {
        uint256 output;
        uint256 input;
        bool status;
    }

    mapping(address => address) public beReferred;
    mapping(address => uint256) public referralRewardTotal;
    mapping(address => uint8) public referralUserTotal;

    mapping(address => uint256) public boughtAmountTotals;

    enum Stage {Unpause, Pause}

    Stage public stage;

    mapping(address => bool) public whitelist;
    bool public isPublic;

    modifier requireOpen {
        require(stage == Stage.Unpause, "Stage close");
        require(block.timestamp >= start, "IDO time is not started");
        require(block.timestamp <= end, "IDO time was end");

        require(isPublic || whitelist[msg.sender], "Public sale still not open");

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

    function setStage(Stage _stage) public onlyOwner{
        stage = _stage;
    }

    function setPublic(bool _isPublic) public onlyOwner {
        isPublic = _isPublic;
    }

    function addWhiteList(address _whitelist) public onlyOwner {
        whitelist[_whitelist] = true;
    }

    function updateExchangePair(
        address token,
        uint256 output,
        uint256 input
    ) public onlyOwner {
        // require(token != address(0), "Token invalid"); address(0) for BNB
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



    function _transferBNBToOwner(uint256 amount) internal {
        address owner=owner();
        address payable ownerPayable = address(uint160(owner));
        ownerPayable.transfer(amount);
    }

    function _transferDFy(uint256 amount) internal{
        require(
            DFYToken.approve(msg.sender, amount),
            "DFY approve failed!"
        );

        require(
            DFYToken.transfer(msg.sender, amount),
            "DFY transfer fail"
        );
    }

    function buyIdo(
        address token,
        uint256 amount,
        address referral
    ) external requireOpen payable{
        require(exchangePairs[token].status, "Exchange pair is not exist!");
        if(token==address(0)){
            amount=msg.value;
        }
        uint256 outputDFYAmount =
        (exchangePairs[token].output.mul(amount)).div(
            exchangePairs[token].input
        );

        require(
            outputDFYAmount >= buyMinimum*(10 ** 18),
            "Amount DFY request is too low"
        );

        require(
            boughtAmountTotals[msg.sender] + outputDFYAmount <= buyMaximum*(10 ** 18),
            "Request DFY amount is exceeded!"
        );

        boughtAmountTotals[msg.sender] += outputDFYAmount;

        require(
            DFYToken.balanceOf(address(this)) >= outputDFYAmount,
            "DFY insufficient"
        );

        if(token!=address(0)){
            _transferTokenToOwner(token, amount);
        } else {
            _transferBNBToOwner(amount);
        }

        _transferDFy(outputDFYAmount);

        uint256 referralReceiveAmount = 0;
        if (referral != address(0)
        && referral != msg.sender
        && beReferred[msg.sender] == address(0)
        && referralUserTotal[referral] < maxPersonRef) {
            referralReceiveAmount=_calculateReferral(referral, outputDFYAmount);
        }

        if (referralReceiveAmount > 0) {
            referralRewardTotal[referral] += referralReceiveAmount;
            referralUserTotal[referral] += 1;

            beReferred[msg.sender] = referral;

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
        } else{
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
    }

    function _transferTokenToOwner(address token, uint256 amount) internal {
        IERC20 transferToken = IERC20(token);

        require(
            transferToken.balanceOf(msg.sender) >= amount,
            "Token insufficient"
        );

        require(
            transferToken.transferFrom(msg.sender, owner(), amount),
            "Token transfer fail"
        );
    }

    function _calculateReferral(address referral, uint256 amount) internal view returns (uint256){
        uint256 referralReceiveAmount = 0;
        uint256 expectedReferralReceiveAmount = (amount.mul(refRewardPercent)).div(
            100
        );

        if(referralRewardTotal[referral] + expectedReferralReceiveAmount <= maxRewardFromRef*(10 ** 18)) {
            referralReceiveAmount = expectedReferralReceiveAmount;
        } else {
            referralReceiveAmount = maxRewardFromRef*(10 ** 18) - referralRewardTotal[referral];
        }

        return referralReceiveAmount;
    }

    function getTokenSupport() public view returns (address[] memory) {
        return supportedTokens;
    }

    function getExchangePair(address _tokenAddress) public view returns (address tokenAddress, uint256 output, uint256 input, bool status) {
        return (_tokenAddress, exchangePairs[_tokenAddress].output, exchangePairs[_tokenAddress].input, exchangePairs[_tokenAddress].status);
    }

    function withdrawnBNB() external onlyOwner{
        address owner=owner();
        address payable ownerPayable = address(uint160(owner));
        ownerPayable.transfer(address(this).balance);
    }

    event WithdrawnToken(
        address token,
        uint256 amount,
        address receiveAddress
    );

    function withdrawnToken(address _tokenAddress, uint256 amount) external onlyOwner {
        IERC20 transferToken = IERC20(_tokenAddress);
        require(
            transferToken.balanceOf(address(this)) >= amount,
            "Token insufficient"
        );

        require(
            transferToken.approve(owner(), amount),
            "Token approve failed!"
        );

        require(
            transferToken.transfer(owner(), amount),
            "Token transfer fail"
        );

        emit WithdrawnToken(
            _tokenAddress,
            amount,
            owner()
        );
    }

}

