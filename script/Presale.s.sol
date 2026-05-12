// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Presale} from "../contracts/Presale.sol";

contract DeployPresale is Script {
    function run() external {
        address soundCoinAddress = 0x4Bb738eb7604Cfa7520E8a00ec208625ac49752B;
        uint256 presaleStartTime = block.timestamp + 3 hours;
        uint256 presaleEndTime = presaleStartTime + 25 days;
        address ethUsdPairAddress = 0x88A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C;
        address usdTokenAddress = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        vm.startBroadcast();

        new Presale(soundCoinAddress, presaleStartTime, presaleEndTime, ethUsdPairAddress, usdTokenAddress);

        vm.stopBroadcast();
    }
}
