// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RewardManager} from "../contracts/RewardManager.sol";

contract DeployRewardManager is Script {
    address internal constant SOUND_COIN = 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A;
    uint256 internal constant REWARD_SUPPLY = 62_500_000 * 1e18;
    uint256 internal constant BASE_RATE = 1e18; // 1 MSC base rate
    address internal constant BACKEND_ADMIN = 0xA80b312006A918a441f9C4F51b6f773CEFFbB6b3;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deploying RewardManager to Base ===");
        console.log("Deployer:", deployer);
        console.log("SoundCoin:", SOUND_COIN);

        vm.startBroadcast(deployerPrivateKey);

        RewardManager manager = new RewardManager(
            SOUND_COIN,
            REWARD_SUPPLY,
            BASE_RATE,
            deployer,
            BACKEND_ADMIN
        );

        console.log("Newly Deployed RewardManager:", address(manager));

        vm.stopBroadcast();
    }
}
