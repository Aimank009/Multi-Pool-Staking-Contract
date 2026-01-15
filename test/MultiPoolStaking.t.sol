// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MultiPoolStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MultiPoolStakingTest is Test {
    MultiPoolStaking public staking;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    uint256 public constant REWARD_RATE = 1e18;
    uint256 public constant LOCK_DURATION = 7 days;
    uint256 public constant END_TIME = 30 days;
    uint256 public constant PENALTY_DURATION = 3 days;
    uint256 public constant MAX_PENALTY = 10;

    function setUp() public {
        stakingToken = new MockERC20("Stake Token", "STK");
        rewardToken = new MockERC20("Reward Token", "RWD");
        staking = new MultiPoolStaking();

        stakingToken.mint(user1, 10000e18);
        stakingToken.mint(user2, 10000e18);
        rewardToken.mint(address(staking), 1000000e18);

        vm.prank(user1);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        stakingToken.approve(address(staking), type(uint256).max);
    }

    function createDefaultPool() internal {
        staking.createPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken)),
            REWARD_RATE,
            LOCK_DURATION,
            block.timestamp + END_TIME,
            PENALTY_DURATION,
            MAX_PENALTY
        );
    }

    function test_CreatePool() public {
        createDefaultPool();
        (
            IERC20 sToken,
            IERC20 rToken,
            uint256 rate,
            ,
            ,
            uint256 totalStaked,
            ,
            ,
            ,
            ,
            bool isPaused
        ) = staking.pools(0);

        assertEq(address(sToken), address(stakingToken));
        assertEq(address(rToken), address(rewardToken));
        assertEq(rate, REWARD_RATE);
        assertEq(totalStaked, 0);
        assertEq(isPaused, false);
    }

    function test_CreatePoolRevertsZeroStakingToken() public {
        vm.expectRevert("Staking Token address cannot be null");
        staking.createPool(
            IERC20(address(0)),
            IERC20(address(rewardToken)),
            REWARD_RATE,
            LOCK_DURATION,
            block.timestamp + END_TIME,
            PENALTY_DURATION,
            MAX_PENALTY
        );
    }

    function test_CreatePoolRevertsHighPenalty() public {
        vm.expectRevert("Penalty too high");
        staking.createPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken)),
            REWARD_RATE,
            LOCK_DURATION,
            block.timestamp + END_TIME,
            PENALTY_DURATION,
            51
        );
    }

    function test_Stake() public {
        createDefaultPool();
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        staking.stake(0, stakeAmount);

        (uint256 amount, , , ) = staking.userInfo(0, user1);
        assertEq(amount, stakeAmount);

        (, , , , , uint256 totalStaked, , , , , ) = staking.pools(0);
        assertEq(totalStaked, stakeAmount);
    }

    function test_StakeRevertsZeroAmount() public {
        createDefaultPool();

        vm.prank(user1);
        vm.expectRevert("Stake amount should be greater than zero");
        staking.stake(0, 0);
    }

    function test_StakeRevertsInvalidPool() public {
        vm.prank(user1);
        vm.expectRevert("No such pool exist");
        staking.stake(99, 1000e18);
    }

    function test_StakeRevertsPausedPool() public {
        createDefaultPool();
        staking.pausePool(0);

        vm.prank(user1);
        vm.expectRevert("Pool is Paused");
        staking.stake(0, 1000e18);
    }

    function test_WithdrawAfterPenaltyDuration() public {
        createDefaultPool();
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        staking.stake(0, stakeAmount);

        vm.warp(block.timestamp + PENALTY_DURATION + 1);

        uint256 balanceBefore = stakingToken.balanceOf(user1);
        vm.prank(user1);
        staking.withdraw(0, stakeAmount);
        uint256 balanceAfter = stakingToken.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, stakeAmount);
    }

    function test_WithdrawWithPenalty() public {
        createDefaultPool();
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        staking.stake(0, stakeAmount);

        vm.warp(block.timestamp + 1 days);

        uint256 penaltyPercent = staking.getPenalty(0, user1);
        uint256 expectedPenalty = (stakeAmount * penaltyPercent) / 100;
        uint256 expectedReceive = stakeAmount - expectedPenalty;

        uint256 balanceBefore = stakingToken.balanceOf(user1);
        vm.prank(user1);
        staking.withdraw(0, stakeAmount);
        uint256 balanceAfter = stakingToken.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, expectedReceive);
    }

    function test_WithdrawRevertsInsufficientBalance() public {
        createDefaultPool();

        vm.prank(user1);
        staking.stake(0, 1000e18);

        vm.prank(user1);
        vm.expectRevert("Not enough staked");
        staking.withdraw(0, 2000e18);
    }

    function test_Claim() public {
        createDefaultPool();
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        staking.stake(0, stakeAmount);

        vm.warp(block.timestamp + 100);

        uint256 rewardBalanceBefore = rewardToken.balanceOf(user1);
        vm.prank(user1);
        staking.claim(0);
        uint256 rewardBalanceAfter = rewardToken.balanceOf(user1);

        assertGt(rewardBalanceAfter, rewardBalanceBefore);
    }

    function test_ClaimRevertsNothingToClaim() public {
        createDefaultPool();

        vm.prank(user1);
        staking.stake(0, 1000e18);

        vm.warp(block.timestamp + 100);

        vm.prank(user1);
        staking.claim(0);

        vm.prank(user1);
        vm.expectRevert("Nothing to claim");
        staking.claim(0);
    }

    function test_EmergencyWithdraw() public {
        createDefaultPool();
        uint256 stakeAmount = 1000e18;

        vm.prank(user1);
        staking.stake(0, stakeAmount);

        vm.warp(block.timestamp + 100);

        uint256 balanceBefore = stakingToken.balanceOf(user1);
        vm.prank(user1);
        staking.emergencyWithdraw(0);
        uint256 balanceAfter = stakingToken.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, stakeAmount);

        (uint256 amount, uint256 rewardDebt, , ) = staking.userInfo(0, user1);
        assertEq(amount, 0);
        assertEq(rewardDebt, 0);
    }

    function test_EmergencyWithdrawRevertsNoStake() public {
        createDefaultPool();

        vm.prank(user1);
        vm.expectRevert("No staked amount");
        staking.emergencyWithdraw(0);
    }

    function test_PausePool() public {
        createDefaultPool();
        staking.pausePool(0);

        (, , , , , , , , , , bool isPaused) = staking.pools(0);
        assertEq(isPaused, true);
    }

    function test_PausePoolRevertsAlreadyPaused() public {
        createDefaultPool();
        staking.pausePool(0);

        vm.expectRevert("Pool is already paused");
        staking.pausePool(0);
    }

    function test_ResumePool() public {
        createDefaultPool();
        staking.pausePool(0);
        staking.resumePool(0);

        (, , , , , , , , , , bool isPaused) = staking.pools(0);
        assertEq(isPaused, false);
    }

    function test_ResumePoolRevertsNotPaused() public {
        createDefaultPool();

        vm.expectRevert("Pool is not  paused");
        staking.resumePool(0);
    }

    function test_GetPenalty() public {
        createDefaultPool();

        vm.prank(user1);
        staking.stake(0, 1000e18);

        uint256 penaltyAtStart = staking.getPenalty(0, user1);
        assertEq(penaltyAtStart, MAX_PENALTY);

        vm.warp(block.timestamp + PENALTY_DURATION);
        uint256 penaltyAfterDuration = staking.getPenalty(0, user1);
        assertEq(penaltyAfterDuration, 0);
    }

    function test_GetPenaltyDecreases() public {
        createDefaultPool();

        vm.prank(user1);
        staking.stake(0, 1000e18);

        uint256 penalty1 = staking.getPenalty(0, user1);

        vm.warp(block.timestamp + 1 days);
        uint256 penalty2 = staking.getPenalty(0, user1);

        vm.warp(block.timestamp + 1 days);
        uint256 penalty3 = staking.getPenalty(0, user1);

        assertGt(penalty1, penalty2);
        assertGt(penalty2, penalty3);
    }

    function test_MultipleUsers() public {
        createDefaultPool();

        vm.prank(user1);
        staking.stake(0, 1000e18);

        vm.prank(user2);
        staking.stake(0, 2000e18);

        (, , , , , uint256 totalStaked, , , , , ) = staking.pools(0);
        assertEq(totalStaked, 3000e18);

        (uint256 amount1, , , ) = staking.userInfo(0, user1);
        (uint256 amount2, , , ) = staking.userInfo(0, user2);
        assertEq(amount1, 1000e18);
        assertEq(amount2, 2000e18);
    }

    function test_RewardsDistributedProportionally() public {
        createDefaultPool();

        vm.prank(user1);
        staking.stake(0, 1000e18);

        vm.prank(user2);
        staking.stake(0, 3000e18);

        vm.warp(block.timestamp + 100);

        uint256 reward1Before = rewardToken.balanceOf(user1);
        vm.prank(user1);
        staking.claim(0);
        uint256 reward1After = rewardToken.balanceOf(user1);

        uint256 reward2Before = rewardToken.balanceOf(user2);
        vm.prank(user2);
        staking.claim(0);
        uint256 reward2After = rewardToken.balanceOf(user2);

        uint256 user1Reward = reward1After - reward1Before;
        uint256 user2Reward = reward2After - reward2Before;

        assertGt(user2Reward, user1Reward);
    }

    function test_OnlyOwnerCanCreatePool() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.createPool(
            IERC20(address(stakingToken)),
            IERC20(address(rewardToken)),
            REWARD_RATE,
            LOCK_DURATION,
            block.timestamp + END_TIME,
            PENALTY_DURATION,
            MAX_PENALTY
        );
    }

    function test_OnlyOwnerCanPausePool() public {
        createDefaultPool();

        vm.prank(user1);
        vm.expectRevert();
        staking.pausePool(0);
    }

    function test_OnlyOwnerCanResumePool() public {
        createDefaultPool();
        staking.pausePool(0);

        vm.prank(user1);
        vm.expectRevert();
        staking.resumePool(0);
    }
}
