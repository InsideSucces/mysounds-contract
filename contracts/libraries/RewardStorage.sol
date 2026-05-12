// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library RewardStorage {
    struct Layout {
        uint256 totalRewardSupply;
        uint256 totalDistributed;
        uint256 baseRate; // base tokens per unit weight (scaled to 1e18 interpretation)
        uint256 manualMultiplier; // scaled by 1e18
        uint256 totalUsers;
        address token;
        mapping(address => uint256) lifetimeRewards;
        mapping(address => bool) hasSignedUp;
        mapping(uint256 => uint256) actionWeights; // action enum -> weight
        mapping(address => mapping(uint256 => uint256)) lastActionTimestamp; // user -> action -> timestamp
        mapping(address => mapping(uint256 => bytes)) lastActionMetadata; // user -> action -> metadata
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("mysounds.reward.storage.v1");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
    }
}
