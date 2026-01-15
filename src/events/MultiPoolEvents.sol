// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract MultiPoolEvents {
    event PoolCreated(
        uint256 indexed poolId,
        address stakingToken,
        address rewardToken
    );
    event Staked(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdrawn(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event Claimed(address indexed user, uint256 indexed poolId, uint256 reward);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event PenaltyTaken(
        address indexed user,
        uint256 indexed poolId,
        uint256 penaltyAmount
    );
    event PoolPaused(uint256 indexed poolId);
    event PoolResumed(uint256 indexed poolId);
}
