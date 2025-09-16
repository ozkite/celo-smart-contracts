// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title CeloStaking
 * @dev A staking contract for Celo Network with claimable or auto-compounded rewards
 */
contract CeloStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // === TOKENS ===
    IERC20 public stakingToken;  // e.g., cUSD or CELO
    IERC20 public rewardToken;   // e.g., CELO or governance token

    // === STAKING PARAMETERS ===
    uint256 public rewardRate = 100; // 100 tokens per block (adjustable)
    uint256 public startBlock;
    uint256 public rewardPerTokenStored;

    // === USER DATA ===
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public stakedBalance;
    uint256 public totalStaked;

    // === EVENTS ===
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);
    event Recovered(address token, uint256 amount);

    // === MODIFIERS ===
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // === CONSTRUCTOR ===
    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _startBlock
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        startBlock = _startBlock;
    }

    // === VIEWS ===
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + (
            (block.number >= startBlock ? block.number - startBlock : 0) * rewardRate * 1e18
        ) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return (stakedBalance[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    // === STAKE ===
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount);
    }

    // === WITHDRAW ===
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0 && amount <= stakedBalance[msg.sender], "Invalid amount");
        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // === CLAIM REWARDS ===
    function claim() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    // === COMPOUND: Stake rewards automatically ===
    function compound() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to compound");
        rewards[msg.sender] = 0;
        stakedBalance[msg.sender] += reward;
        totalStaked += reward;
        emit RewardPaid(msg.sender, reward);
        emit Staked(msg.sender, reward);
    }

    // === OWNER: Update reward rate ===
    function setRewardRate(uint256 rate) external onlyOwner {
        rewardRate = rate;
        emit RewardRateUpdated(rate);
    }

    // === EMERGENCY: Recover ERC20 tokens (except staking/reward) ===
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(stakingToken), "Cannot recover staking token");
        require(token != address(rewardToken), "Cannot recover reward token");
        IERC20(token).safeTransfer(owner(), amount);
        emit Recovered(token, amount);
    }

    // === SET START BLOCK (if needed) ===
    function setStartBlock(uint256 blockNumber) external onlyOwner {
        require(block.number < startBlock, "Already started");
        startBlock = blockNumber;
    }
}
