// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRewardError {
    error NullAddress(address addr);

    error InsufficientPermission(address caller);
    error InvalidMultiplier(uint256 multiplier);
    error TooSoonForAction(
        address user, uint256 action, uint256 lastTimestamp, uint256 currentTimestamp, uint256 minInterval
    );
}
