pragma solidity ^0.7.0;

import "@vittominacori/erc20-token/contracts/ERC20Base.sol";
import "@vittominacori/erc20-token/contracts/access/Roles.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract DFY is ERC20Base, Pausable {

    constructor () ERC20Base(
        "DeFi For You.", 
        "DFY", 
        18, 
        1e27, 
        1e27, 
        false
    ) {}

    // Add required getOwner
    function getOwner() external view returns (address) {
        return owner();
    }

    // Override ERC20Base before transfer to allow pauseable contract
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20Base) {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), "ERC20Pausable: token transfer while paused");
    }

    // Override transferOwnership to grant role
    function transferOwnership(address newOwner) public virtual onlyOwner override(Ownable) {
        super.transferOwnership(newOwner);
        grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        grantRole(MINTER_ROLE, newOwner);
        grantRole(OPERATOR_ROLE, newOwner);

        revokeRole(OPERATOR_ROLE, _msgSender());
        revokeRole(MINTER_ROLE, _msgSender());
        revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    // Functions for reward reputations

    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _pawnReputationScore;
    bool private _rewardPawnReputationEnabled = true;

    event RewardPawnReputationEnabled();
    event RewardPawnReputationDisabled();
    event PawnReputationRewarded(address indexed to, uint256 score);
    event PawnReputationReduced(address indexed to, uint256 score);    

    function rewardPawnReputationEnabled() public view returns (bool) {
        return _rewardPawnReputationEnabled;
    }

    modifier canRewardPawnReputation() {
        require(
            _rewardPawnReputationEnabled && hasRole(OPERATOR_ROLE, _msgSender())
            , "DFY: Reward Pawn Reputation is disabled or caller doesn't have permission to do this");
        _;
    }

    function enableRewardPawnReputation() public onlyOwner {
        _rewardPawnReputationEnabled = true;

        emit RewardPawnReputationEnabled();
    }

    function disableRewardPawnReputation() public onlyOwner {
        _rewardPawnReputationEnabled = false;

        emit RewardPawnReputationDisabled();
    }

    function pawnReputationOf(address account) public view returns (uint256) {
        return _pawnReputationScore[account];
    }

    function rewardPawnReputation(address to, uint256 score) public canRewardPawnReputation whenNotPaused returns (uint256) {
        _rewardPawnReputation(to, score);
        return _pawnReputationScore[to];
    }

    function reducePawnReputation(address to, uint256 score) public canRewardPawnReputation whenNotPaused returns (uint256) {
        _reducePawnReputation(to, score);
        return _pawnReputationScore[to];
    }

    function _rewardPawnReputation(address to, uint256 score) internal virtual {
        require(to != address(0), "DFY: Reward pawn reputation to the zero address");

        _pawnReputationScore[to] = _pawnReputationScore[to].add(score);
        emit PawnReputationRewarded(to, score);
    }

    function _reducePawnReputation(address to, uint256 score) internal virtual {
        require(to != address(0), "DFY: Reward pawn reputation to the zero address");

        _pawnReputationScore[to] = _pawnReputationScore[to].sub(score, "ERC20: reduce amount exceeds balance");
        emit PawnReputationReduced(to, score);
    }
}
