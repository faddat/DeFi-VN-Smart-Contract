pragma solidity ^0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract Staking is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    address public admin;
    address public coldWallet;
    uint256 public minStakeAmount;

    uint256 public ZOOM = 100;
    uint256 public SECOND_IN_DAY = 86400;
    uint256 public DAY_IN_YEAR = 365;
    address public DFY = 0xD98560689C6e748DC37bc410B4d3096B1aA3D8C2;
    uint256 public totalVolume;

    function pause() onlyOwner public {
        _pause();
    }

    function unPause() onlyOwner public {
        _unpause();
    }

    modifier onlyOwnerOrAdmin() {
        if (msg.sender != admin && msg.sender != owner()) {
            revert();
        }
        _;
    }

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    uint256 public numberPools;

    enum PoolStatus {CLOSE, OPEN, PAUSE}

    struct Pool {
        address token;
        uint256 apy;
        uint256 duration;
        PoolStatus status;
    }

    enum StakingStatus {AVAILABLE, CLOSE}
    struct StakingData {
        uint256 balance;
        uint256 stakeFrom;
        uint256 pid;
        uint256 stakeTo;
        uint256 apy;
        StakingStatus status;
    }

    event NewPool(
        uint256 _pid,
        uint256 _apy,
        uint256 _duration
    );

    event UpdatePool(
        uint256 _pid,
        uint256 _apy,
        uint256 _duration
    );

    event Stake(
        address _staker,
        uint256 _pid,
        uint256 _sid,
        uint256 _amount,
        uint256 _stakeFrom,
        uint256 _stakeTo
    );

    event Claim(
        address _toAddress,
        uint256 _reward,
        uint256 _sid
    );

    event Withdraw(
        address _toAddress,
        uint256 _sid
    );

    mapping (uint256 => Pool) public stakingPools;
    mapping (address => mapping (uint256 => StakingData)) public stakingData;
    mapping (address => uint256) public numberStakeTime;

    constructor () public {
        coldWallet = address(this);
        numberPools = 0;
        minStakeAmount = 0;
        totalVolume = 0;
    }

    function newPool(uint256 _apy, uint256 _duration)
    public onlyOwnerOrAdmin
    returns (uint256 _idx)
    {
        _idx = numberPools;
        Pool storage pool = stakingPools[_idx];
        pool.apy = _apy;
        pool.duration = _duration;
        pool.status = PoolStatus.OPEN;

        emit NewPool(_idx, _apy, _duration);
        ++numberPools;
    }

    function updatePool(uint256 _pid, uint256 _apy, uint256 _duration, uint256 _status)
    public onlyOwnerOrAdmin
    {
        Pool storage pool = stakingPools[_pid];
        pool.apy = _apy;
        pool.duration = _duration;
        pool.status = PoolStatus(_status);

        emit UpdatePool(_pid, _apy, _duration);
    }

    function reward(address _staker, uint256 _sid)
    public view
    returns (uint256 _reward)

    {
        StakingData memory data = stakingData[_staker][_sid];
        uint256 calculateTime = block.timestamp;
        if (data.stakeTo < calculateTime) {
            calculateTime = data.stakeTo;
        }
        calculateTime = calculateTime - data.stakeFrom;
        _reward = data.balance.mul(calculateTime).mul(data.apy).div(DAY_IN_YEAR * SECOND_IN_DAY).div(ZOOM);
    }

    function totalReward(address _staker)
    public view
    returns (uint256 _totalReward)
    {
        _totalReward = 0;
        uint256 nStakeTime = numberStakeTime[_staker];
        for (uint i = 0; i < nStakeTime; i++) {
            _totalReward = _totalReward.add(reward(_staker, i));
        }
    }

    function executeStake(address _staker, uint256 _pid, uint256 _amount)
    internal
    returns (uint256 _sid)
    {
        ERC20(DFY).safeTransferFrom(_staker, coldWallet, _amount);
        Pool memory pool = stakingPools[_pid];
        _sid = numberStakeTime[_staker];
        StakingData storage data = stakingData[_staker][_sid];
        data.balance = _amount;
        data.stakeFrom = block.timestamp;
        data.pid = _pid;
        data.status = StakingStatus.AVAILABLE;
        data.stakeTo = data.stakeFrom + pool.duration;
        data.apy = pool.apy;

        emit Stake(_staker, _pid, _sid, _amount, data.stakeFrom, data.stakeTo);
        numberStakeTime[msg.sender] = _sid + 1;
    }

    function stake(uint256 _pid, uint256 _amount)
    public
    whenNotPaused
    returns (uint256 _sid)
    {
        Pool memory pool = stakingPools[_pid];
        require(pool.status == PoolStatus.OPEN, 'Pool unavailable');
        require(_amount >= minStakeAmount, 'Less than min stake amount');
        totalVolume = totalVolume.add(_amount);
        _sid = executeStake(msg.sender, _pid, _amount);
    }

    function withdraw()
    public
    whenNotPaused
    {
        uint256 nStakeTime = numberStakeTime[msg.sender];

        for (uint i = 0; i < nStakeTime; i++) {
            StakingData storage data = stakingData[msg.sender][i];
            if (data.status == StakingStatus.AVAILABLE) {
                uint256 reward = reward(msg.sender, i);
                IERC20(DFY).transfer(msg.sender, reward);
                emit Claim(msg.sender, reward, i);
                data.stakeFrom = block.timestamp;
                if (data.stakeFrom > data.stakeTo) {
                    data.stakeFrom = data.stakeTo;
                }

                if (data.stakeTo <= block.timestamp) {
                    IERC20(DFY).transfer(msg.sender, data.balance);
                    emit Withdraw(msg.sender, i);
                    totalVolume = totalVolume.sub(data.balance);
                    data.balance = 0;
                    data.status = StakingStatus.CLOSE;
                }
            }
        }

    }

    function claim()
    public
    whenNotPaused
    {
        uint256 nStakeTime = numberStakeTime[msg.sender];

        for (uint i = 0; i < nStakeTime; i++) {
            StakingData storage data = stakingData[msg.sender][i];
            if (data.status == StakingStatus.AVAILABLE) {
                uint256 reward = reward(msg.sender, i);
                IERC20(DFY).transfer(msg.sender, reward);
                emit Claim(msg.sender, reward, i);
                data.stakeFrom = block.timestamp;
                if (data.stakeFrom > data.stakeTo) {
                    data.stakeFrom = data.stakeTo;
                }
            }
        }
    }

    function emergencyWithdraw()
    public onlyOwner
    whenPaused
    {
        uint256 balance = IERC20(DFY).balanceOf(coldWallet);
        IERC20(DFY).transfer(owner(), balance);
    }
}
