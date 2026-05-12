// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewardManager {
    enum Action {
        SIGNUP,
        LIKE_MILESTONE,
        PURCHASE,
        DAILY_STREAK,
        UPLOAD,
        COMMENT,
        REFERRAL,
        STREAMING,
        EVENT_ATTENDANCE,
        ARTIST_MILESTONE
    }

    event RewardPaid(address indexed user, uint256 amount, Action action, bytes metadata);
    event RewardRateUpdated(uint256 indexed oldBaseRate, uint256 indexed newBaseRate);
    event ManualMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event ActionWeightUpdated(Action action, uint256 oldWeight, uint256 newWeight);

    function rewardAction(address user, Action action, bytes calldata metadata) external;
    function getEffectiveReward(Action action) external view returns (uint256);
    function remainingRewards() external view returns (uint256);
}
