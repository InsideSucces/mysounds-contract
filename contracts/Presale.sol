// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

contract Presale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20Metadata public immutable soundCoin;
    IUniswapV2Pair public immutable ethUsdPair;
    address public immutable usdToken;

    uint8 private immutable _tokenDecimals;
    uint256 private immutable _usdAdjustment;

    uint256 public sold;
    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    address public tokenWallet;
    bool public presaleClosed = false;

    uint256 public constant MIN_BUY = 10 * 1e18;
    uint256 public constant MAX_BUY = 50000 * 1e18;
    uint256 public constant ALLOCATION = 125_000_000 * 1e18;
    uint32 public constant TWAP_PERIOD = 30 minutes;

    struct PriceObservation {
        uint256 priceCumulativeUsdPerEth;
        uint32 timestamp;
    }

    PriceObservation private _lastObservation;

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
    error ZeroLiquidity();

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

        _tokenDecimals = soundCoin.decimals();
        uint8 usdDecimals = IERC20Metadata(_usdToken).decimals();
        require(usdDecimals <= 18, "USD decimals too high");
        _usdAdjustment = 10 ** (18 - usdDecimals);
    }

    modifier whenPresaleActive() {
        if (presaleClosed || block.timestamp < presaleStartTime || block.timestamp > presaleEndTime) {
            revert PresaleClosed();
        }
        _;
    }

    modifier whenPresaleClosed() {
        if (!presaleClosed && block.timestamp <= presaleEndTime) revert PresaleNotClosed();
        _;
    }

    function buyTokens() public payable whenPresaleActive nonReentrant {
        uint256 ethPaid = msg.value;
        uint256 usdPerEth = getEthPrice();
        _updateOracle();
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

        IERC20(address(soundCoin)).safeTransfer(msg.sender, tokensToBuy);

        emit Bought(msg.sender, ethPaid, usdValue, tokensToBuy);
    }

    function getEthPrice() public view returns (uint256 usdPerEth) {
        uint32 obsTimestamp = _lastObservation.timestamp;
        if (obsTimestamp == 0) {
            return _spotUsdPerEth();
        }

        uint256 elapsed = block.timestamp - obsTimestamp;
        if (elapsed == 0) {
            return _spotUsdPerEth();
        }

        uint256 currentCumulative = _currentCumulativeUsdPerEth();
        usdPerEth = (currentCumulative - _lastObservation.priceCumulativeUsdPerEth) / elapsed;
    }

    function closePresale() external onlyOwner {
        presaleClosed = true;
        emit PresaleClosedEvent();
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

    function withdrawETH(address payable to) external onlyOwner whenPresaleClosed nonReentrant {
        uint256 bal = address(this).balance;
        (bool ok,) = to.call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit WithdrawETH(bal);
    }

    function withdrawTokens(address to) external onlyOwner whenPresaleClosed nonReentrant {
        uint256 contractBalance = soundCoin.balanceOf(address(this));
        uint256 unsold = 0;
        uint256 soldAmount = sold;
        if (ALLOCATION > soldAmount) {
            uint256 theoreticallyUnsold;
            unchecked {
                theoreticallyUnsold = ALLOCATION - soldAmount;
            }
            unsold = contractBalance < theoreticallyUnsold ? contractBalance : theoreticallyUnsold;
        }

        if (unsold == 0) revert TransferFailed();

        IERC20(address(soundCoin)).safeTransfer(to, unsold);

        emit WithdrawTokens(unsold);
    }

    function getRemainingAllowance() external view returns (uint256) {
        return soundCoin.allowance(tokenWallet, address(this));
    }

    receive() external payable {
        buyTokens();
    }

    function _spotUsdPerEth() internal view returns (uint256) {
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

        if (reserveEth == 0) revert ZeroLiquidity();

        return (reserveUsd * _usdAdjustment * 1e18) / reserveEth;
    }

    function _currentCumulativeUsdPerEth() internal view returns (uint256) {
        uint32 obsTimestamp = _lastObservation.timestamp;
        if (obsTimestamp == 0) {
            return 0;
        }
        return _lastObservation.priceCumulativeUsdPerEth
            + _spotUsdPerEth() * (block.timestamp - obsTimestamp);
    }

    function _updateOracle() internal {
        _lastObservation = PriceObservation({
            priceCumulativeUsdPerEth: _currentCumulativeUsdPerEth(),
            timestamp: uint32(block.timestamp)
        });
    }
}
