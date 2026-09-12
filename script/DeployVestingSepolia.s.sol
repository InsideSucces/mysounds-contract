// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MSCVesting} from "../contracts/MSCVesting.sol";
import {vMSC} from "../contracts/vMSC.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployVestingSepolia is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying on Sepolia with address:", deployerAddress);

        // 1. Use existing SoundCoin (MSC)
        address mscAddress = 0xdf7DC94eB5e4F9c579260f687894D4d339429CC6;
        SoundCoin msc = SoundCoin(mscAddress);
        console.log("Using SoundCoin (MSC) at:", mscAddress);

        // 2. Deploy NEW vMSC
        vMSC vmsc = new vMSC();
        console.log("NEW vMSC deployed at:", address(vmsc));

        // 3. Deploy NEW MSCVesting
        MSCVesting vesting = new MSCVesting(mscAddress, address(vmsc));
        console.log("NEW MSCVesting deployed at:", address(vesting));

        // 4. Transfer ownership of vMSC to NEW Vesting contract
        vmsc.transferOwnership(address(vesting));
        console.log("vMSC ownership transferred to NEW Vesting contract");

        // 5. Fund Vesting Contract with MSC from deployer balance (fixed-supply token)
        uint256 fundingAmount = 100_000_000 * 10 ** 18;
        require(msc.balanceOf(deployerAddress) >= fundingAmount, "Insufficient MSC balance to fund vesting");
        msc.approve(address(vesting), fundingAmount);
        vesting.deposit(fundingAmount);
        console.log("MSCVesting funded with", fundingAmount / 10 ** 18, "MSC via deposit");

        // 6. Configure Categories

        // Team: 15% (75M), 1 year cliff, 4 years total
        bytes32 teamCategory = keccak256("TEAM");
        vesting.createVestingCategory(
            teamCategory,
            "Team",
            75_000_000 * 10 ** 18, // 75M
            365 days, // 1 year cliff
            4 * 365 days // 4 years total (1460 days)
        );
        console.log("Team category created");

        // Investors: 5% (25M), 6 months cliff, 2 years total
        bytes32 investorCategory = keccak256("INVESTORS");
        vesting.createVestingCategory(
            investorCategory,
            "Investors",
            25_000_000 * 10 ** 18, // 25M
            180 days, // ~6 months cliff
            2 * 365 days // 2 years total
        );
        console.log("Investor category created");

        vm.stopBroadcast();
    }
}
