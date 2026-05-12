// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MusicArtistVoting} from "../contracts/MusicArtistVoting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";

contract DeployMusicArtistVoting is Script {
    function setUp() public {}

    function run() public {
        // Retrieve deployment key (BACKEND_PRIVATE_KEY)
        uint256 deployerPrivateKey = vm.envUint("BACKEND_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying with address:", deployerAddress);

        // Retrieve token address from env or use existing SoundCoin (MSC) address on Base Mainnet
        address voteTokenAddress = vm.envOr("VOTE_TOKEN_ADDRESS", address(0x4Bb738eb7604Cfa7520E8a00ec208625ac49752B));
        
        if (voteTokenAddress == address(0)) {
            console.log("VOTE_TOKEN_ADDRESS not set, deploying mock SoundCoin...");
            SoundCoin mockToken = new SoundCoin();
            voteTokenAddress = address(mockToken);
            console.log("Mock SoundCoin deployed at:", voteTokenAddress);
        }

        MusicArtistVoting voting = new MusicArtistVoting(voteTokenAddress);
        console.log("MusicArtistVoting deployed at:", address(voting));

        vm.stopBroadcast();
    }
}
