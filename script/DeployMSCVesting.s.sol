// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MSCVesting} from "../contracts/MSCVesting.sol";
import {vMSC} from "../contracts/vMSC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployMSCVesting is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("BACKEND_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        // Use existing SoundCoin (MSC) address on Base Mainnet
        address mscAddress = vm.envOr("MSC_TOKEN_ADDRESS", address(0x4Bb738eb7604Cfa7520E8a00ec208625ac49752B));
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying with address:", deployerAddress);
        console.log("Using MSC at:", mscAddress);

        // 1. Deploy vMSC
        vMSC vmsc = new vMSC();
        console.log("vMSC deployed at:", address(vmsc));

        // 2. Deploy MSCVesting
        MSCVesting vesting = new MSCVesting(mscAddress, address(vmsc));
        console.log("MSCVesting deployed at:", address(vesting));

        // 3. Transfer ownership of vMSC to Vesting contract
        vmsc.transferOwnership(address(vesting));
        console.log("vMSC ownership transferred to Vesting contract");

        // 4. Configure Categories
        
        // Team: 15% (75M), 1 year cliff, 4 years total
        bytes32 teamCategory = keccak256("TEAM");
        vesting.createVestingCategory(
            teamCategory,
            "Team",
            75_000_000 * 10**18, // 75M
            365 days,            // 1 year cliff
            4 * 365 days         // 4 years total (1460 days)
        );
        console.log("Team category created");

        // Investors: 5% (25M), 6 months cliff, 2 years total
        bytes32 investorCategory = keccak256("INVESTORS");
        vesting.createVestingCategory(
            investorCategory,
            "Investors",
            25_000_000 * 10**18, // 25M
            180 days,            // ~6 months cliff
            2 * 365 days         // 2 years total
        );
        console.log("Investor category created");

        vm.stopBroadcast();
    }
}
