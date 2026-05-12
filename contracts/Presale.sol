// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

contract Presale is Ownable, ReentrancyGuard {
    IERC20Metadata public immutable soundCoin;
    IUniswapV2Pair public immutable ethUsdPair;
    address public immutable usdToken;

    uint256 public sold;
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    address public tokenWallet; // owner funding source for depositTokens
    bool public presaleClosed = false;

    // BUY LIMITS (USD * 1e18)
    uint256 public constant MIN_BUY = 10 * 1e18; // $10
    uint256 public constant MAX_BUY = 50000 * 1e18; // $50,000

    uint256 public constant ALLOCATION = 125_000_000 * 1e18;

    mapping(address => uint256) public contributions;

    event Bought(address indexed buyer, uint256 ethPaid, uint256 usdValue, uint256 tokensBought);
    event TokenWalletSet(address indexed newWallet);
    event WithdrawETH(uint256 amount);
    event WithdrawTokens(uint256 amount);
    event PresaleClosedEvent();
    event TokensDeposited(address indexed from, uint256 amount);

    error InsufficientPayment();
    error TransferFailed();
    error PresaleClosed();
    error PresaleNotClosed();
    error NullAddress();
    error AllocationExceeded();
    error BuyLimitExceeded();
    error NotEnoughTokensInContract();

    constructor(
        address _soundCoinAddress,
        uint256 _presaleStartTime,
        uint256 _presaleEndTime,
        address _pairAddress,
        address _usdToken
    ) Ownable(msg.sender) {
        require(_presaleEndTime > _presaleStartTime, "Bad time");
        if (_soundCoinAddress == address(0) || _pairAddress == address(0) || _usdToken == address(0)) {
            revert NullAddress();
        }

        soundCoin = IERC20Metadata(_soundCoinAddress);
        presaleStartTime = _presaleStartTime;
        presaleEndTime = _presaleEndTime;
        ethUsdPair = IUniswapV2Pair(_pairAddress);
        usdToken = _usdToken;
        tokenWallet = msg.sender;
    }

    /// @dev presale is active when not manually closed AND current time is within window
    modifier whenPresaleActive() {
        if (presaleClosed || block.timestamp > presaleEndTime) {
            revert PresaleClosed();
        }
        _;
    }

    /// @dev considered closed either by owner or when time ended
    modifier whenPresaleClosed() {
        if (!presaleClosed && block.timestamp <= presaleEndTime) revert PresaleNotClosed();
        _;
    }

    /// @notice Buy tokens by sending ETH. Contract must hold enough tokens.
    function buyTokens() public payable whenPresaleActive nonReentrant {
        uint256 ethPaid = msg.value;
        uint256 usdPerEth = getEthPrice();

        uint256 usdValue = (ethPaid * usdPerEth) / 1e18;

        if (usdValue < MIN_BUY) revert BuyLimitExceeded();
        if (contributions[msg.sender] + usdValue > MAX_BUY) revert BuyLimitExceeded();

        uint8 decimals = soundCoin.decimals();

        uint256 tokensToBuy = (usdValue * (10 ** decimals)) / 1e18;

        if (tokensToBuy + sold > ALLOCATION) revert AllocationExceeded();
        uint256 contractBalance = soundCoin.balanceOf(address(this));
        if (contractBalance < tokensToBuy) revert NotEnoughTokensInContract();

        contributions[msg.sender] += usdValue;
        sold += tokensToBuy;

        bool success = soundCoin.transfer(msg.sender, tokensToBuy);
        if (!success) revert TransferFailed();

        emit Bought(msg.sender, ethPaid, usdValue, tokensToBuy);
    }

    /// @notice Read ETH price from pair (USD per ETH scaled by 1e18)
    function getEthPrice() public view returns (uint256 usdPerEth) {
        (uint112 reserve0, uint112 reserve1,) = ethUsdPair.getReserves();
        address token0 = ethUsdPair.token0();

        uint256 reserveUsd;
        uint256 reserveEth;

        if (token0 == usdToken) {
            reserveUsd = reserve0;
            reserveEth = reserve1;
        } else {
            reserveUsd = reserve1;
            reserveEth = reserve0;
        }

        // Adjust for decimals: USD token usually has 6 decimals, WETH has 18
        uint256 usdDecimals = IERC20Metadata(usdToken).decimals();
        uint256 usdAdjustment = 10 ** (18 - usdDecimals); // usually 1e12 for 6-decimal tokens

        usdPerEth = (reserveUsd * usdAdjustment * 1e18) / reserveEth;
    }

    /// @notice Owner can close presale early
    function closePresale() external onlyOwner {
        presaleClosed = true;
        emit PresaleClosedEvent();
    }

    function setTokenWallet(address _wallet) external onlyOwner {
        if (_wallet == address(0)) revert NullAddress();
        tokenWallet = _wallet;
        emit TokenWalletSet(_wallet);
    }

    /// @notice Owner can deposit tokens from tokenWallet (requires tokenWallet approved allowance for this contract)
    function depositTokens(uint256 amount) external onlyOwner nonReentrant {
        if (tokenWallet == address(0)) revert NullAddress();
        bool success = soundCoin.transferFrom(tokenWallet, address(this), amount);
        if (!success) revert TransferFailed();
        emit TokensDeposited(tokenWallet, amount);
    }

    /// @notice Withdraw collected ETH after presale closed or ended
    function withdrawETH(address payable to) external onlyOwner whenPresaleClosed nonReentrant {
        uint256 bal = address(this).balance;
        to.call{value: bal}("");
        emit WithdrawETH(bal);
    }

    /// @notice Withdraw unsold tokens (contract holds allocation)
    function withdrawTokens(address to) external onlyOwner whenPresaleClosed nonReentrant {
        uint256 contractBalance = soundCoin.balanceOf(address(this));
        uint256 unsold = 0;
        if (ALLOCATION > sold) {
            uint256 theoreticallyUnsold = ALLOCATION - sold;
            unsold = contractBalance < theoreticallyUnsold ? contractBalance : theoreticallyUnsold;
        }

        if (unsold == 0) revert TransferFailed();

        bool success = soundCoin.transfer(to, unsold);
        if (!success) revert TransferFailed();

        emit WithdrawTokens(unsold);
    }

    function getRemainingAllowance() external view returns (uint256) {
        return soundCoin.allowance(tokenWallet, address(this));
    }

    receive() external payable {
        buyTokens();
    }
}
