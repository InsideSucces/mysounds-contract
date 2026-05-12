// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Presale} from "../contracts/Presale.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {MockUniswapV2Pair} from "../contracts/mocks/MockUniswapV2Pair.sol";

contract PresaleTest is Test {
    Presale public presale;
    MockERC20 public soundCoin;
    MockUniswapV2Pair public ethUsdPair;
    MockERC20 public usdToken; // e.g. USDC or USDT mock

    address public owner = address(0x1);
    address public buyer1 = address(0x2);
    address public buyer2 = address(0x3);
    address public tokenWallet = address(0x4);

    uint8 public constant DECIMALS = 18;
    uint256 public constant TOKEN_SUPPLY = 500_000_000 * 1e18;
    uint256 public constant ALLOCATION = 125_000_000 * 1e18;

    uint256 public presaleStartTime;
    uint256 public presaleEndTime;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        soundCoin = new MockERC20("Sound Coin", "SOUND", 18);
        usdToken = new MockERC20("USD Token", "USDT", 6); // 6 decimals

        // Mint
        soundCoin.mint(tokenWallet, TOKEN_SUPPLY);

        // === FIX: Realistic liquidity with correct decimals ===
        // 1000 ETH = $2,000,000 USDT → $2000/ETH
        uint256 wethReserve = 1000 ether;
        uint256 usdtReserve = 2_000_000 * 1e6; // 2M USDT (6 decimals)

        ethUsdPair = new MockUniswapV2Pair(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH = token0
            address(usdToken)
        );
        ethUsdPair.setReserves(uint112(wethReserve), uint112(usdtReserve));

        presaleStartTime = block.timestamp + 1 hours;
        presaleEndTime = presaleStartTime + 30 days;

        presale = new Presale(
            address(soundCoin), presaleStartTime, presaleEndTime, address(ethUsdPair), address(usdToken)
        );

        presale.setTokenWallet(tokenWallet);
        vm.stopPrank();

        // Approve and deposit full allocation
        vm.prank(tokenWallet);
        soundCoin.approve(address(presale), type(uint256).max);

        vm.prank(owner);
        presale.depositTokens(ALLOCATION);

        // Start presale
        vm.warp(presaleStartTime + 1);
    }

    function test_ConstructorSetsValuesCorrectly() public view {
        assertEq(address(presale.soundCoin()), address(soundCoin));
        assertEq(presale.presaleStartTime(), presaleStartTime);
        assertEq(presale.presaleEndTime(), presaleEndTime);
        assertEq(address(presale.ethUsdPair()), address(ethUsdPair));
        assertEq(presale.usdToken(), address(usdToken));
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

    // function test_BuyTokens_AllocationExceeded() public {
    //     // Use many different buyers so no one hits $50k limit
    //     uint256 ethPerBuyer = 20 ether; // ~$40,000
    //     uint256 buyersNeeded = 62; // 70 * $40k = $2.8M → way over allocation

    //     for (uint160 i = 1; i <= buyersNeeded; i++) {
    //         address buyer = address(i);
    //         vm.deal(buyer, ethPerBuyer);
    //         vm.prank(buyer);
    //         presale.buyTokens{value: ethPerBuyer}();
    //     }

    //     // Now any new buy should fail with AllocationExceeded
    //     address newBuyer = address(0xFF);
    //     vm.deal(newBuyer, 20 ether);
    //     vm.prank(newBuyer);
    //     vm.expectRevert(Presale.AllocationExceeded.selector);
    //     presale.buyTokens{value: 20 ether}();
    // }

    function test_BuyTokens_FullEthHeldByPresale() public {
        uint256 ethToSend = 1 ether;

        vm.deal(buyer1, 10 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: ethToSend}();

        assertEq(address(presale).balance, ethToSend);
    }

    function test_BuyTokens_NotEnoughTokensInContract() public {
        // Create new underfunded presale
        Presale underfunded = new Presale(
            address(soundCoin),
            block.timestamp + 1,
            block.timestamp + 7 days,
            address(ethUsdPair),
            address(usdToken)
        );

        // Owner of the new contract is THIS test contract
        vm.prank(address(this)); // ← critical!
        underfunded.setTokenWallet(tokenWallet);

        // Deposit only 100 tokens
        vm.prank(tokenWallet);
        soundCoin.approve(address(underfunded), 100);
        vm.prank(address(this));
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
        address payable recipient = payable(makeAddr("recipient")); // safe address

        vm.deal(buyer1, 5 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: 5 ether}();

        vm.prank(owner);
        presale.closePresale();

        uint256 initialBal = recipient.balance;
        vm.prank(owner);
        presale.withdrawETH(recipient);

        assertEq(recipient.balance, initialBal + 5 ether);
    }

    function test_WithdrawUnsoldTokens() public {
        // Only small purchase
        vm.deal(buyer1, 0.1 ether);
        vm.prank(buyer1);
        presale.buyTokens{value: 0.1 ether}();

        vm.warp(presaleEndTime + 1);

        uint256 unsold = ALLOCATION - presale.sold();

        vm.prank(owner);
        presale.withdrawTokens(owner);

        assertEq(soundCoin.balanceOf(owner), unsold);
    }

    function test_CannotBuyAfterPresaleEnd() public {
        vm.warp(presaleEndTime + 1);

        vm.deal(buyer1, 1 ether);
        vm.prank(buyer1);
        vm.expectRevert(Presale.PresaleClosed.selector);
        presale.buyTokens{value: 1 ether}();
    }

    function test_DepositTokens_RequiresApproval() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        newToken.mint(tokenWallet, 1000);

        vm.prank(owner);
        Presale newPresale = new Presale(
            address(newToken),
            block.timestamp + 1,
            block.timestamp + 1 days,
            address(ethUsdPair),
            address(usdToken)
        );

        vm.prank(owner);
        newPresale.setTokenWallet(tokenWallet);

        // No approval → should fail
        vm.prank(owner);
        vm.expectRevert(); // transferFrom fails
        newPresale.depositTokens(500);
    }

    function test_ReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(presale);
        vm.deal(address(attacker), 10 ether);

        uint256 expectedTokens = 2000 * 1e18; // 1 ETH → $2000 → 2000 tokens

        // nonReentrant blocks second call
        attacker.attack{value: 1 ether}();

        // Only one purchase should have succeeded
        assertEq(presale.sold(), expectedTokens);
        assertEq(soundCoin.balanceOf(address(attacker)), expectedTokens);
    }
}

// Simple malicious contract to test reentrancy
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
