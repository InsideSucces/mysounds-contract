// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library RewardScaling {
    uint256 internal constant SCALE = 1e18;

    // effective = base * remaining / total
    function byRemainingAllocation(uint256 base, uint256 remaining, uint256 total) internal pure returns (uint256) {
        if (total == 0) return 0;
        return (base * remaining) / total;
    }

    // user penalty: 1 / log2(totalUsers + 2) scaled
    // implement a simple integer log2 approximation
    function userPenalty(uint256 totalUsers) internal pure returns (uint256) {
        // scaling to SCALE
        if (totalUsers == 0) return SCALE;
        uint256 x = totalUsers + 2;
        uint256 l = _floorLog2(x);
        if (l == 0) return SCALE;
        return SCALE / l;
    }

    function applyManualMultiplier(uint256 amount, uint256 manualMultiplier) internal pure returns (uint256) {
        return (amount * manualMultiplier) / SCALE;
    }

    function _floorLog2(uint256 x) private pure returns (uint256) {
        uint256 res = 0;
        while (x > 1) {
            x >>= 1;
            res++;
        }
        return res;
    }
}
