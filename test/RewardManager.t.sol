// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {RewardManager} from "../contracts/RewardManager.sol";
import {IRewardManager} from "../contracts/interfaces/IRewardManager.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {RewardScaling} from "../contracts/libraries/RewardScaling.sol";

contract RewardManagerTest is Test {
    RewardManager public rewardManager;
    MockERC20 public rewardToken;

    address public admin = address(0x1);
    address public backend = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant BASE_RATE = 1e18; // 1 token base
    uint256 public constant INITIAL_FUNDING = 100_000 * 1e18;

    event RewardPaid(address indexed user, uint256 amount, IRewardManager.Action action, bytes metadata);
    event RewardRateUpdated(uint256 indexed oldRate, uint256 indexed newRate);
    event ManualMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event ActionWeightUpdated(IRewardManager.Action action, uint256 oldWeight, uint256 newWeight);

    function setUp() public {
        vm.warp(1000000);
        vm.startPrank(admin);

        // Deploy mock token
        rewardToken = new MockERC20("Reward Token", "RWD", 18);
        rewardToken.mint(admin, TOTAL_SUPPLY);

        // Deploy RewardManager
        rewardManager = new RewardManager(address(rewardToken), TOTAL_SUPPLY, BASE_RATE,admin,admin);

        // Grant backend role
        rewardManager.grantRole(rewardManager.BACKEND_ROLE(), backend);

        // Fund the pool
        rewardToken.approve(address(rewardManager), INITIAL_FUNDING);
        rewardManager.fundPool(INITIAL_FUNDING);

        vm.stopPrank();
    }

    function test_ConstructorSetsValuesCorrectly() public view {
        // Check roles
        assertTrue(rewardManager.hasRole(rewardManager.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(rewardManager.hasRole(rewardManager.BACKEND_ROLE(), admin)); // Admin gets backend role in constructor

        // Check initial state via viewers or storage if public (storage is internal library, so check behavior)
        assertEq(rewardManager.remainingRewards(), INITIAL_FUNDING); // Since totalDistributed is 0, remaining is min(balance, supply). Balance is INITIAL_FUNDING.
    }

    function test_SetBaseRate() public {
        vm.prank(admin);
        uint256 newRate = 2e18;

        vm.expectEmit(true, true, true, true);
        emit RewardRateUpdated(BASE_RATE, newRate);

        rewardManager.setBaseRate(newRate);
    }

    function test_SetBaseRate_RevertIfNotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(); // AccessControl error
        rewardManager.setBaseRate(2e18);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_RewardAction_Signup() public {
        // Signup action
        vm.startPrank(backend);

        uint256 expectedReward = rewardManager.getEffectiveReward(IRewardManager.Action.SIGNUP);

        vm.recordLogs();
        rewardManager.rewardAction(user1, IRewardManager.Action.SIGNUP, "");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // We expect at least 2 events: Transfer and RewardPaid
        assertTrue(entries.length >= 2, "Should emit at least 2 events");

        // Find RewardPaid event
        bool found = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length == 2) {
                if (entries[i].topics[1] == bytes32(uint256(uint160(user1)))) {
                    (uint256 amount, uint8 action, bytes memory metadata) = abi.decode(entries[i].data, (uint256, uint8, bytes));
                    if (amount == expectedReward && action == uint8(IRewardManager.Action.SIGNUP) && metadata.length == 0) {
                        found = true;
                        break;
                    }
                }
            }
        }
        assertTrue(found, "RewardPaid event not found or incorrect");

        assertEq(rewardToken.balanceOf(user1), expectedReward);
        assertEq(rewardManager.getUserLifetimeRewards(user1), expectedReward);
        vm.stopPrank();
    }

    function test_SetManualMultiplier() public {
        vm.prank(admin);
        uint256 newMult = 0.5e18; // 0.5x (valid <= SCALE)

        vm.recordLogs();
        rewardManager.setManualMultiplier(newMult);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertTrue(entries.length > 0);

        (uint256 oldVal, uint256 newVal) = abi.decode(entries[0].data, (uint256, uint256));
        assertEq(oldVal, 1e18);
        assertEq(newVal, newMult);
    }

    function test_SetActionWeight() public {
        vm.prank(admin);
        uint256 newWeight = 500;
        IRewardManager.Action action = IRewardManager.Action.SIGNUP;

        // Default SIGNUP weight is 100
        vm.expectEmit(true, true, true, true);
        emit ActionWeightUpdated(action, 100, newWeight);

        rewardManager.setActionWeight(action, newWeight);
    }

    function test_RewardAction_OnlyBackend() public {
        vm.prank(user1);
        vm.expectRevert(); // InsufficientPermission
        rewardManager.rewardAction(user1, IRewardManager.Action.SIGNUP, "");
    }

    function test_RewardAction_DuplicateSignup() public {
        vm.startPrank(backend);
        rewardManager.rewardAction(user1, IRewardManager.Action.SIGNUP, "");

        uint256 balanceAfterFirst = rewardToken.balanceOf(user1);

        // Second signup should do nothing (return early)
        rewardManager.rewardAction(user1, IRewardManager.Action.SIGNUP, "");

        assertEq(rewardToken.balanceOf(user1), balanceAfterFirst);
        vm.stopPrank();
    }

    function test_RewardAction_Throttling() public {
        vm.startPrank(backend);

        // COMMENT has 30s interval
        rewardManager.rewardAction(user1, IRewardManager.Action.COMMENT, "");

        // Immediate second attempt should fail
        vm.expectRevert(); // TooSoonForAction
        rewardManager.rewardAction(user1, IRewardManager.Action.COMMENT, "");

        // Wait 31 seconds
        vm.warp(block.timestamp + 31);

        // Should succeed now
        rewardManager.rewardAction(user1, IRewardManager.Action.COMMENT, "");

        vm.stopPrank();
    }

    function test_EmergencyWithdraw() public {
        uint256 contractBalance = rewardToken.balanceOf(address(rewardManager));

        vm.prank(admin);
        rewardManager.emergencyWithdraw(admin, contractBalance);

        assertEq(rewardToken.balanceOf(address(rewardManager)), 0);
        assertEq(rewardToken.balanceOf(admin), TOTAL_SUPPLY); // Initial mint was TOTAL_SUPPLY, funded INITIAL_FUNDING, then withdrew back.
    }

    function test_RemainingRewards() public {
        // Initial state
        assertEq(rewardManager.remainingRewards(), INITIAL_FUNDING);

        // Distribute some rewards
        vm.prank(backend);
        rewardManager.rewardAction(user1, IRewardManager.Action.SIGNUP, "");

        uint256 distributed = rewardToken.balanceOf(user1);
        assertEq(rewardManager.remainingRewards(), INITIAL_FUNDING - distributed);
    }

    function test_RewardAction_StoresMetadata() public {
        vm.startPrank(backend);
        bytes memory meta = hex"123456";
        
        vm.recordLogs();
        rewardManager.rewardAction(user1, IRewardManager.Action.UPLOAD, meta);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Check event
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length == 2 && entries[i].topics[1] == bytes32(uint256(uint160(user1)))) {
                (uint256 amount, uint8 action, bytes memory m) = abi.decode(entries[i].data, (uint256, uint8, bytes));
                if (action == uint8(IRewardManager.Action.UPLOAD) && keccak256(m) == keccak256(meta)) {
                    found = true;
                    break;
                }
            }
        }
        assertTrue(found, "Metadata not emitted correctly");
        vm.stopPrank();
    }
}
