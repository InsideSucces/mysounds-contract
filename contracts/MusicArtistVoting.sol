// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MusicArtistVoting
 * @dev A voting contract for music artists where users vote by locking ERC-20 tokens.
 * 1 Token = 1 Vote Weight.
 * Supports multiple voting cycles.
 * Tokens are locked in the contract and can be withdrawn by the admin after voting ends.
 */
contract MusicArtistVoting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---

    /// @notice The ERC-20 token used for voting
    IERC20 public immutable voteToken;

    /// @notice Current voting cycle ID
    uint256 public votingCycle;

    /// @notice Voting start timestamp for the current cycle
    uint256 public votingStart;

    /// @notice Voting end timestamp for the current cycle
    uint256 public votingEnd;

    /// @notice Struct representing a music artist
    struct Artist {
        uint256 id;
        string name;
        bool exists;
        uint256 totalVotes;
    }

    /// @notice Mapping from Cycle ID -> Artist ID -> Artist details
    mapping(uint256 => mapping(uint256 => Artist)) public artists;

    /// @notice Mapping from Cycle ID -> List of registered artist IDs
    mapping(uint256 => uint256[]) public artistIds;

    /// @notice Mapping from Cycle ID -> User Address -> Artist ID -> Vote Weight
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public userVotes;

    /// @notice Mapping from Cycle ID -> User Address -> Total tokens locked
    mapping(uint256 => mapping(address => uint256)) public totalUserLocked;

    /// @notice Flag to prevent double withdrawal by admin for the current cycle
    /// @dev Cycle ID -> Withdrawn status
    mapping(uint256 => bool) public tokensWithdrawn;

    // --- Events ---

    /// @notice Emitted when a new artist is registered
    event ArtistAdded(uint256 indexed cycleId, uint256 indexed artistId, string name);

    /// @notice Emitted when a vote is cast
    event VoteCast(uint256 indexed cycleId, address indexed voter, uint256 indexed artistId, uint256 weight);

    /// @notice Emitted when the voting window is set
    event VotingWindowSet(uint256 indexed cycleId, uint256 startTime, uint256 endTime);

    /// @notice Emitted when tokens are withdrawn by admin
    event TokensWithdrawn(uint256 indexed cycleId, address indexed admin, uint256 amount);

    /// @notice Emitted when a new voting cycle is started
    event NewVotingCycleStarted(uint256 indexed newCycleId);

    // --- Modifiers ---

    /// @dev Checks if voting is currently active based on timestamps
    modifier onlyDuringVoting() {
        require(block.timestamp >= votingStart && block.timestamp <= votingEnd, "Voting is not active");
        _;
    }

    /// @dev Checks if voting has ended
    modifier onlyAfterVoting() {
        require(block.timestamp > votingEnd, "Voting is still active");
        _;
    }

    // --- Constructor ---

    /**
     * @param _voteToken Address of the ERC-20 token used for voting
     */
    constructor(address _voteToken) Ownable(msg.sender) {
        require(_voteToken != address(0), "Invalid token address");
        voteToken = IERC20(_voteToken);
        votingCycle = 1; // Start with cycle 1
    }

    // --- Admin Functions ---

    /**
     * @notice Register a new artist for the current cycle.
     * @param _artistId Unique ID for the artist
     * @param _name Name of the artist
     */
    function registerArtist(uint256 _artistId, string memory _name) external onlyOwner {
        require(!artists[votingCycle][_artistId].exists, "Artist ID already exists in this cycle");
        require(bytes(_name).length > 0, "Artist name cannot be empty");

        artists[votingCycle][_artistId] = Artist({
            id: _artistId,
            name: _name,
            exists: true,
            totalVotes: 0
        });

        artistIds[votingCycle].push(_artistId);

        emit ArtistAdded(votingCycle, _artistId, _name);
    }

    /**
     * @notice Set the start and end time for the current voting cycle.
     * @param _startTime Timestamp when voting starts
     * @param _endTime Timestamp when voting ends
     */
    function setVotingWindow(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(_endTime > _startTime, "End time must be after start time");
        require(_endTime > block.timestamp, "End time must be in future");

        votingStart = _startTime;
        votingEnd = _endTime;

        emit VotingWindowSet(votingCycle, _startTime, _endTime);
    }

    /**
     * @notice Withdraw all locked tokens to the admin address after voting ends.
     */
    function withdrawTokens() external onlyOwner onlyAfterVoting nonReentrant {
        require(!tokensWithdrawn[votingCycle], "Tokens already withdrawn for this cycle");
        
        uint256 contractBalance = voteToken.balanceOf(address(this));
        require(contractBalance > 0, "No tokens to withdraw");

        tokensWithdrawn[votingCycle] = true;
        voteToken.safeTransfer(msg.sender, contractBalance);

        emit TokensWithdrawn(votingCycle, msg.sender, contractBalance);
    }

    /**
     * @notice Start a new voting cycle, effectively clearing all artists and votes.
     * @dev Should be called after the previous cycle is complete and tokens withdrawn (optional but recommended).
     */
    function startNewVotingCycle() external onlyOwner {
        // Optional: Require previous voting to be ended? 
        // We allow force restart, but best practice is to ensure closure. 
        // For flexibility, we just increment.
        
        votingCycle++;
        
        // Reset window to avoid accidental open voting
        votingStart = 0;
        votingEnd = 0;

        emit NewVotingCycleStarted(votingCycle);
    }

    // --- User Functions ---

    /**
     * @notice Vote for an artist by locking tokens.
     * @param _artistId The ID of the artist to vote for
     * @param _amount The amount of tokens to vote (1 Token = 1 Vote)
     */
    function vote(uint256 _artistId, uint256 _amount) external onlyDuringVoting nonReentrant {
        require(artists[votingCycle][_artistId].exists, "Artist does not exist");
        require(_amount > 0, "Vote amount must be greater than 0");

        // Transfer tokens from user to contract
        voteToken.safeTransferFrom(msg.sender, address(this), _amount);

        // Update stats
        artists[votingCycle][_artistId].totalVotes += _amount;
        userVotes[votingCycle][msg.sender][_artistId] += _amount;
        totalUserLocked[votingCycle][msg.sender] += _amount;

        emit VoteCast(votingCycle, msg.sender, _artistId, _amount);
    }

    // --- View / Analytics Functions ---

    /**
     * @notice Get details of a specific artist in the current cycle.
     */
    function getArtist(uint256 _artistId) external view returns (uint256 id, string memory name, bool exists, uint256 totalVotes) {
        Artist memory artist = artists[votingCycle][_artistId];
        return (artist.id, artist.name, artist.exists, artist.totalVotes);
    }

    /**
     * @notice Get the leading artist(s) for the current cycle.
     * @dev Returns an array of leaders in case of a tie.
     */
    function getLeadingArtist() external view returns (Artist[] memory leaders) {
        uint256[] memory currentIds = artistIds[votingCycle];
        uint256 highestVotes = 0;
        uint256 leaderCount = 0;

        // First pass: find highest vote count
        for (uint256 i = 0; i < currentIds.length; i++) {
            uint256 votes = artists[votingCycle][currentIds[i]].totalVotes;
            if (votes > highestVotes) {
                highestVotes = votes;
                leaderCount = 1;
            } else if (votes == highestVotes && votes > 0) {
                leaderCount++;
            }
        }

        // If no votes or no artists, return empty
        if (highestVotes == 0) {
            return new Artist[](0);
        }

        // Second pass: fill leaders array
        leaders = new Artist[](leaderCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < currentIds.length; i++) {
            Artist memory art = artists[votingCycle][currentIds[i]];
            if (art.totalVotes == highestVotes) {
                leaders[currentIndex] = art;
                currentIndex++;
            }
        }
        return leaders;
    }

    /**
     * @notice Get all artists registered in the current cycle.
     */
    function getAllArtists() external view returns (Artist[] memory) {
        uint256[] memory ids = artistIds[votingCycle];
        Artist[] memory allArtists = new Artist[](ids.length);
        
        for (uint256 i = 0; i < ids.length; i++) {
            allArtists[i] = artists[votingCycle][ids[i]];
        }
        return allArtists;
    }

    /**
     * @notice Get the leaderboard for a specific cycle (or current if 0 passed).
     * @param _cycleId The cycle ID to get leaderboard for (0 for current).
     */
    function getLeaderboard(uint256 _cycleId) external view returns (Artist[] memory) {
        uint256 targetCycle = _cycleId == 0 ? votingCycle : _cycleId;
        uint256[] memory ids = artistIds[targetCycle];
        uint256 length = ids.length;
        
        Artist[] memory leaderboard = new Artist[](length);
        
        // Populate array
        for (uint256 i = 0; i < length; i++) {
            leaderboard[i] = artists[targetCycle][ids[i]];
        }

        // Sort by totalVotes descending (Bubble Sort)
        // Note: For large numbers of artists, off-chain indexing is preferred. 
        // But for < 100 artists, this is acceptable for view functions.
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = 0; j < length - 1 - i; j++) {
                if (leaderboard[j].totalVotes < leaderboard[j + 1].totalVotes) {
                    Artist memory temp = leaderboard[j];
                    leaderboard[j] = leaderboard[j + 1];
                    leaderboard[j + 1] = temp;
                }
            }
        }
        
        return leaderboard;
    }

    /**
     * @notice Check if the voting period is currently active.
     */
    function isVotingActive() external view returns (bool) {
        return block.timestamp >= votingStart && block.timestamp <= votingEnd;
    }
}
