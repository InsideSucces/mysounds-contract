// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRewardManager} from "./interfaces/IRewardManager.sol";
import {RewardScaling} from "./libraries/RewardScaling.sol";
import {RewardStorage} from "./libraries/RewardStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IRewardError} from "./errors/RewardManagerError.sol";

contract RewardManager is IRewardManager, AccessControl, Ownable, ReentrancyGuard, IRewardError {
    using RewardScaling for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");

    constructor(address token_, uint256 totalSupply_, uint256 baseRate_, address defaultAdmin_, address backendAdmin_) Ownable(msg.sender) {
        if (token_ == address(0)) revert NullAddress(token_);
        if (defaultAdmin_ == address(0)) revert NullAddress(defaultAdmin_);
        if (backendAdmin_ == address(0)) revert NullAddress(backendAdmin_);
        if (baseRate_ == 0) revert InvalidMultiplier(baseRate_);
        RewardStorage.Layout storage s = RewardStorage.layout();
        s.token = token_;
        s.totalRewardSupply = totalSupply_;
        s.baseRate = baseRate_;
        s.manualMultiplier = RewardScaling.SCALE; // 1e18
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin_);
        _grantRole(BACKEND_ROLE, backendAdmin_);

        // default weights (scaled integer weights)
        s.actionWeights[uint256(Action.SIGNUP)] = 100; // baseline weight
        s.actionWeights[uint256(Action.LIKE_MILESTONE)] = 20;
        s.actionWeights[uint256(Action.PURCHASE)] = 200;
        s.actionWeights[uint256(Action.DAILY_STREAK)] = 30;
        s.actionWeights[uint256(Action.UPLOAD)] = 150;
        s.actionWeights[uint256(Action.COMMENT)] = 10;
        s.actionWeights[uint256(Action.REFERRAL)] = 500;
        s.actionWeights[uint256(Action.STREAMING)] = 5;
        s.actionWeights[uint256(Action.EVENT_ATTENDANCE)] = 50;
        s.actionWeights[uint256(Action.ARTIST_MILESTONE)] = 400;
    }

    modifier onlyBackend() {
        _onlyBackend();

        _;
    }

    // Administrative functions
    function setBaseRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRate == 0) revert InvalidMultiplier(newRate);
        RewardStorage.Layout storage s = RewardStorage.layout();
        emit RewardRateUpdated(s.baseRate, newRate);
        s.baseRate = newRate;
    }

    function setManualMultiplier(uint256 multiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        RewardStorage.Layout storage s = RewardStorage.layout();
        if (multiplier == 0 || multiplier > RewardScaling.SCALE) revert InvalidMultiplier(multiplier);
        uint256 old = s.manualMultiplier;
        s.manualMultiplier = multiplier;
        emit ManualMultiplierUpdated(old, multiplier);
    }

    function setActionWeight(Action action, uint256 weight) external onlyRole(DEFAULT_ADMIN_ROLE) {
        RewardStorage.Layout storage s = RewardStorage.layout();
        uint256 old = s.actionWeights[uint256(action)];
        s.actionWeights[uint256(action)] = weight;
        emit ActionWeightUpdated(action, old, weight);
    }

    // Fund the contract with MSC tokens. Admin calls this to provision rewards.
    function fundPool(uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        RewardStorage.Layout storage s = RewardStorage.layout();
        IERC20(s.token).safeTransferFrom(msg.sender, address(this), amount);
    }

    // Viewers
    function remainingRewards() external view override returns (uint256) {
        RewardStorage.Layout storage s = RewardStorage.layout();
        uint256 balance = IERC20(s.token).balanceOf(address(this));
        // remaining is min of balance and allocation left
        uint256 allocatedLeft = 0;
        if (s.totalRewardSupply > s.totalDistributed) allocatedLeft = s.totalRewardSupply - s.totalDistributed;
        return balance < allocatedLeft ? balance : allocatedLeft;
    }

    function getEffectiveReward(Action action) public view override returns (uint256) {
        RewardStorage.Layout storage s = RewardStorage.layout();
        uint256 weight = s.actionWeights[uint256(action)];
        if (weight == 0) return 0;

        // base amount: baseRate * weight
        uint256 base = s.baseRate * weight;

        // scale by remaining allocation
        uint256 remaining = 0;
        if (s.totalRewardSupply > s.totalDistributed) remaining = s.totalRewardSupply - s.totalDistributed;
        uint256 byAlloc = RewardScaling.byRemainingAllocation(base, remaining, s.totalRewardSupply);

        // user penalty
        uint256 up = RewardScaling.userPenalty(s.totalUsers);
        uint256 adjusted = (byAlloc * up) / RewardScaling.SCALE;

        // manual multiplier
        uint256 finalAmount = RewardScaling.applyManualMultiplier(adjusted, s.manualMultiplier);
        return finalAmount;
    }

    // Primary reward entrypoint triggered by backend (off-chain verification)
    function rewardAction(address user, Action action, bytes calldata metadata) external override onlyBackend nonReentrant {
        RewardStorage.Layout storage s = RewardStorage.layout();
        if (user == address(0)) revert NullAddress(user);

        if (action == Action.SIGNUP && s.hasSignedUp[user]) return;

        uint256 last = s.lastActionTimestamp[user][uint256(action)];
        if (block.timestamp < last + _minInterval(action)) {
            revert TooSoonForAction(user, uint256(action), last, block.timestamp, _minInterval(action));
        }

        // Compute payout before mutating throttle state so empty-pool calls do not burn the interval.
        uint256 amount = getEffectiveReward(action);

        if (action == Action.SIGNUP) {
            s.hasSignedUp[user] = true;
            s.totalUsers += 1;
            s.lastActionTimestamp[user][uint256(action)] = block.timestamp;
            s.lastActionMetadata[user][uint256(action)] = metadata;
            // Signup still records even if amount is 0 (allocation exhausted).
        } else {
            if (amount == 0) return;
            s.lastActionTimestamp[user][uint256(action)] = block.timestamp;
            s.lastActionMetadata[user][uint256(action)] = metadata;
        }

        if (amount == 0) return;

        // cap by remaining allocation
        uint256 remainingAlloc = 0;
        if (s.totalRewardSupply > s.totalDistributed) remainingAlloc = s.totalRewardSupply - s.totalDistributed;
        if (amount > remainingAlloc) amount = remainingAlloc;

        // cap by contract token balance
        uint256 bal = IERC20(s.token).balanceOf(address(this));
        if (amount > bal) amount = bal;
        if (amount == 0) return;

        // distribute
        s.totalDistributed += amount;
        s.lifetimeRewards[user] += amount;

        IERC20(s.token).safeTransfer(user, amount);

        emit RewardPaid(user, amount, action, metadata);
    }

    function _minInterval(Action action) internal pure returns (uint256) {
        if (action == Action.LIKE_MILESTONE) return 1 minutes;
        if (action == Action.COMMENT) return 30 seconds;
        if (action == Action.STREAMING) return 10 seconds;
        return 0; // default no throttling (backend should gate)
    }

    // helper for frontend / offchain tooling
    function getUserLifetimeRewards(address user) external view returns (uint256) {
        return RewardStorage.layout().lifetimeRewards[user];
    }

    // emergency withdrawal by admin (non-rewarded tokens only if over-allocated etc.)
    function emergencyWithdraw(address to, uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert NullAddress(to);
        RewardStorage.Layout storage s = RewardStorage.layout();
        uint256 bal = IERC20(s.token).balanceOf(address(this));
        uint256 allocLeft = s.totalRewardSupply > s.totalDistributed
            ? s.totalRewardSupply - s.totalDistributed
            : 0;
        uint256 reserved = bal < allocLeft ? bal : allocLeft;
        uint256 withdrawable = bal - reserved;
        require(amount <= withdrawable, "insufficient balance");
        IERC20(s.token).safeTransfer(to, amount);
    }

    /// @notice Recover ETH accidentally sent to this contract.
    function withdrawETH(address payable to) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert NullAddress(to);
        uint256 bal = address(this).balance;
        require(bal > 0, "no eth");
        (bool ok,) = to.call{value: bal}("");
        require(ok, "eth transfer failed");
    }

    function _onlyBackend() internal view {
        if (!hasRole(BACKEND_ROLE, msg.sender)) revert InsufficientPermission(msg.sender);
    }

    receive() external payable {}
}

