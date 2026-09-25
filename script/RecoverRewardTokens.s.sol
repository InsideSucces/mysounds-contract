// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {RewardManager} from "../contracts/RewardManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardManager} from "../contracts/interfaces/IRewardManager.sol";

contract RecoverRewardTokens is Script {
    address internal constant TARGET_OLD_CONTRACT = 0x7b6A58D818617F11C858e3C90f84c66056Fb4428;
    address internal constant SOUND_COIN = 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A;
    address internal constant RECIPIENT = 0x79c49aA5743B0f82098045bc8eB2f9AC1e0B6904;
    bytes32 internal constant BACKEND_ROLE = keccak256("BACKEND_ROLE");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Recovering tokens from Old RewardManager ===");
        console.log("Deployer / Admin:", deployer);
        console.log("Target Contract:", TARGET_OLD_CONTRACT);

        RewardManager oldManager = RewardManager(payable(TARGET_OLD_CONTRACT));
        uint256 contractBal = IERC20(SOUND_COIN).balanceOf(TARGET_OLD_CONTRACT);
        console.log("Contract MSC Balance:", contractBal);

        if (contractBal == 0) {
            console.log("Nothing to recover!");
            return;
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. Grant BACKEND_ROLE to deployer if not already granted
        if (!oldManager.hasRole(BACKEND_ROLE, deployer)) {
            oldManager.grantRole(BACKEND_ROLE, deployer);
            console.log("Granted BACKEND_ROLE to deployer");
        }

        // 2. Set baseRate & action weight to ensure effective reward covers contractBal
        oldManager.setBaseRate(contractBal);
        oldManager.setActionWeight(IRewardManager.Action.LIKE_MILESTONE, 1e18);

        // 3. Trigger rewardAction to recipient
        oldManager.rewardAction(RECIPIENT, IRewardManager.Action.LIKE_MILESTONE, "0x");

        vm.stopBroadcast();

        uint256 remainingContractBal = IERC20(SOUND_COIN).balanceOf(TARGET_OLD_CONTRACT);
        uint256 recipientBal = IERC20(SOUND_COIN).balanceOf(RECIPIENT);
        console.log("Remaining Contract Bal:", remainingContractBal);
        console.log("Recipient Bal:", recipientBal);
    }
}
