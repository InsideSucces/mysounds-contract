// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RewardManager} from "../contracts/RewardManager.sol";
import {Presale} from "../contracts/Presale.sol";

contract RedeployPresaleAndReward is Script {
    uint256 internal constant CHAIN_ID = 8453;
    address internal constant SOUND_COIN = 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A;
    uint256 internal constant REWARD_SUPPLY = 62_500_000 * 1e18;
    uint256 internal constant BASE_RATE = 1e18;
    address internal constant BACKEND_ADMIN = 0xA80b312006A918a441f9C4F51b6f773CEFFbB6b3;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 presaleStartTime = vm.envOr("PRESALE_START_TIME", block.timestamp);
        uint256 presaleEndTime = vm.envOr("PRESALE_END_TIME", block.timestamp + 30 days);
        address pairAddress = vm.envOr("PRESALE_PAIR_ADDRESS", address(0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C));
        address usdToken = vm.envOr("PRESALE_USD_TOKEN", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        address payable vaultAddress = payable(vm.envOr("PRESALE_VAULT_ADDRESS", address(0x9A6395F8456a8CDE8Cafc3E67cD5Cf918a42d4cc)));

        console.log("=== Redeploying Presale and RewardManager to Base ===");
        console.log("Deployer:", deployer);
        console.log("SoundCoin:", SOUND_COIN);

        vm.startBroadcast(deployerPrivateKey);

        RewardManager rewardManager = new RewardManager(
            SOUND_COIN,
            REWARD_SUPPLY,
            BASE_RATE,
            deployer,
            BACKEND_ADMIN
        );
        console.log("New RewardManager:", address(rewardManager));

        Presale presale = new Presale(
            SOUND_COIN,
            presaleStartTime,
            presaleEndTime,
            pairAddress,
            usdToken,
            vaultAddress
        );
        console.log("New Presale:", address(presale));

        vm.stopBroadcast();
    }
}
