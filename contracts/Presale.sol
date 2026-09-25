// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/**
 * @title Presale
 * @notice ETH → MSC presale priced via Chainlink ETH/USD Price Feed on Base.
 */
contract Presale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20Metadata public immutable soundCoin;
    AggregatorV3Interface public priceFeed;
    address payable private _reserveVault;

    uint8 private immutable _tokenDecimals;

    uint256 public sold;
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    address public tokenWallet;
    bool public presaleClosed = false;
    uint256 public manualPrice; // Optional fallback override in 1e18 format (0 = use Chainlink)

    uint256 public constant MIN_BUY = 10 * 1e18; // $10 USD
    uint256 public constant MAX_BUY = 50000 * 1e18; // $50,000 USD
    uint256 public constant ALLOCATION = 125_000_000 * 1e18; // 125,000,000 MSC
    uint256 public constant RESERVE_BPS = 1000; // 10%

    mapping(address => uint256) public contributions;

    event Bought(address indexed buyer, uint256 ethPaid, uint256 usdValue, uint256 tokensBought);
    event TokenWalletSet(address indexed newWallet);
    event WithdrawETH(uint256 amount);
    event WithdrawTokens(uint256 amount);
    event PresaleClosedEvent();
    event TokensDeposited(address indexed from, uint256 amount);
    event PriceFeedUpdated(address indexed newFeed);
    event ManualPriceUpdated(uint256 newPrice);
    event PresaleTimeUpdated(uint256 startTime, uint256 endTime);
    event ReserveVaultUpdated(address indexed newVault);

    error InsufficientPayment();
    error TransferFailed();
    error PresaleClosed();
    error PresaleNotClosed();
    error NullAddress();
    error AllocationExceeded();
    error BuyLimitExceeded();
    error NotEnoughTokensInContract();
    error OracleNotReady();

    constructor(
        address _soundCoinAddress,
        uint256 _presaleStartTime,
        uint256 _presaleEndTime,
        address _priceFeedAddress,
        address payable _vaultAddress
    ) Ownable(msg.sender) {
        require(_presaleEndTime > _presaleStartTime, "Bad time");
        if (_soundCoinAddress == address(0) || _vaultAddress == address(0)) {
            revert NullAddress();
        }

        soundCoin = IERC20Metadata(_soundCoinAddress);
        presaleStartTime = _presaleStartTime;
        presaleEndTime = _presaleEndTime;
        if (_priceFeedAddress != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeedAddress);
        }
        tokenWallet = msg.sender;
        _reserveVault = _vaultAddress;

        _tokenDecimals = soundCoin.decimals();
    }

    modifier whenPresaleActive() {
        if (presaleClosed || block.timestamp < presaleStartTime || block.timestamp > presaleEndTime) {
            revert PresaleClosed();
        }
        _;
    }

    /**
     * @notice Returns ETH price in 18-decimal USD ($/ETH * 1e18).
     */
    function getEthPrice() public view returns (uint256 usdPerEth) {
        if (manualPrice > 0) {
            return manualPrice;
        }
        if (address(priceFeed) == address(0)) revert OracleNotReady();

        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        if (price <= 0 || updatedAt == 0) revert OracleNotReady();

        uint8 feedDecimals = priceFeed.decimals();
        if (feedDecimals <= 18) {
            usdPerEth = uint256(price) * (10 ** (18 - feedDecimals));
        } else {
            usdPerEth = uint256(price) / (10 ** (feedDecimals - 18));
        }
    }

    function buyTokens() public payable whenPresaleActive nonReentrant {
        uint256 ethPaid = msg.value;
        if (ethPaid == 0) revert InsufficientPayment();

        uint256 usdPerEth = getEthPrice();
        uint256 usdValue = (ethPaid * usdPerEth) / 1e18;

        if (usdValue < MIN_BUY) revert BuyLimitExceeded();

        uint256 userContribution = contributions[msg.sender];
        if (userContribution + usdValue > MAX_BUY) revert BuyLimitExceeded();

        uint256 tokensToBuy = (usdValue * (10 ** _tokenDecimals)) / 1e18;

        uint256 soldAmount = sold;
        if (tokensToBuy + soldAmount > ALLOCATION) revert AllocationExceeded();

        uint256 contractBalance = soundCoin.balanceOf(address(this));
        if (contractBalance < tokensToBuy) revert NotEnoughTokensInContract();

        contributions[msg.sender] = userContribution + usdValue;
        sold = soldAmount + tokensToBuy;

        uint256 reserveShare = (ethPaid * RESERVE_BPS) / 10000;
        if (reserveShare > 0) {
            (bool ok,) = _reserveVault.call{value: reserveShare}("");
            if (!ok) revert TransferFailed();
        }

        IERC20(address(soundCoin)).safeTransfer(msg.sender, tokensToBuy);

        emit Bought(msg.sender, ethPaid, usdValue, tokensToBuy);
    }

    function setPriceFeed(address _newFeed) external onlyOwner {
        if (_newFeed == address(0)) revert NullAddress();
        priceFeed = AggregatorV3Interface(_newFeed);
        emit PriceFeedUpdated(_newFeed);
    }

    function setManualPrice(uint256 _newPrice) external onlyOwner {
        manualPrice = _newPrice;
        emit ManualPriceUpdated(_newPrice);
    }

    function setPresaleTime(uint256 _startTime, uint256 _endTime) external onlyOwner {
        require(_endTime > _startTime, "Bad time");
        presaleStartTime = _startTime;
        presaleEndTime = _endTime;
        emit PresaleTimeUpdated(_startTime, _endTime);
    }

    function setReserveVault(address payable _vault) external onlyOwner {
        if (_vault == address(0)) revert NullAddress();
        _reserveVault = _vault;
        emit ReserveVaultUpdated(_vault);
    }

    function getReserveVault() external view returns (address) {
        return _reserveVault;
    }

    function closePresale() external onlyOwner {
        presaleClosed = true;
        emit PresaleClosedEvent();
    }

    function openPresale() external onlyOwner {
        presaleClosed = false;
    }

    function setTokenWallet(address _wallet) external onlyOwner {
        if (_wallet == address(0)) revert NullAddress();
        tokenWallet = _wallet;
        emit TokenWalletSet(_wallet);
    }

    function depositTokens(uint256 amount) external onlyOwner nonReentrant {
        if (tokenWallet == address(0)) revert NullAddress();
        IERC20(address(soundCoin)).safeTransferFrom(tokenWallet, address(this), amount);
        emit TokensDeposited(tokenWallet, amount);
    }

    function withdrawETH(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert NullAddress();
        uint256 bal = address(this).balance;
        (bool ok,) = to.call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit WithdrawETH(bal);
    }

    function withdrawTokens(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert NullAddress();
        uint256 contractBalance = soundCoin.balanceOf(address(this));
        if (contractBalance == 0) revert TransferFailed();
        IERC20(address(soundCoin)).safeTransfer(to, contractBalance);
        emit WithdrawTokens(contractBalance);
    }

    function withdrawTokens(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert NullAddress();
        uint256 contractBalance = soundCoin.balanceOf(address(this));
        uint256 withdrawAmount = (amount == 0 || amount > contractBalance) ? contractBalance : amount;
        if (withdrawAmount == 0) revert TransferFailed();
        IERC20(address(soundCoin)).safeTransfer(to, withdrawAmount);
        emit WithdrawTokens(withdrawAmount);
    }

    function getRemainingAllowance() external view returns (uint256) {
        return soundCoin.allowance(tokenWallet, address(this));
    }

    receive() external payable {
        buyTokens();
    }
}
