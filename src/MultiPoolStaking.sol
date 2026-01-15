// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./interfaces/IMultiPoolStaking.sol";
import "./events/MultiPoolEvents.sol";

contract MultiPoolStaking is
    IMultiPoolStaking,
    MultiPoolEvents,
    Ownable,
    ReentrancyGuard
{
    struct Pool {
        IERC20 stakingToken;
        IERC20 rewardingToken;
        uint256 rewardRate;
        uint256 lastRewardTime;
        uint256 accRewardPerShare;
        uint256 totalStaked;
        uint256 lockDuration;
        uint256 endTime;
        uint256 penaltyDuration;
        uint256 maxPenalty;
        bool isPaused;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastStakeTime;
        uint256 lockEnd;
    }

    Pool[] public pools;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public constant PRECISION = 1e18;

    constructor() Ownable(msg.sender) {}

    function createPool(
        IERC20 _stakingToken,
        IERC20 _rewardingToken,
        uint256 _rewardRate,
        uint256 _lockDuration,
        uint256 _endTime,
        uint256 _penaltyDuration,
        uint256 _maxPenalty
    ) external onlyOwner {
        require(
            address(_stakingToken) != address(0),
            "Staking Token address cannot be null"
        );
        require(
            address(_rewardingToken) != address(0),
            "Rewarding token address cannot be null"
        );
        require(_rewardRate > 0, "Reward rate should be greater than 0");
        require(_lockDuration > 0, "Lock Duration should be greater than 0");
        require(_endTime > 0, "End Time should be greater than 0");
        require(_maxPenalty <= 50, "Penalty too high");

        pools.push(
            Pool({
                stakingToken: _stakingToken,
                rewardingToken: _rewardingToken,
                rewardRate: _rewardRate,
                lastRewardTime: block.timestamp,
                accRewardPerShare: 0,
                totalStaked: 0,
                lockDuration: _lockDuration,
                endTime: _endTime,
                penaltyDuration: _penaltyDuration,
                maxPenalty: _maxPenalty,
                isPaused: false
            })
        );

        emit PoolCreated(
            pools.length - 1,
            address(_stakingToken),
            address(_rewardingToken)
        );
    }

    function _updatePool(uint256 _poolId) internal {
        Pool storage pool = pools[_poolId];

        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.totalStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;

        uint256 reward = pool.rewardRate * timeElapsed;

        pool.accRewardPerShare += (reward * PRECISION) / pool.totalStaked;

        pool.lastRewardTime = block.timestamp;
    }

    function _pendingRewards(
        uint256 _poolId,
        address _user
    ) internal view returns (uint256) {
        Pool storage pool = pools[_poolId];

        UserInfo storage user = userInfo[_poolId][_user];

        uint256 tempAccRewardPerShare = pool.accRewardPerShare;

        if (block.timestamp > pool.lastRewardTime && pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;

            uint256 reward = pool.rewardRate * timeElapsed;

            tempAccRewardPerShare += (reward * PRECISION) / pool.totalStaked;
        }

        uint256 pending = (user.amount * tempAccRewardPerShare) /
            PRECISION -
            user.rewardDebt;

        return pending;
    }

    function stake(
        uint256 _poolId,
        uint256 _amount
    ) external override nonReentrant {
        require(_poolId < pools.length, "No such pool exist");

        require(_amount > 0, "Stake amount should be greater than zero");

        Pool storage pool = pools[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];

        require(!pool.isPaused, "Pool is Paused");

        require(
            pool.endTime == 0 || block.timestamp < pool.endTime,
            "Pool Ended"
        );

        _updatePool(_poolId);

        if (user.amount > 0) {
            uint256 pending = _pendingRewards(_poolId, msg.sender);

            if (pending > 0) {
                require(
                    pool.rewardingToken.transfer(msg.sender, pending),
                    "Trnasaction failed of sending reward token"
                );

                emit Claimed(msg.sender, _poolId, pending);
            }
        }

        require(
            pool.stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Staking tokens tranfer failed"
        );

        pool.totalStaked += _amount;
        user.amount += _amount;

        user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;

        user.lastStakeTime = block.timestamp;

        user.lockEnd = block.timestamp + pool.lockDuration;

        emit Staked(msg.sender, _poolId, _amount);
    }

    function withdraw(
        uint256 _poolId,
        uint256 _amount
    ) external override nonReentrant {
        require(_poolId < pools.length, "Pool does not exist");

        Pool storage pool = pools[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];

        require(_amount > 0, "Amount should be greater than zero");
        require(user.amount >= _amount, "Not enough staked");

        _updatePool(_poolId);
        uint256 pending = (user.amount * pool.accRewardPerShare) /
            PRECISION -
            user.rewardDebt;

        if (pending > 0) {
            require(
                pool.rewardingToken.transfer(msg.sender, pending),
                "Pending rewards transfer failed"
            );
        }

        user.amount -= _amount;

        user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;

        pool.totalStaked -= _amount;

        uint256 penaltyPercent = getPenalty(_poolId, msg.sender);

        uint256 penaltyAmount = (_amount * penaltyPercent) / 100;
        uint256 sendAmount = _amount - penaltyAmount;
        require(
            pool.stakingToken.transfer(msg.sender, sendAmount),
            "Withdraw Failed"
        );

        emit Withdrawn(msg.sender, _poolId, sendAmount);

        if (penaltyAmount > 0) {
            require(
                pool.stakingToken.transfer(owner(), penaltyAmount),
                "Penalty transfer failed"
            );

            emit PenaltyTaken(msg.sender, _poolId, penaltyAmount);
        }
    }

    function claim(uint256 _poolId) external override nonReentrant {
        require(_poolId < pools.length, "Pool does not exist");
        Pool storage pool = pools[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];

        _updatePool(_poolId);

        uint256 pending = (user.amount * pool.accRewardPerShare) /
            PRECISION -
            user.rewardDebt;
        require(pending > 0, "Nothing to claim");
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / PRECISION;
        require(
            pool.rewardingToken.transfer(msg.sender, pending),
            "Claim failed"
        );

        emit Claimed(msg.sender, _poolId, pending);
    }

    function emergencyWithdraw(uint256 _poolId) external override nonReentrant {
        require(_poolId < pools.length, "Pool does not exist");
        Pool storage pool = pools[_poolId];
        UserInfo storage user = userInfo[_poolId][msg.sender];

        uint256 userStakeAmount = user.amount;

        require(userStakeAmount > 0, "No staked amount");

        user.amount = 0;
        user.rewardDebt = 0;

        pool.totalStaked -= userStakeAmount;

        require(
            pool.stakingToken.transfer(msg.sender, userStakeAmount),
            "Emergency Withdraw failed"
        );

        emit EmergencyWithdraw(msg.sender, _poolId, userStakeAmount);
    }

    function getPenalty(
        uint256 _poolId,
        address _user
    ) public view returns (uint256) {
        require(_poolId < pools.length, "Pool does not exist");
        Pool storage pool = pools[_poolId];
        UserInfo storage user = userInfo[_poolId][_user];

        if (user.lastStakeTime == 0) {
            return 0;
        }

        uint256 timeStaked = block.timestamp - user.lastStakeTime;
        if (timeStaked >= pool.penaltyDuration) {
            return 0;
        }

        uint256 penalty = (pool.maxPenalty *
            (pool.penaltyDuration - timeStaked)) / pool.penaltyDuration;
        return penalty;
    }

    function pausePool(uint256 _poolId) external onlyOwner {
        require(_poolId < pools.length, "Pool does not exist");
        Pool storage pool = pools[_poolId];

        require(!pool.isPaused, "Pool is already paused");

        pool.isPaused = true;
        emit PoolPaused(_poolId);
    }

    function resumePool(uint256 _poolId) external onlyOwner {
        require(_poolId < pools.length, "Pool does not exist");
        Pool storage pool = pools[_poolId];

        require(pool.isPaused, "Pool is not  paused");

        pool.isPaused = false;
        emit PoolResumed(_poolId);
    }
}
