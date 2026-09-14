// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {vMSC} from "./vMSC.sol";

/**
 * @title MSCVesting
 * @notice Manages vesting schedules for MSC tokens with category-based rules.
 */
contract MSCVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---

    IERC20 public immutable mscToken;
    vMSC public immutable vmscToken;

    struct Category {
        string name;
        uint256 allocationCap;
        uint256 totalAllocated;
        uint256 cliffDuration;
        uint256 vestingDuration;
        bool exists;
    }

    struct VestingSchedule {
        bytes32 categoryId;
        uint256 totalAllocated;
        uint256 claimed;
        uint256 startTime;
        bool revoked;
    }

    mapping(bytes32 => Category) public categories;
    bytes32[] public categoryKeys;
    mapping(bytes32 => uint256) private categoryIndex; // 1-indexed for O(1) existence and removal

    mapping(address => VestingSchedule) public schedules;
    
    // Explicitly track the total MSC backing the vesting schedules
    uint256 public totalOutstandingMSC;

    // --- Events ---

    event CategoryCreated(bytes32 indexed categoryId, string name, uint256 cap, uint256 cliff, uint256 duration);
    event CategoryUpdated(bytes32 indexed categoryId, string name, uint256 cap, uint256 cliff, uint256 duration);
    event CategoryDeleted(bytes32 indexed categoryId);
    event ScheduleCreated(address indexed beneficiary, bytes32 indexed categoryId, uint256 amount);
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event Revoked(address indexed beneficiary, uint256 refundAmount);
    event TokensDeposited(address indexed admin, uint256 amount);
    event ExcessWithdrawn(address indexed to, uint256 amount);

    // --- Constructor ---

    constructor(address _mscToken, address _vmscToken) Ownable(msg.sender) {
        require(_mscToken != address(0), "Invalid MSC address");
        require(_vmscToken != address(0), "Invalid vMSC address");
        mscToken = IERC20(_mscToken);
        vmscToken = vMSC(_vmscToken);
    }

    // --- Admin Functions ---

    /**
     * @notice Creates a new vesting category.
     * @param categoryId Unique identifier for the category (e.g., keccak256("TEAM")).
     * @param cap Maximum total allocation for this category.
     * @param cliff Duration in seconds before vesting starts.
     * @param duration Total vesting duration in seconds (includes cliff).
     */
    function createVestingCategory(
        bytes32 categoryId,
        string calldata name,
        uint256 cap,
        uint256 cliff,
        uint256 duration
    ) external onlyOwner {
        require(!categories[categoryId].exists, "Category already exists");
        require(duration > cliff, "Duration must be greater than cliff");

        categories[categoryId] = Category({
            name: name,
            allocationCap: cap,
            totalAllocated: 0,
            cliffDuration: cliff,
            vestingDuration: duration,
            exists: true
        });

        categoryKeys.push(categoryId);
        categoryIndex[categoryId] = categoryKeys.length;

        emit CategoryCreated(categoryId, name, cap, cliff, duration);
    }

    /**
     * @notice Updates an existing vesting category.
     */
    function updateVestingCategory(
        bytes32 categoryId,
        string calldata name,
        uint256 cap,
        uint256 cliff,
        uint256 duration
    ) external onlyOwner {
        Category storage category = categories[categoryId];
        require(category.exists, "Category does not exist");
        require(duration > cliff, "Duration must be greater than cliff");
        require(cap >= category.totalAllocated, "Cap below allocated");

        if (category.totalAllocated > 0) {
            require(duration >= category.vestingDuration, "Cannot shorten vesting duration");
            require(cliff <= category.cliffDuration, "Cannot extend cliff duration");
        }

        category.name = name;
        category.allocationCap = cap;
        category.cliffDuration = cliff;
        category.vestingDuration = duration;

        emit CategoryUpdated(categoryId, name, cap, cliff, duration);
    }

    /**
     * @notice Allows admin to deposit MSC tokens into the contract.
     */
    function deposit(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        mscToken.safeTransferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw MSC not backing outstanding vesting schedules (e.g. after revokes).
     */
    function withdrawExcess(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        uint256 balance = mscToken.balanceOf(address(this));
        require(balance >= totalOutstandingMSC + amount, "Insufficient excess");
        mscToken.safeTransfer(to, amount);
        emit ExcessWithdrawn(to, amount);
    }

    /**
     * @notice Deletes a vesting category. Only possible if no tokens have been allocated.
     */
    function deleteVestingCategory(bytes32 categoryId) external onlyOwner {
        require(categories[categoryId].exists, "Category does not exist");
        require(categories[categoryId].totalAllocated == 0, "Allocations exist");

        // Remove from categoryKeys using swap and pop
        uint256 index = categoryIndex[categoryId];
        bytes32 lastKey = categoryKeys[categoryKeys.length - 1];

        if (index != categoryKeys.length) {
            categoryKeys[index - 1] = lastKey;
            categoryIndex[lastKey] = index;
        }

        categoryKeys.pop();
        delete categoryIndex[categoryId];
        delete categories[categoryId];

        emit CategoryDeleted(categoryId);
    }

    /**
     * @notice Creates a vesting schedule for a beneficiary.
     * @param beneficiary Address to receive the tokens.
     * @param categoryId Category to assign the beneficiary to.
     * @param amount Amount of MSC tokens to allocate.
     * @param startTime Timestamp when the vesting clock starts (usually now or TGE).
     */
    function createVestingSchedule(
        address beneficiary,
        bytes32 categoryId,
        uint256 amount,
        uint256 startTime
    ) external onlyOwner nonReentrant {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(categories[categoryId].exists, "Category does not exist");
        require(schedules[beneficiary].totalAllocated == 0, "Schedule already exists"); // Simple 1-schedule limit per user for now

        Category storage category = categories[categoryId];
        require(category.totalAllocated + amount <= category.allocationCap, "Category cap exceeded");

        // Ensure contract has enough MSC to back the allocation
        // This check assumes the admin has already funded the contract.
        require(mscToken.balanceOf(address(this)) >= totalLockedMSC() + amount, "Insufficient MSC in contract");

        category.totalAllocated += amount;
        totalOutstandingMSC += amount;

        schedules[beneficiary] = VestingSchedule({
            categoryId: categoryId,
            totalAllocated: amount,
            claimed: 0,
            startTime: startTime,
            revoked: false
        });

        // Mint vMSC 1:1 to beneficiary to represent locked tokens
        vmscToken.mint(beneficiary, amount);

        emit ScheduleCreated(beneficiary, categoryId, amount);
    }

    /**
     * @notice Revokes a user's vesting schedule.
     * @dev Calculates vested amount up to now, lets them keep it (or requires them to claim it first?),
     * and refunds the rest to the owner/contract or just marks it as revoked.
     * The requirement said "Revoke unvested tokens".
     */
    function revoke(address beneficiary) external onlyOwner nonReentrant {
        VestingSchedule storage schedule = schedules[beneficiary];
        require(schedule.totalAllocated > 0, "No schedule found");
        require(!schedule.revoked, "Already revoked");

        uint256 totalAllocated = schedule.totalAllocated;
        uint256 claimed = schedule.claimed;
        bytes32 categoryId = schedule.categoryId;

        uint256 vested = _calculateVestedAmount(beneficiary);
        uint256 claimable;
        unchecked {
            claimable = vested - claimed;
        }

        // Effects first
        schedule.revoked = true;
        schedule.totalAllocated = vested;
        schedule.claimed = vested;

        uint256 unvested;
        unchecked {
            unvested = totalAllocated - vested;
        }

        Category storage category = categories[categoryId];
        category.totalAllocated -= unvested;
        totalOutstandingMSC -= unvested;

        if (claimable > 0) {
            totalOutstandingMSC -= claimable;
            mscToken.safeTransfer(beneficiary, claimable);
            vmscToken.burn(beneficiary, claimable);
            emit TokensClaimed(beneficiary, claimable);
        }

        if (unvested > 0) {
            vmscToken.burn(beneficiary, unvested);
        }

        emit Revoked(beneficiary, unvested);
    }

    // --- User Functions ---

    /**
     * @notice Claims all currently unlocked MSC tokens.
     */
    function claim() external nonReentrant {
        VestingSchedule storage schedule = schedules[msg.sender];
        require(schedule.totalAllocated > 0, "No schedule found");
        require(!schedule.revoked, "Schedule revoked");

        uint256 vested = _calculateVestedAmount(msg.sender);
        uint256 claimed = schedule.claimed;
        uint256 claimable;
        unchecked {
            claimable = vested - claimed;
        }

        require(claimable > 0, "Nothing to claim");

        // Effects before interactions
        schedule.claimed = claimed + claimable;
        totalOutstandingMSC -= claimable;

        mscToken.safeTransfer(msg.sender, claimable);
        vmscToken.burn(msg.sender, claimable);

        emit TokensClaimed(msg.sender, claimable);
    }

    // --- View Functions ---

    /**
     * @notice Returns claimable amount for a beneficiary.
     */
    function getClaimableAmount(address beneficiary) external view returns (uint256) {
        VestingSchedule storage schedule = schedules[beneficiary];
        if (schedule.totalAllocated == 0) return 0;
        
        uint256 vested = _calculateVestedAmount(beneficiary);
        if (vested <= schedule.claimed) return 0;
        return vested - schedule.claimed;
    }

    /**
     * @notice Calculates the total vested amount (claimed + unclaimed) based on time.
     */
    function _calculateVestedAmount(address beneficiary) internal view returns (uint256) {
        VestingSchedule storage schedule = schedules[beneficiary];
        if (schedule.totalAllocated == 0) return 0;
        
        // If already revoked, the vested amount is capped at what it was when revoked (handled in revoke logic)
        // actually, if revoked, we modified totalAllocated to equal vested. 
        // So for revoked schedules, totalAllocated IS the vested amount.
        if (schedule.revoked) {
            return schedule.totalAllocated;
        }

        Category storage category = categories[schedule.categoryId];
        uint256 cliffDuration = category.cliffDuration;
        uint256 vestingDuration = category.vestingDuration;
        uint256 startTime = schedule.startTime;
        uint256 totalAllocated = schedule.totalAllocated;

        if (block.timestamp < startTime + cliffDuration) {
            return 0;
        }

        if (block.timestamp >= startTime + vestingDuration) {
            return totalAllocated;
        }

        uint256 timeSinceStart = block.timestamp - startTime;
        uint256 vested = (totalAllocated * timeSinceStart) / vestingDuration;
        return vested > totalAllocated ? totalAllocated : vested;
    }

    function totalLockedMSC() public view returns (uint256) {
        return totalOutstandingMSC;
    }

    /**
     * @notice Returns all available vesting categories.
     */
    function getAllCategories() external view returns (Category[] memory) {
        Category[] memory allCategories = new Category[](categoryKeys.length);
        for (uint256 i = 0; i < categoryKeys.length; i++) {
            allCategories[i] = categories[categoryKeys[i]];
        }
        return allCategories;
    }

    /**
     * @notice Returns all available category IDs.
     */
    function getCategoryIds() external view returns (bytes32[] memory) {
        return categoryKeys;
    }
}
