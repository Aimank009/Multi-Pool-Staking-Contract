// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMultiPoolStaking {
    function stake(uint256 poolId, uint256 amount) external;
    function withdraw(uint256 poolId, uint256 amount) external;
    function claim(uint256 poolId) external;
    function emergencyWithdraw(uint256 poolId) external;
}
