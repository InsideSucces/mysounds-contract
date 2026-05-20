// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MusicArtistVoting} from "../contracts/MusicArtistVoting.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract MusicArtistVotingTest is Test {
    MusicArtistVoting public voting;
    MockERC20 public token;

    address public admin = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    uint256 public constant INITIAL_BALANCE = 1000 * 10**18;
    
    // Test event signatures
    event ArtistAdded(uint256 indexed cycleId, uint256 indexed artistId, string name);
    event VoteCast(uint256 indexed cycleId, address indexed voter, uint256 indexed artistId, uint256 weight);
    event NewVotingCycleStarted(uint256 indexed newCycleId);
    event TokensWithdrawn(uint256 indexed cycleId, address indexed admin, uint256 amount);

    function setUp() public {
        // Deploy Mock Token
        token = new MockERC20("Vote Token", "VOTE", 18);

        // Deploy Voting Contract
        voting = new MusicArtistVoting(address(token));

        // Setup Users
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);
        token.mint(user3, INITIAL_BALANCE);

        vm.prank(user1);
        token.approve(address(voting), type(uint256).max);

        vm.prank(user2);
        token.approve(address(voting), type(uint256).max);
        
        vm.prank(user3);
        token.approve(address(voting), type(uint256).max);
    }

    // --- Artist Registration Tests ---

    function test_RegisterArtist() public {
        vm.expectEmit(true, true, false, true);
        emit ArtistAdded(1, 1, "Artist One");
        voting.registerArtist(1, "Artist One");

        (uint256 id, string memory name, bool exists, uint256 votes) = voting.getArtist(1);
        assertEq(id, 1);
        assertEq(name, "Artist One");
        assertTrue(exists);
        assertEq(votes, 0);
    }

    function test_RevertIf_ArtistExists() public {
        voting.registerArtist(1, "Artist One");
        vm.expectRevert("Artist ID already exists in this cycle");
        voting.registerArtist(1, "Artist One Duplicate");
    }

    function test_RevertIf_NotOwnerRegisters() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        voting.registerArtist(2, "Hacker Artist");
    }

    // --- Voting Window Tests ---

    function test_SetVotingWindow() public {
        uint256 start = block.timestamp + 100;
        uint256 end = block.timestamp + 1000;
        
        voting.setVotingWindow(start, end);
        assertEq(voting.votingStart(), start);
        assertEq(voting.votingEnd(), end);
    }

    function test_RevertIf_InvalidWindow_EndTimeBeforeStart() public {
        vm.expectRevert("End time must be after start time");
        voting.setVotingWindow(block.timestamp + 1000, block.timestamp + 100);
    }



    // --- Voting Logic Tests ---

    function test_Vote() public {
        // Setup scenarios
        voting.registerArtist(1, "Artist One");
        
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1000;
        voting.setVotingWindow(start, end);

        uint256 voteAmount = 10 * 10**18;

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(1, user1, 1, voteAmount);
        voting.vote(1, voteAmount);

        // Check state
        (,,, uint256 votes) = voting.getArtist(1);
        assertEq(votes, voteAmount);
        
        assertEq(voting.userVotes(1, user1, 1), voteAmount);
        assertEq(voting.totalUserLocked(1, user1), voteAmount);
        
        // Check balance
        assertEq(token.balanceOf(address(voting)), voteAmount);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - voteAmount);
    }

    function test_RevertIf_VoteOutsideWindow() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp + 100, block.timestamp + 200);

        vm.prank(user1);
        vm.expectRevert("Voting is not active");
        voting.vote(1, 100);

        // Fast forward
        vm.warp(block.timestamp + 300);
        vm.prank(user1);
        vm.expectRevert("Voting is not active");
        voting.vote(1, 100);
    }

    // --- Leaderboard Tests ---

    function test_GetLeadingArtist_TieBreak() public {
        voting.registerArtist(1, "Artist One");
        voting.registerArtist(2, "Artist Two");
        voting.registerArtist(3, "Artist Three");
        
        voting.setVotingWindow(block.timestamp, block.timestamp + 1000);

        // Vote: A1=10, A2=20, A3=20
        vm.prank(user1); voting.vote(1, 10e18);
        vm.prank(user2); voting.vote(2, 20e18);
        vm.prank(user3); voting.vote(3, 20e18);

        MusicArtistVoting.Artist[] memory leaders = voting.getLeadingArtist();
        
        assertEq(leaders.length, 2);
        // Ordering depends on iteration, usually registration order
        // A2 (id 2) registered before A3 (id 3)? 
        // Logic iterates array, so ids[0]=1, ids[1]=2, ids[2]=3.
        // It finds 20 as max. 
        // Second pass: checks votes.
        // returns [Artist(2...), Artist(3...)]
        
        assertEq(leaders[0].id, 2);
        assertEq(leaders[1].id, 3);
        assertEq(leaders[0].totalVotes, 20e18);
    }

    function test_GetLeaderboard() public {
        voting.registerArtist(1, "Artist One");
        voting.registerArtist(2, "Artist Two");
        voting.registerArtist(3, "Artist Three");
        voting.registerArtist(4, "Artist Four");

        voting.setVotingWindow(block.timestamp, block.timestamp + 1000);

        // Vote: 
        // A1: 10
        // A2: 50
        // A3: 5
        // A4: 25
        vm.prank(user1); voting.vote(1, 10e18);
        vm.prank(user2); voting.vote(2, 50e18);
        vm.prank(user3); voting.vote(3, 5e18);
        vm.prank(user1); voting.vote(4, 25e18);

        MusicArtistVoting.Artist[] memory board = voting.getLeaderboard(0);

        assertEq(board.length, 4);
        
        // Expected Order: A2 (50), A4 (25), A1 (10), A3 (5)
        assertEq(board[0].id, 2);
        assertEq(board[0].totalVotes, 50e18);

        assertEq(board[1].id, 4);
        assertEq(board[1].totalVotes, 25e18);

        assertEq(board[2].id, 1);
        assertEq(board[2].totalVotes, 10e18);

        assertEq(board[3].id, 3);
        assertEq(board[3].totalVotes, 5e18);
    }

    // --- Withdrawal Tests ---

    function test_WithdrawTokens() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);
        
        vm.prank(user1); voting.vote(1, 50e18);

        // Try withdraw early
        vm.expectRevert("Voting is still active");
        voting.withdrawTokens();

        // Warp to end
        vm.warp(block.timestamp + 101);

        uint256 adminStartBal = token.balanceOf(address(this));
        
        vm.expectEmit(true, true, false, true);
        emit TokensWithdrawn(1, address(this), 50e18);
        voting.withdrawTokens();

        assertEq(token.balanceOf(address(this)), adminStartBal + 50e18);
        assertEq(token.balanceOf(address(voting)), 0);
    }

    // --- Multi-Cycle Tests ---

    function test_MultiCycleVoting() public {
        // Cycle 1
        voting.registerArtist(1, "Cycle1 Artist");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);
        
        vm.prank(user1); voting.vote(1, 10e18);
        
        // Assert Cycle 1 state
        (uint256 id,,,) = voting.getArtist(1);
        assertEq(id, 1);
        assertEq(voting.artistIds(1, 0), 1);

        vm.warp(block.timestamp + 101);
        voting.withdrawTokens();

        vm.expectEmit(true, false, false, false);
        emit NewVotingCycleStarted(2);
        voting.startNewVotingCycle();
        
        assertEq(voting.votingCycle(), 2);

        // Verify Cycle 2 is empty
        MusicArtistVoting.Artist[] memory artists = voting.getAllArtists();
        assertEq(artists.length, 0);

        // Verify Cycle 1 data persists (by reading raw storage or helper if available, assumes getArtist reads current cycle)
        // Actually getArtist reads 'votingCycle' which is now 2. 
        // So getArtist(1) should return empty/false for cycle 2
        (uint256 id2,,bool exists,) = voting.getArtist(1);
        assertFalse(exists);

        // Register new artist for Cycle 2 (can reuse ID 1 if we want, or new IDs)
        voting.registerArtist(1, "Cycle2 Artist");
        (,,, uint256 votes2) = voting.getArtist(1);
        assertEq(votes2, 0); // Fresh start
    }

    function test_CannotWithdrawAfterNewCycleWithoutPriorWithdraw() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 50e18);

        vm.warp(block.timestamp + 101);

        vm.expectRevert("Withdraw previous cycle first");
        voting.startNewVotingCycle();
    }

    function test_WithdrawOnlyCycleLockedAmount() public {
        voting.registerArtist(1, "Cycle1 Artist");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 30e18);

        vm.warp(block.timestamp + 101);
        voting.withdrawTokens();

        voting.startNewVotingCycle();
        voting.registerArtist(1, "Cycle2 Artist");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user2);
        voting.vote(1, 20e18);

        vm.warp(block.timestamp + 101);

        uint256 adminBalBefore = token.balanceOf(address(this));
        voting.withdrawTokens();

        assertEq(token.balanceOf(address(this)), adminBalBefore + 20e18);
        assertEq(token.balanceOf(address(voting)), 0);
    }

    function test_CannotWithdrawWhenVotingWindowNotSet() public {
        vm.expectRevert("Voting window not set");
        voting.withdrawTokens();
    }
}
