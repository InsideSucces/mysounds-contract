// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Presale} from "../contracts/Presale.sol";

contract DeployPresale is Script {
    function run() external {
        address soundCoinAddress = vm.envOr("PRESALE_SOUND_COIN", address(0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A));
        // Default start: Monday Sept 28, 2026 00:00:00 UTC (1790553600)
        uint256 presaleStartTime = vm.envOr("PRESALE_START_TIME", uint256(1790553600));
        uint256 presaleEndTime = vm.envOr("PRESALE_END_TIME", presaleStartTime + 30 days);
        // Base mainnet Chainlink ETH/USD Price Feed (0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70)
        address priceFeedAddress = vm.envOr("PRESALE_PRICE_FEED", address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70));
        address payable vaultRecipient = payable(vm.envOr("PRESALE_VAULT_ADDRESS", address(0x9A6395F8456a8CDE8Cafc3E67cD5Cf918a42d4cc)));

        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        } else {
            vm.startBroadcast();
        }

        Presale presale = new Presale(
            soundCoinAddress,
            presaleStartTime,
            presaleEndTime,
            priceFeedAddress,
            vaultRecipient
        );

        console.log("Presale deployed at:", address(presale));
        console.log("Vault recipient configured:", vaultRecipient);
        console.log("Price feed configured:", priceFeedAddress);
        console.log("Presale start time:", presaleStartTime);
        console.log("Presale end time:", presaleEndTime);

        vm.stopBroadcast();
    }
}
