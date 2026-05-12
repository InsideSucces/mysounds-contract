// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {RewardManager} from "../contracts/RewardManager.sol";
import {IRewardManager} from "../contracts/interfaces/IRewardManager.sol";

contract UpdateActionWeights is Script {
    function run() external {
        address managerAddress = 0x85C16eE3D3F322A6E074a251e4C99AC162c5c100;
        RewardManager manager = RewardManager(payable(managerAddress));

        uint256 baseRate = 1e16; // 0.01 MSC

        vm.startBroadcast();

        // Update Base Rate
        manager.setBaseRate(baseRate);

        // Update Weights
        manager.setActionWeight(IRewardManager.Action.SIGNUP, 1000); // 10 coins
        manager.setActionWeight(IRewardManager.Action.LIKE_MILESTONE, 20); // 0.2 coins
        manager.setActionWeight(IRewardManager.Action.PURCHASE, 100); // 1 coin
        manager.setActionWeight(IRewardManager.Action.DAILY_STREAK, 30); // 0.3 coins
        manager.setActionWeight(IRewardManager.Action.UPLOAD, 200); // 2 coins
        manager.setActionWeight(IRewardManager.Action.COMMENT, 1); // 0.01 coins
        manager.setActionWeight(IRewardManager.Action.REFERRAL, 500); // 5 coins
        manager.setActionWeight(IRewardManager.Action.STREAMING, 5); // 0.05 coins
        manager.setActionWeight(IRewardManager.Action.EVENT_ATTENDANCE, 50); // 0.5 coins
        manager.setActionWeight(IRewardManager.Action.ARTIST_MILESTONE, 400); // 4 coins

        vm.stopBroadcast();
    }
}
