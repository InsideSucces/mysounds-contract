// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";
import {RewardManager} from "../contracts/RewardManager.sol";
import {MusicArtistVoting} from "../contracts/MusicArtistVoting.sol";
import {MSCVesting} from "../contracts/MSCVesting.sol";
import {vMSC} from "../contracts/vMSC.sol";
import {CouponManager} from "../contracts/CouponManager.sol";

contract DeployAllBase is Script {
    uint256 internal constant CHAIN_ID = 8453;
    uint256 internal constant REWARD_SUPPLY = 62_500_000 * 1e18;
    uint256 internal constant BASE_RATE = 1e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", CHAIN_ID);

        SoundCoin soundCoin = new SoundCoin();
        console.log("SoundCoin:", address(soundCoin));

        RewardManager rewardManager = new RewardManager(
            address(soundCoin),
            REWARD_SUPPLY,
            BASE_RATE,
            deployer,
            deployer
        );
        console.log("RewardManager:", address(rewardManager));

        MusicArtistVoting voting = new MusicArtistVoting(address(soundCoin));
        console.log("MusicArtistVoting:", address(voting));

        vMSC vmsc = new vMSC();
        console.log("vMSC:", address(vmsc));

        MSCVesting vesting = new MSCVesting(address(soundCoin), address(vmsc));
        console.log("MSCVesting:", address(vesting));

        vmsc.transferOwnership(address(vesting));

        bytes32 teamCategory = keccak256("TEAM");
        vesting.createVestingCategory(
            teamCategory,
            "Team",
            75_000_000 * 10 ** 18,
            365 days,
            4 * 365 days
        );

        bytes32 investorCategory = keccak256("INVESTORS");
        vesting.createVestingCategory(
            investorCategory,
            "Investors",
            25_000_000 * 10 ** 18,
            180 days,
            2 * 365 days
        );

        CouponManager couponManager = new CouponManager(address(soundCoin), deployer);
        console.log("CouponManager:", address(couponManager));

        vm.stopBroadcast();

        string memory json = string.concat(
            "{\n",
            '  "network": "base",\n',
            '  "chainId": ',
            vm.toString(CHAIN_ID),
            ",\n",
            '  "deployer": "',
            vm.toString(deployer),
            '",\n',
            '  "deployedAtBlock": "',
            vm.toString(block.number),
            '",\n',
            '  "contracts": {\n',
            '    "SoundCoin": "',
            vm.toString(address(soundCoin)),
            '",\n',
            '    "RewardManager": "',
            vm.toString(address(rewardManager)),
            '",\n',
            '    "MusicArtistVoting": "',
            vm.toString(address(voting)),
            '",\n',
            '    "vMSC": "',
            vm.toString(address(vmsc)),
            '",\n',
            '    "MSCVesting": "',
            vm.toString(address(vesting)),
            '",\n',
            '    "CouponManager": "',
            vm.toString(address(couponManager)),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("deployments/base-8453.json", json);
        console.log("Addresses written to deployments/base-8453.json");
    }
}
