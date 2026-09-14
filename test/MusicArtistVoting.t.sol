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

    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;

    event ArtistAdded(uint256 indexed cycleId, uint256 indexed artistId, string name);
    event VoteCast(uint256 indexed cycleId, address indexed voter, uint256 indexed artistId, uint256 weight);
    event NewVotingCycleStarted(uint256 indexed newCycleId);
    event TokensReclaimed(uint256 indexed cycleId, address indexed voter, uint256 amount);

    function setUp() public {
        token = new MockERC20("Vote Token", "VOTE", 18);
        voting = new MusicArtistVoting(address(token));

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

    function test_RevertIf_RegisterDuringVoting() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 1000);
        vm.expectRevert("Cannot register during or after voting");
        voting.registerArtist(2, "Late Artist");
    }

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

    function test_RevertIf_ShortenActiveWindow() public {
        voting.registerArtist(1, "Artist One");
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1000;
        voting.setVotingWindow(start, end);

        vm.expectRevert("Cannot shorten active voting window");
        voting.setVotingWindow(start, end - 1);
    }

    function test_Vote() public {
        voting.registerArtist(1, "Artist One");

        uint256 start = block.timestamp;
        uint256 end = block.timestamp + 1000;
        voting.setVotingWindow(start, end);

        uint256 voteAmount = 10 * 10 ** 18;

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(1, user1, 1, voteAmount);
        voting.vote(1, voteAmount);

        (,,, uint256 votes) = voting.getArtist(1);
        assertEq(votes, voteAmount);

        assertEq(voting.userVotes(1, user1, 1), voteAmount);
        assertEq(voting.totalUserLocked(1, user1), voteAmount);

        assertEq(token.balanceOf(address(voting)), voteAmount);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE - voteAmount);
    }

    function test_RevertIf_VoteOutsideWindow() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp + 100, block.timestamp + 200);

        vm.prank(user1);
        vm.expectRevert("Voting is not active");
        voting.vote(1, 100);

        vm.warp(block.timestamp + 300);
        vm.prank(user1);
        vm.expectRevert("Voting is not active");
        voting.vote(1, 100);
    }

    function test_GetLeadingArtist_TieBreak() public {
        voting.registerArtist(1, "Artist One");
        voting.registerArtist(2, "Artist Two");
        voting.registerArtist(3, "Artist Three");

        voting.setVotingWindow(block.timestamp, block.timestamp + 1000);

        vm.prank(user1);
        voting.vote(1, 10e18);
        vm.prank(user2);
        voting.vote(2, 20e18);
        vm.prank(user3);
        voting.vote(3, 20e18);

        MusicArtistVoting.Artist[] memory leaders = voting.getLeadingArtist();

        assertEq(leaders.length, 2);
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

        vm.prank(user1);
        voting.vote(1, 10e18);
        vm.prank(user2);
        voting.vote(2, 50e18);
        vm.prank(user3);
        voting.vote(3, 5e18);
        vm.prank(user1);
        voting.vote(4, 25e18);

        MusicArtistVoting.Artist[] memory board = voting.getLeaderboard(0);

        assertEq(board.length, 4);
        assertEq(board[0].id, 2);
        assertEq(board[0].totalVotes, 50e18);
        assertEq(board[1].id, 4);
        assertEq(board[1].totalVotes, 25e18);
        assertEq(board[2].id, 1);
        assertEq(board[2].totalVotes, 10e18);
        assertEq(board[3].id, 3);
        assertEq(board[3].totalVotes, 5e18);
    }

    function test_ReclaimTokens() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 50e18);

        vm.expectRevert("Voting is still active");
        vm.prank(user1);
        voting.reclaimTokens(0);

        vm.warp(block.timestamp + 101);

        vm.expectEmit(true, true, false, true);
        emit TokensReclaimed(1, user1, 50e18);
        vm.prank(user1);
        voting.reclaimTokens(0);

        assertEq(token.balanceOf(user1), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(voting)), 0);
        assertEq(voting.totalUserLocked(1, user1), 0);
        assertEq(voting.cycleOutstanding(1), 0);
    }

    function test_AdminCannotConfiscateUserTokens() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 50e18);

        vm.warp(block.timestamp + 101);

        vm.expectRevert("No excess tokens");
        voting.withdrawExcessTokens(address(this));

        // User still owns reclaim rights
        assertEq(voting.totalUserLocked(1, user1), 50e18);
    }

    function test_WithdrawExcessOnly() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 50e18);

        // Mistaken direct transfer
        token.mint(address(voting), 10e18);

        uint256 adminBefore = token.balanceOf(address(this));
        voting.withdrawExcessTokens(address(this));
        assertEq(token.balanceOf(address(this)), adminBefore + 10e18);
        assertEq(token.balanceOf(address(voting)), 50e18);
    }

    function test_MultiCycleVoting() public {
        voting.registerArtist(1, "Cycle1 Artist");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 10e18);

        (uint256 id,,,) = voting.getArtist(1);
        assertEq(id, 1);
        assertEq(voting.artistIds(1, 0), 1);

        vm.warp(block.timestamp + 101);

        vm.expectEmit(true, false, false, false);
        emit NewVotingCycleStarted(2);
        voting.startNewVotingCycle();

        assertEq(voting.votingCycle(), 2);

        MusicArtistVoting.Artist[] memory artists = voting.getAllArtists();
        assertEq(artists.length, 0);

        (,, bool exists,) = voting.getArtist(1);
        assertFalse(exists);

        // Past-cycle reclaim still works after new cycle starts
        vm.prank(user1);
        voting.reclaimTokens(1);
        assertEq(token.balanceOf(user1), INITIAL_BALANCE);

        voting.registerArtist(1, "Cycle2 Artist");
        (,,, uint256 votes2) = voting.getArtist(1);
        assertEq(votes2, 0);
    }

    function test_CannotStartNewCycleWhileActive() public {
        voting.registerArtist(1, "Artist One");
        voting.setVotingWindow(block.timestamp, block.timestamp + 100);

        vm.prank(user1);
        voting.vote(1, 50e18);

        vm.expectRevert("Voting is still active");
        voting.startNewVotingCycle();
    }

    function test_CannotReclaimWhenVotingWindowNotSet() public {
        vm.expectRevert("Voting window not set");
        vm.prank(user1);
        voting.reclaimTokens(0);
    }
}
