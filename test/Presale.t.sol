// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Presale} from "../contracts/Presale.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../contracts/mocks/MockAggregatorV3.sol";

contract PresaleTest is Test {
    Presale public presale;
    MockERC20 public soundCoin;
    MockAggregatorV3 public priceFeed;

    address public owner = address(0x1);
    address public buyer1 = address(0x2);
    address public buyer2 = address(0x3);
    address public tokenWallet = address(0x4);
    address payable public reserveVault = payable(address(0x5));

    uint8 public constant DECIMALS = 18;
    uint256 public constant TOKEN_SUPPLY = 500_000_000 * 1e18;
    uint256 public constant ALLOCATION = 125_000_000 * 1e18;

    uint256 public presaleStartTime;
    uint256 public presaleEndTime;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        soundCoin = new MockERC20("Sound Coin", "SOUND", 18);

        // Mint
        soundCoin.mint(tokenWallet, TOKEN_SUPPLY);

        // Mock Chainlink ETH/USD feed at $2000 (8 decimals: 2000 * 1e8)
        priceFeed = new MockAggregatorV3(8, 2000 * 1e8);

        presaleStartTime = block.timestamp + 1 hours;
        presaleEndTime = presaleStartTime + 30 days;

        presale = new Presale(
            address(soundCoin),
            presaleStartTime,
            presaleEndTime,
            address(priceFeed),
            reserveVault
        );

        presale.setTokenWallet(tokenWallet);
        vm.stopPrank();

        // Approve and deposit full allocation
        vm.prank(tokenWallet);
        soundCoin.approve(address(presale), type(uint256).max);

        vm.prank(owner);
        presale.depositTokens(ALLOCATION);

        // Enter presale window
        vm.warp(presaleStartTime + 1);
    }

    function test_ConstructorSetsValuesCorrectly() public view {
        assertEq(address(presale.soundCoin()), address(soundCoin));
        assertEq(presale.presaleStartTime(), presaleStartTime);
        assertEq(presale.presaleEndTime(), presaleEndTime);
        assertEq(address(presale.priceFeed()), address(priceFeed));
        assertEq(presale.tokenWallet(), tokenWallet);
        assertEq(presale.owner(), owner);
    }

    function test_GetEthPrice() public view {
        uint256 price = presale.getEthPrice();
        assertEq(price, 2000 * 1e18);
    }

    function test_BuyTokens_Success() public {
        uint256 ethToSend = 1 ether;
        uint256 usdValue = (ethToSend * 2000 * 1e18) / 1e18; // $2000
        uint256 expectedTokens = usdValue; // 1 USD = 1 SOUND (18 decimals)

        vm.deal(buyer1, 10 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: ethToSend}();

        assertEq(presale.contributions(buyer1), usdValue);
        assertEq(presale.sold(), expectedTokens);
        assertEq(soundCoin.balanceOf(buyer1), expectedTokens);
    }

    function test_BuyTokens_MinBuyLimit() public {
        // $2000/ETH → $10 = 0.005 ETH
        uint256 tinyEth = 0.0049 ether; // ~$9.8 < $10

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(Presale.BuyLimitExceeded.selector);
        presale.buyTokens{value: tinyEth}();
    }

    function test_BuyTokens_MaxBuyPerUser() public {
        vm.deal(buyer1, 100 ether);

        // First buy: $49,999
        uint256 firstBuy = 24.9995 ether; // ~$49,999
        vm.prank(buyer1);
        presale.buyTokens{value: firstBuy}();

        // Second buy: would push over $50k
        vm.prank(buyer1);
        vm.expectRevert(Presale.BuyLimitExceeded.selector);
        presale.buyTokens{value: 0.001 ether}();
    }

    function test_BuyTokens_FeeSplit10Percent() public {
        uint256 ethToSend = 1 ether;
        uint256 devBalBefore = reserveVault.balance;

        vm.deal(buyer1, 10 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: ethToSend}();

        // 10% reserve share to reserveVault (0.1 ETH), 90% in presale contract (0.9 ETH)
        assertEq(reserveVault.balance - devBalBefore, 0.1 ether);
        assertEq(address(presale).balance, 0.9 ether);
    }

    function test_BuyTokens_NotEnoughTokensInContract() public {
        Presale underfunded = new Presale(
            address(soundCoin),
            block.timestamp + 1,
            block.timestamp + 7 days,
            address(priceFeed),
            reserveVault
        );

        underfunded.setTokenWallet(tokenWallet);

        vm.prank(tokenWallet);
        soundCoin.approve(address(underfunded), 100);
        underfunded.depositTokens(100);

        vm.warp(block.timestamp + 1 hours);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(Presale.NotEnoughTokensInContract.selector);
        underfunded.buyTokens{value: 1 ether}();
    }

    function test_ClosePresaleEarly() public {
        vm.prank(owner);
        presale.closePresale();

        assertTrue(presale.presaleClosed());

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(Presale.PresaleClosed.selector);
        presale.buyTokens{value: 1 ether}();
    }

    function test_WithdrawETH_AfterPresale() public {
        address payable recipient = payable(makeAddr("recipient"));

        vm.deal(buyer1, 5 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}();

        vm.prank(owner);
        presale.closePresale();

        uint256 initialBal = recipient.balance;
        vm.prank(owner);
        presale.withdrawETH(recipient);

        // 90% of 5 ETH = 4.5 ETH
        assertEq(recipient.balance, initialBal + 4.5 ether);
    }

    function test_WithdrawUnsoldTokens() public {
        vm.deal(buyer1, 0.1 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: 0.1 ether}();

        vm.warp(presaleEndTime + 1);

        uint256 bal = soundCoin.balanceOf(address(presale));

        vm.prank(owner);
        presale.withdrawTokens(owner);

        assertEq(soundCoin.balanceOf(owner), bal);
    }

    function test_CannotBuyAfterPresaleEnd() public {
        vm.warp(presaleEndTime + 1);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(Presale.PresaleClosed.selector);
        presale.buyTokens{value: 1 ether}();
    }

    function test_CannotBuyBeforePresaleStart() public {
        vm.warp(presaleStartTime - 1);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(Presale.PresaleClosed.selector);
        presale.buyTokens{value: 1 ether}();
    }

    function test_ReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(presale);
        vm.deal(address(attacker), 10 ether);

        uint256 expectedTokens = 2000 * 1e18; // 1 ETH → $2000 → 2000 tokens

        attacker.attack{value: 1 ether}();

        assertEq(presale.sold(), expectedTokens);
        assertEq(soundCoin.balanceOf(address(attacker)), expectedTokens);
    }
}

contract ReentrancyAttacker {
    Presale public presale;

    constructor(Presale _presale) {
        presale = _presale;
    }

    function attack() external payable {
        presale.buyTokens{value: msg.value}();
    }

    receive() external payable {
        if (address(presale).balance >= 1 ether) {
            presale.buyTokens{value: 1 ether}();
        }
    }
}
