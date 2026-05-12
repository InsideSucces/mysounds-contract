// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {RewardManager} from "../contracts/RewardManager.sol";

contract DeployRewardManager is Script {
    function run() external {
        // Configuration
        address tokenAddress = 0x4Bb738eb7604Cfa7520E8a00ec208625ac49752B;
        //address testTokenAddress = 0x7Ff631535006c76Cb02e59d5071Da29Cb79340DE;
        uint256 totalSupply = 62_500_000 * 1e18; // 62.5M tokens halfsupply for community reward 125M total
        uint256 baseRate = 1e18; // 1 token base rate
        address backendAdmin = 0xA80b312006A918a441f9C4F51b6f773CEFFbB6b3;

        vm.startBroadcast();

        RewardManager manager = new RewardManager(tokenAddress, totalSupply, baseRate, msg.sender, backendAdmin);
        // Optional: Setup initial roles if needed (admin is msg.sender)
        // address backend = ...;
        // manager.grantRole(manager.BACKEND_ROLE(), backend);

        vm.stopBroadcast();
    }
}
