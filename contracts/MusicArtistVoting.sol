// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title MusicArtistVoting
 * @dev Voting contract where users lock ERC-20 tokens (1 token = 1 vote weight).
 * Supports multiple voting cycles, EIP-712 gasless meta-transactions (voteBySig),
 * and relayer-sponsored virtual MSC votes (voteForUser).
 * After a cycle ends, token sponsors/voters reclaim their locked tokens.
 */
contract MusicArtistVoting is Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    IERC20 public immutable voteToken;

    uint256 public votingCycle;
    uint256 public votingStart;
    uint256 public votingEnd;

    bytes32 public constant VOTE_TYPEHASH =
        keccak256("Vote(address voter,uint256 cycleId,uint256 artistId,uint256 amount,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public nonces;

    struct Artist {
        uint256 id;
        string name;
        bool exists;
        uint256 totalVotes;
    }

    mapping(uint256 => mapping(uint256 => Artist)) public artists;
    mapping(uint256 => uint256[]) public artistIds;
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public userVotes;
    mapping(uint256 => mapping(address => uint256)) public totalUserLocked;
    mapping(uint256 => uint256) private cycleTotalLocked;
    /// @notice Tokens still owed to voters for a cycle (locked - reclaimed).
    mapping(uint256 => uint256) public cycleOutstanding;

    event ArtistAdded(uint256 indexed cycleId, uint256 indexed artistId, string name);
    event VoteCast(uint256 indexed cycleId, address indexed voter, uint256 indexed artistId, uint256 weight);
    event VotingWindowSet(uint256 indexed cycleId, uint256 startTime, uint256 endTime);
    event TokensReclaimed(uint256 indexed cycleId, address indexed voter, uint256 amount);
    event ExcessTokensWithdrawn(uint256 indexed cycleId, address indexed admin, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);
    event NewVotingCycleStarted(uint256 indexed newCycleId);

    modifier onlyDuringVoting() {
        require(
            votingStart != 0 && block.timestamp >= votingStart && block.timestamp <= votingEnd,
            "Voting is not active"
        );
        _;
    }

    constructor(address _voteToken) Ownable(msg.sender) EIP712("MusicArtistVoting", "1") {
        require(_voteToken != address(0), "Invalid token address");
        voteToken = IERC20(_voteToken);
        votingCycle = 1;
    }

    function registerArtist(uint256 _artistId, string memory _name) external onlyOwner {
        require(!artists[votingCycle][_artistId].exists, "Artist ID already exists in this cycle");
        require(bytes(_name).length > 0, "Artist name cannot be empty");
        // Allow registering artists at any point before voting cycle ends.
        require(votingEnd == 0 || block.timestamp <= votingEnd, "Cannot register after cycle has ended");

        artists[votingCycle][_artistId] = Artist({
            id: _artistId,
            name: _name,
            exists: true,
            totalVotes: 0
        });

        artistIds[votingCycle].push(_artistId);
        emit ArtistAdded(votingCycle, _artistId, _name);
    }

    function setVotingWindow(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(_endTime > _startTime, "End time must be after start time");
        require(_endTime > block.timestamp, "End time must be in future");
        // Prevent shortening an active window to force early reclaim / grief voters.
        if (votingStart != 0 && block.timestamp >= votingStart && block.timestamp <= votingEnd) {
            require(_startTime == votingStart, "Cannot change start during voting");
            require(_endTime >= votingEnd, "Cannot shorten active voting window");
        }

        votingStart = _startTime;
        votingEnd = _endTime;

        emit VotingWindowSet(votingCycle, _startTime, _endTime);
    }

    /**
     * @notice Voters reclaim their locked tokens after that cycle's voting ends.
     * @param _cycleId Cycle to reclaim from (0 = current cycle).
     */
    function reclaimTokens(uint256 _cycleId) external nonReentrant {
        uint256 cycle = _cycleId == 0 ? votingCycle : _cycleId;
        require(cycle > 0 && cycle <= votingCycle, "Invalid cycle");

        if (cycle == votingCycle) {
            require(votingEnd != 0, "Voting window not set");
            require(block.timestamp > votingEnd, "Voting is still active");
        }

        uint256 amount = totalUserLocked[cycle][msg.sender];
        require(amount > 0, "Nothing to reclaim");

        totalUserLocked[cycle][msg.sender] = 0;
        cycleOutstanding[cycle] -= amount;

        voteToken.safeTransfer(msg.sender, amount);
        emit TokensReclaimed(cycle, msg.sender, amount);
    }

    /**
     * @notice Withdraw only tokens not owed to voters (e.g. mistaken transfers).
     */
    function withdrawExcessTokens(address to) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 totalOwed = _totalOutstandingAllCycles();
        uint256 balance = voteToken.balanceOf(address(this));
        require(balance > totalOwed, "No excess tokens");
        uint256 excess = balance - totalOwed;
        voteToken.safeTransfer(to, excess);
        emit ExcessTokensWithdrawn(votingCycle, to, excess);
    }

    /**
     * @notice Withdraw tokens from the contract to a specified wallet address.
     * @param to Recipient wallet address.
     * @param amount Amount to withdraw in token base units (0 = withdraw all tokens in contract).
     */
    function withdrawTokens(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 balance = voteToken.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        uint256 toWithdraw = (amount == 0 || amount > balance) ? balance : amount;
        voteToken.safeTransfer(to, toWithdraw);
        emit TokensWithdrawn(to, toWithdraw);
    }

    function startNewVotingCycle() external onlyOwner {
        require(votingEnd != 0, "Voting window not set");
        require(block.timestamp > votingEnd, "Voting is still active");

        votingCycle++;
        votingStart = 0;
        votingEnd = 0;

        emit NewVotingCycleStarted(votingCycle);
    }

    function vote(uint256 _artistId, uint256 _amount) external onlyDuringVoting nonReentrant {
        _castVote(msg.sender, msg.sender, _artistId, _amount);
    }

    /**
     * @notice Cast multiple votes in a single transaction (batch voting).
     */
    function voteBatch(uint256[] calldata _artistIds, uint256[] calldata _amounts) external onlyDuringVoting nonReentrant {
        require(_artistIds.length == _amounts.length, "Array lengths must match");
        require(_artistIds.length > 0, "Empty batch");
        for (uint256 i = 0; i < _artistIds.length; i++) {
            _castVote(msg.sender, msg.sender, _artistIds[i], _amounts[i]);
        }
    }

    /**
     * @notice Cast vote using an EIP-712 signature (gasless / meta-transaction).
     * @dev Allows relayers or third parties to broadcast on behalf of a signer who holds MSC.
     */
    function voteBySig(
        address voter,
        uint256 _artistId,
        uint256 _amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyDuringVoting nonReentrant {
        require(voter != address(0), "Invalid voter address");
        require(block.timestamp <= deadline, "Vote signature expired");

        uint256 currentNonce = nonces[voter]++;
        bytes32 structHash = keccak256(
            abi.encode(
                VOTE_TYPEHASH,
                voter,
                votingCycle,
                _artistId,
                _amount,
                currentNonce,
                deadline
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        require(signer == voter, "Invalid vote signature");

        _castVote(voter, voter, _artistId, _amount);
    }

    /**
     * @notice Relayer/owner cast vote on behalf of an off-chain / virtual balance user.
     * @dev msg.sender (relayer) sponsors the locked tokens; vote weight is attributed to voter.
     */
    function voteForUser(
        address voter,
        uint256 _artistId,
        uint256 _amount
    ) external onlyOwner onlyDuringVoting nonReentrant {
        require(voter != address(0), "Invalid voter address");
        _castVote(voter, msg.sender, _artistId, _amount);
    }

    function _castVote(
        address voter,
        address tokenPayer,
        uint256 _artistId,
        uint256 _amount
    ) internal {
        uint256 cycle = votingCycle;
        Artist storage artist = artists[cycle][_artistId];
        require(artist.exists, "Artist does not exist");
        require(_amount > 0, "Vote amount must be greater than 0");

        voteToken.safeTransferFrom(tokenPayer, address(this), _amount);

        artist.totalVotes += _amount;
        userVotes[cycle][voter][_artistId] += _amount;
        totalUserLocked[cycle][tokenPayer] += _amount;
        cycleTotalLocked[cycle] += _amount;
        cycleOutstanding[cycle] += _amount;

        emit VoteCast(cycle, voter, _artistId, _amount);
    }

    function getArtist(uint256 _artistId)
        external
        view
        returns (uint256 id, string memory name, bool exists, uint256 totalVotes)
    {
        Artist memory artist = artists[votingCycle][_artistId];
        return (artist.id, artist.name, artist.exists, artist.totalVotes);
    }

    function getLeadingArtist() external view returns (Artist[] memory leaders) {
        uint256[] memory currentIds = artistIds[votingCycle];
        uint256 highestVotes = 0;
        uint256 leaderCount = 0;

        for (uint256 i = 0; i < currentIds.length; i++) {
            uint256 votes = artists[votingCycle][currentIds[i]].totalVotes;
            if (votes > highestVotes) {
                highestVotes = votes;
                leaderCount = 1;
            } else if (votes == highestVotes && votes > 0) {
                leaderCount++;
            }
        }

        if (highestVotes == 0) {
            return new Artist[](0);
        }

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

    function getAllArtists() external view returns (Artist[] memory) {
        uint256[] memory ids = artistIds[votingCycle];
        Artist[] memory allArtists = new Artist[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            allArtists[i] = artists[votingCycle][ids[i]];
        }
        return allArtists;
    }

    function getLeaderboard(uint256 _cycleId) external view returns (Artist[] memory) {
        uint256 targetCycle = _cycleId == 0 ? votingCycle : _cycleId;
        uint256[] memory ids = artistIds[targetCycle];
        uint256 length = ids.length;

        Artist[] memory leaderboard = new Artist[](length);
        for (uint256 i = 0; i < length; i++) {
            leaderboard[i] = artists[targetCycle][ids[i]];
        }

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

    function isVotingActive() external view returns (bool) {
        return votingStart != 0 && block.timestamp >= votingStart && block.timestamp <= votingEnd;
    }

    function _totalOutstandingAllCycles() internal view returns (uint256 total) {
        // Outstanding is tracked per cycle; sum through current cycle.
        for (uint256 i = 1; i <= votingCycle; i++) {
            total += cycleOutstanding[i];
        }
    }
}
