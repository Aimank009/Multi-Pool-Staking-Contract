# Multi-Pool Staking Contract (MPSC)

A production-grade ERC20 staking protocol that enables multiple independent staking pools with time-based rewards, early withdrawal penalties, and comprehensive admin controls.

## Overview

Multi-Pool Staking Contract allows protocol administrators to create and manage multiple staking pools, each with its own reward token, reward rate, lock duration, and penalty structure. Users can stake tokens across different pools and earn proportional rewards based on their share of the pool.

## Key Features

- **Multiple Independent Pools** - Deploy unlimited staking pools from a single contract
- **Reward-Per-Share Accounting** - Gas-efficient MasterChef-style reward distribution
- **Time-Based Rewards** - Continuous reward accrual based on time staked
- **Early Withdrawal Penalties** - Configurable sliding-scale penalty that decreases over time
- **Pool Lifecycle Management** - Pause, resume, and set end times for pools
- **Emergency Withdraw** - Users can exit immediately, forfeiting pending rewards

## Architecture

```
src/
├── MultiPoolStaking.sol         # Main contract
├── interfaces/
│   └── IMultiPoolStaking.sol    # External interface
└── events/
    └── MultiPoolEvents.sol      # Event definitions
```

## Core Concepts

### Reward Accounting

Uses the proven MasterChef algorithm:
- `accRewardPerShare` - Accumulated rewards per staked token
- `rewardDebt` - User's reward debt at time of deposit
- Pending rewards = (userAmount × accRewardPerShare) - rewardDebt

### Penalty System

Early withdrawal penalty decreases linearly over time:
```
penalty = maxPenalty × (penaltyDuration - timeStaked) / penaltyDuration
```

If user withdraws at 50% of penalty duration, they pay 50% of max penalty.

## Contract Functions

### User Functions

| Function | Description |
|----------|-------------|
| `stake(poolId, amount)` | Deposit tokens into a pool |
| `withdraw(poolId, amount)` | Withdraw tokens (may incur penalty) |
| `claim(poolId)` | Claim pending rewards only |
| `emergencyWithdraw(poolId)` | Exit immediately, forfeit rewards |

### Admin Functions

| Function | Description |
|----------|-------------|
| `createPool(...)` | Create a new staking pool |
| `pausePool(poolId)` | Pause deposits to a pool |
| `resumePool(poolId)` | Resume a paused pool |

### View Functions

| Function | Description |
|----------|-------------|
| `getPenalty(poolId, user)` | Current penalty percentage for user |
| `pools(poolId)` | Pool configuration details |
| `userInfo(poolId, user)` | User's staking info in a pool |

## Pool Configuration

Each pool is configured with:

| Parameter | Description |
|-----------|-------------|
| `stakingToken` | Token users deposit |
| `rewardingToken` | Token users earn |
| `rewardRate` | Tokens distributed per second |
| `lockDuration` | Minimum lock period |
| `endTime` | When rewards stop |
| `penaltyDuration` | Time until penalty reaches zero |
| `maxPenalty` | Maximum penalty percentage (≤50%) |

## Security Features

- **ReentrancyGuard** - Protection against reentrancy attacks
- **Ownable** - Admin-only functions restricted to owner
- **CEI Pattern** - Checks-Effects-Interactions ordering
- **Safe Transfers** - Uses standard ERC20 transfer methods

## Usage

### Build
```bash
forge build
```

### Test
```bash
forge test
```

### Deploy
```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <KEY>
```

## Dependencies

- OpenZeppelin Contracts v5.0
  - IERC20
  - Ownable
  - ReentrancyGuard

## License

MIT
