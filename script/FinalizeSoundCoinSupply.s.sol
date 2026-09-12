// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IDeployedSoundCoin} from "../contracts/interfaces/IDeployedSoundCoin.sol";

/**
 * @notice One-time Base mainnet ops: mint remaining supply to 500M, then disable minting.
 *
 * Usage:
 *   forge script script/FinalizeSoundCoinSupply.s.sol:FinalizeSoundCoinSupply \
 *     --rpc-url $BASE_RPC_URL --broadcast
 *
 * Optional: set RENOUNCE_OWNERSHIP=true to also renounce ownership after disable.
 */
contract FinalizeSoundCoinSupply is Script {
    address internal constant SOUND_COIN = 0xD8de18653E0D6B9b279A259816a4F16ef7cE4a9A;
    uint256 internal constant TARGET_SUPPLY = 500_000_000 * 1e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        bool renounce = vm.envOr("RENOUNCE_OWNERSHIP", false);

        IDeployedSoundCoin msc = IDeployedSoundCoin(SOUND_COIN);

        uint256 currentSupply = msc.totalSupply();
        require(msc.isMintable(), "Minting already disabled");
        require(msc.owner() == deployer, "Caller is not SoundCoin owner");
        require(currentSupply <= TARGET_SUPPLY, "Supply already above target");

        uint256 toMint = TARGET_SUPPLY - currentSupply;

        vm.startBroadcast(deployerPrivateKey);

        if (toMint > 0) {
            console.log("Minting to reach 500M:", toMint);
            msc.mint(deployer, toMint);
        } else {
            console.log("Supply already at 500M; skipping mint");
        }

        msc.disableMinting();
        console.log("Minting disabled. totalSupply:", msc.totalSupply());

        if (renounce) {
            msc.renounceOwnership();
            console.log("Ownership renounced");
        }

        vm.stopBroadcast();

        require(msc.totalSupply() == TARGET_SUPPLY, "Final supply != 500M");
        require(!msc.isMintable(), "Minting still enabled");
    }
}
