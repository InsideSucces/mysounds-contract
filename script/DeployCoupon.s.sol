// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CouponManager} from "../contracts/CouponManager.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";

contract DeployCoupon is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address soundCoinAddress = vm.envAddress("SOUNDCOIN_ADDRESS");
        address initialSigner = vm.envAddress("INITIAL_SIGNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        CouponManager manager = new CouponManager(soundCoinAddress, initialSigner);

        console2.log("CouponManager deployed at:", address(manager));

        vm.stopBroadcast();
    }
}
