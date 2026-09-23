// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Presale} from "../contracts/Presale.sol";

contract DeployPresale is Script {
    function run() external {
        address soundCoinAddress = vm.envOr("PRESALE_SOUND_COIN", address(0x4Bb738eb7604Cfa7520E8a00ec208625ac49752B));
        uint256 presaleStartTime = vm.envOr("PRESALE_START_TIME", block.timestamp + 3 hours);
        uint256 presaleEndTime = vm.envOr("PRESALE_END_TIME", presaleStartTime + 25 days);
        // Base mainnet Uniswap/Aerodrome or Chainlink WETH/USDC pair and USDC (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
        address ethUsdPairAddress = vm.envOr("PRESALE_PAIR_ADDRESS", address(0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C));
        address usdTokenAddress = vm.envOr("PRESALE_USD_TOKEN", address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        address payable vaultRecipient = payable(vm.envOr("PRESALE_VAULT_ADDRESS", vm.envOr("PRESALE_FEE_RECIPIENT", msg.sender)));

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
            ethUsdPairAddress,
            usdTokenAddress,
            vaultRecipient
        );

        console.log("Presale deployed at:", address(presale));
        console.log("Vault recipient configured:", vaultRecipient);

        vm.stopBroadcast();
    }
}
