// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MSCVesting} from "../contracts/MSCVesting.sol";
import {vMSC} from "../contracts/vMSC.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";

contract MSCVestingTest is Test {
    MSCVesting public vesting;
    vMSC public vmsc;
    SoundCoin public msc;

    address public owner;
    address public beneficiary1;
    address public beneficiary2;

    bytes32 public constant TEAM_CATEGORY = keccak256("TEAM");
    
    function setUp() public {
        owner = address(this);
        beneficiary1 = address(0x123);
        beneficiary2 = address(0x456);

        // Deploy tokens
        msc = new SoundCoin();
        vmsc = new vMSC();

        // Deploy vesting
        vesting = new MSCVesting(address(msc), address(vmsc));

        // Transfer vMSC ownership to vesting
        vmsc.transferOwnership(address(vesting));

        // Fund vesting contract from constructor mint (500M to deployer)
        msc.transfer(address(vesting), 200_000_000 * 10**18);

        // Create Team Category
        // Cap: 75M, Cliff: 1 year (365 days), Duration: 4 years (1460 days)
        vesting.createVestingCategory(
            TEAM_CATEGORY,
            "Team",
            75_000_000 * 10**18,
            365 days,
            1460 days
        );
    }

    function test_CategoryCreation() public view {
        (string memory name, uint256 cap, uint256 totalAllocated, uint256 cliff, uint256 duration, bool exists) 
            = vesting.categories(TEAM_CATEGORY);
        
        assertTrue(exists);
        assertEq(name, "Team");
        assertEq(cap, 75_000_000 * 10**18);
        assertEq(cliff, 365 days);
        assertEq(duration, 1460 days);
        assertEq(totalAllocated, 0);
    }

    function test_CreateVestingSchedule() public {
        uint256 amount = 1_000_000 * 10**18;
        vesting.createVestingSchedule(
            beneficiary1,
            TEAM_CATEGORY,
            amount,
            block.timestamp
        );

        // Check vMSC balance (minted 1:1)
        assertEq(vmsc.balanceOf(beneficiary1), amount);

        // Check Schedule
        (bytes32 catId, uint256 totalAllocated, uint256 claimed, uint256 startTime, bool revoked) 
            = vesting.schedules(beneficiary1);
        
        assertEq(catId, TEAM_CATEGORY);
        assertEq(totalAllocated, amount);
        assertEq(claimed, 0);
        assertEq(startTime, block.timestamp);
        assertEq(revoked, false);
    }

    function test_CliffPeriod() public {
        uint256 amount = 1_000_000 * 10**18;
        uint256 startTime = block.timestamp;
        
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, startTime);

        // Move to just before cliff
        vm.warp(startTime + 365 days - 1 seconds);
        
        uint256 claimable = vesting.getClaimableAmount(beneficiary1);
        assertEq(claimable, 0, "Should be 0 before cliff");
    }

    function test_VestingAfterCliffAndLinearity() public {
        uint256 amount = 1_000_000 * 10**18;
        uint256 startTime = block.timestamp;
        
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, startTime);

        // Move to exactly cliff (1 year / 365 days)
        // 365 days / 1460 days = 0.25 (25%)
        vm.warp(startTime + 365 days);
        
        uint256 claimable = vesting.getClaimableAmount(beneficiary1);
        uint256 expected = amount * 365 / 1460;
        
        assertApproxEqAbs(claimable, expected, 1e18); // Allow small rounding diff

        // Move to halfway (2 years)
        // 730 / 1460 = 0.5 (50%)
        vm.warp(startTime + 730 days);
        claimable = vesting.getClaimableAmount(beneficiary1);
        expected = amount * 730 / 1460;
        
        assertApproxEqAbs(claimable, expected, 1e18);
    }

    function test_Claiming() public {
        uint256 amount = 1_000_000 * 10**18;
        uint256 startTime = block.timestamp;
        
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, startTime);

        // Move to 2 years (50% vested)
        vm.warp(startTime + 730 days);
        
        uint256 expectedClaimable = amount / 2;
        
        vm.prank(beneficiary1);
        vesting.claim();

        // Check MSC balance
        assertApproxEqAbs(msc.balanceOf(beneficiary1), expectedClaimable, 1e18);

        // Check vMSC balance (should be burned)
        // Initial vMSC = amount
        // Burned = expectedClaimable
        // Remaining = amount - expectedClaimable
        uint256 remainingVMSC = vmsc.balanceOf(beneficiary1);
        assertApproxEqAbs(remainingVMSC, amount - expectedClaimable, 1e18);
        
        // Check schedule claimed amount
        (,, uint256 claimed,,) = vesting.schedules(beneficiary1);
        assertApproxEqAbs(claimed, expectedClaimable, 1e18);
    }

    function test_FullVesting() public {
        uint256 amount = 100 * 10**18;
        uint256 startTime = block.timestamp;
        
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, startTime);

        // Move to 5 years (past 4 year duration)
        vm.warp(startTime + 2000 days);
        
        uint256 claimable = vesting.getClaimableAmount(beneficiary1);
        assertEq(claimable, amount);
        
        vm.prank(beneficiary1);
        vesting.claim();
        
        assertEq(msc.balanceOf(beneficiary1), amount);
        assertEq(vmsc.balanceOf(beneficiary1), 0);
    }

    function test_Revoke() public {
        uint256 amount = 1_000_000 * 10**18;
        uint256 startTime = block.timestamp;
        
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, startTime);

        // Move to 2 years (50% vested = 500,000)
        vm.warp(startTime + 730 days);
        
        // Revoke
        vesting.revoke(beneficiary1);

        // Check that user got their vested amount automatically (per implementation)
        uint256 expectedVested = amount / 2;
        assertApproxEqAbs(msc.balanceOf(beneficiary1), expectedVested, 1e18);
        
        // Check vMSC burned completely?
        // Logic: 
        // 1. claim vested -> burns vested vMSC
        // 2. revoke unvested -> burns unvested vMSC
        // Total vMSC should be 0
        assertEq(vmsc.balanceOf(beneficiary1), 0);

        // Check schedule updated
        (,, uint256 claimed,, bool revoked) = vesting.schedules(beneficiary1);
        assertTrue(revoked);
        assertApproxEqAbs(claimed, expectedVested, 1e18);
        
        // Ensure no more vesting happens
        vm.warp(startTime + 1460 days);
        uint256 newClaimable = vesting.getClaimableAmount(beneficiary1);
        assertEq(newClaimable, 0); // Should claim nothing more
    }

    function test_GetAllCategories() public {
        bytes32 INVESTOR_CATEGORY = keccak256("INVESTOR");
        vesting.createVestingCategory(
            INVESTOR_CATEGORY,
            "Investor",
            25_000_000 * 10**18,
            180 days,
            730 days
        );

        MSCVesting.Category[] memory all = vesting.getAllCategories();
        assertEq(all.length, 2);
        
        assertEq(all[0].name, "Team");
        assertEq(all[1].name, "Investor");
        assertEq(all[0].allocationCap, 75_000_000 * 10**18);
        assertEq(all[1].allocationCap, 25_000_000 * 10**18);
        
        bytes32[] memory ids = vesting.getCategoryIds();
        assertEq(ids.length, 2);
        assertEq(ids[0], TEAM_CATEGORY);
        assertEq(ids[1], INVESTOR_CATEGORY);
    }

    function test_UpdateCategory() public {
        uint256 newCap = 80_000_000 * 10**18;
        uint256 newCliff = 180 days;
        uint256 newDuration = 730 days;
        string memory newName = "New Team Name";

        vesting.updateVestingCategory(TEAM_CATEGORY, newName, newCap, newCliff, newDuration);

        (string memory name, uint256 cap,, uint256 cliff, uint256 duration,) = vesting.categories(TEAM_CATEGORY);
        assertEq(name, newName);
        assertEq(cap, newCap);
        assertEq(cliff, newCliff);
        assertEq(duration, newDuration);
    }

    function test_DeleteCategory() public {
        bytes32 TEMP_CATEGORY = keccak256("TEMP");
        vesting.createVestingCategory(TEMP_CATEGORY, "Temp", 1000, 0, 100);
        
        assertTrue(vesting.getCategoryIds().length == 2); // TEAM + TEMP
        
        vesting.deleteVestingCategory(TEMP_CATEGORY);
        
        assertEq(vesting.getCategoryIds().length, 1);
        assertEq(vesting.getCategoryIds()[0], TEAM_CATEGORY);
        
        (,,,,, bool exists) = vesting.categories(TEMP_CATEGORY);
        assertFalse(exists);
    }

    function test_DeleteCategoryWithAllocationsFails() public {
        uint256 amount = 1_000_000 * 10**18;
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, block.timestamp);
        
        vm.expectRevert("Allocations exist");
        vesting.deleteVestingCategory(TEAM_CATEGORY);
    }

    function test_Deposit() public {
        uint256 depositAmount = 50_000_000 * 10**18;
        // Owner already holds remaining supply from constructor mint
        msc.approve(address(vesting), depositAmount);
        
        uint256 initialBalance = msc.balanceOf(address(vesting));
        vesting.deposit(depositAmount);
        
        assertEq(msc.balanceOf(address(vesting)), initialBalance + depositAmount);
    }

    function test_CannotShortenVestingDurationAfterAllocations() public {
        uint256 amount = 1_000_000 * 10**18;
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, block.timestamp);

        vm.expectRevert("Cannot shorten vesting duration");
        vesting.updateVestingCategory(TEAM_CATEGORY, "Team", 75_000_000 * 10**18, 365 days, 1000 days);
    }

    function test_CannotExtendCliffAfterAllocations() public {
        uint256 amount = 1_000_000 * 10**18;
        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, block.timestamp);

        vm.expectRevert("Cannot extend cliff duration");
        vesting.updateVestingCategory(TEAM_CATEGORY, "Team", 75_000_000 * 10**18, 400 days, 1460 days);
    }

    function test_VestedNeverExceedsTotalAllocated() public {
        uint256 amount = 1_000_000 * 10**18;
        uint256 startTime = block.timestamp;

        vesting.createVestingSchedule(beneficiary1, TEAM_CATEGORY, amount, startTime);

        vm.warp(startTime + 730 days);

        uint256 claimable = vesting.getClaimableAmount(beneficiary1);
        assertLe(claimable, amount);
    }
}
