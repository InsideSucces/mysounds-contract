// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MusicArtistVoting} from "../contracts/MusicArtistVoting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";

contract DeployMusicArtistVoting is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("=== Deploying MusicArtistVoting to Base ===");
        console.log("Deployer:", deployerAddress);

        address voteTokenAddress = vm.envOr("VOTE_TOKEN_ADDRESS", address(0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A));
        console.log("Vote Token (MSC):", voteTokenAddress);

        vm.startBroadcast(deployerPrivateKey);

        MusicArtistVoting voting = new MusicArtistVoting(voteTokenAddress);
        console.log("New MusicArtistVoting deployed at:", address(voting));

        vm.stopBroadcast();
    }
}
