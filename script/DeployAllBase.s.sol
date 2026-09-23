// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";
import {RewardManager} from "../contracts/RewardManager.sol";
import {MusicArtistVoting} from "../contracts/MusicArtistVoting.sol";
import {MSCVesting} from "../contracts/MSCVesting.sol";
import {vMSC} from "../contracts/vMSC.sol";
import {CouponManager} from "../contracts/CouponManager.sol";
import {Presale} from "../contracts/Presale.sol";

contract DeployAllBase is Script {
    uint256 internal constant CHAIN_ID = 8453;
    uint256 internal constant REWARD_SUPPLY = 62_500_000 * 1e18;
    uint256 internal constant BASE_RATE = 1e18;

    struct DeployedContracts {
        address soundCoin;
        address rewardManager;
        address voting;
        address vmsc;
        address vesting;
        address couponManager;
        address presale;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying MySound ecosystem to Base ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", CHAIN_ID);

        DeployedContracts memory c;

        SoundCoin soundCoin = new SoundCoin();
        c.soundCoin = address(soundCoin);
        console.log("SoundCoin:", c.soundCoin);

        RewardManager rewardManager = new RewardManager(
            c.soundCoin,
            REWARD_SUPPLY,
            BASE_RATE,
            deployer,
            deployer
        );
        c.rewardManager = address(rewardManager);
        console.log("RewardManager:", c.rewardManager);

        MusicArtistVoting voting = new MusicArtistVoting(c.soundCoin);
        c.voting = address(voting);
        console.log("MusicArtistVoting:", c.voting);

        vMSC vmsc = new vMSC();
        c.vmsc = address(vmsc);
        console.log("vMSC:", c.vmsc);

        MSCVesting vesting = new MSCVesting(c.soundCoin, c.vmsc);
        c.vesting = address(vesting);
        console.log("MSCVesting:", c.vesting);

        vmsc.transferOwnership(c.vesting);

        vesting.createVestingCategory(
            keccak256("TEAM"),
            "Team",
            75_000_000 * 10 ** 18,
            365 days,
            4 * 365 days
        );

        vesting.createVestingCategory(
            keccak256("INVESTORS"),
            "Investors",
            25_000_000 * 10 ** 18,
            180 days,
            2 * 365 days
        );

        CouponManager couponManager = new CouponManager(c.soundCoin, deployer);
        c.couponManager = address(couponManager);
        console.log("CouponManager:", c.couponManager);

        Presale presale = new Presale(
            c.soundCoin,
            vm.envOr("PRESALE_START_TIME", block.timestamp + 1 hours),
            vm.envOr("PRESALE_END_TIME", block.timestamp + 30 days),
            vm.envOr("PRESALE_PAIR_ADDRESS", address(0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C)),
            vm.envOr("PRESALE_USD_TOKEN", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)),
            payable(vm.envOr("PRESALE_VAULT_ADDRESS", deployer))
        );
        c.presale = address(presale);
        console.log("Presale:", c.presale);

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
            vm.toString(c.soundCoin),
            '",\n',
            '    "RewardManager": "',
            vm.toString(c.rewardManager),
            '",\n',
            '    "MusicArtistVoting": "',
            vm.toString(c.voting),
            '",\n',
            '    "vMSC": "',
            vm.toString(c.vmsc),
            '",\n',
            '    "MSCVesting": "',
            vm.toString(c.vesting),
            '",\n',
            '    "CouponManager": "',
            vm.toString(c.couponManager),
            '",\n',
            '    "Presale": "',
            vm.toString(c.presale),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("deployments/base-8453.json", json);
        console.log("Addresses written to deployments/base-8453.json");
    }
}

