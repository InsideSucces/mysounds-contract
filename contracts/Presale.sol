// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

/**
 * @title Presale
 * @notice ETH → MSC sale priced via Uniswap V2 TWAP (not spot).
 * @dev Oracle must be primed with `updateOracle()` and age ≥ TWAP_PERIOD before buys.
 */
contract Presale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20Metadata public immutable soundCoin;
    IUniswapV2Pair public immutable ethUsdPair;
    address public immutable usdToken;
    /// @dev True when pair.token0() is the USD token (USDC/USDT); else WETH is token0.
    bool private immutable _usdIsToken0;

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
    event OracleUpdated(uint256 priceCumulative, uint32 timestamp);

    error InsufficientPayment();
    error TransferFailed();
    error PresaleClosed();
    error PresaleNotClosed();
    error NullAddress();
    error AllocationExceeded();
    error BuyLimitExceeded();
    error NotEnoughTokensInContract();
    error ZeroLiquidity();
    error OracleNotReady();
    error TwapPeriodNotElapsed();

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

        address token0 = ethUsdPair.token0();
        address token1 = ethUsdPair.token1();
        if (token0 != _usdToken && token1 != _usdToken) revert NullAddress();
        _usdIsToken0 = token0 == _usdToken;

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

    /**
     * @notice Records a Uniswap cumulative price checkpoint. Call at least TWAP_PERIOD
     * before the first purchase (and periodically thereafter).
     */
    function updateOracle() external {
        _updateOracle();
    }

    function buyTokens() public payable whenPresaleActive nonReentrant {
        uint256 ethPaid = msg.value;
        uint256 usdPerEth = _consultTwap();
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

    /**
     * @notice Returns TWAP USD per ETH (1e18). Reverts if oracle is not ready.
     */
    function getEthPrice() public view returns (uint256 usdPerEth) {
        return _consultTwap();
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
        if (to == address(0)) revert NullAddress();
        uint256 bal = address(this).balance;
        (bool ok,) = to.call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit WithdrawETH(bal);
    }

    function withdrawTokens(address to) external onlyOwner whenPresaleClosed nonReentrant {
        if (to == address(0)) revert NullAddress();
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

    function _consultTwap() internal view returns (uint256 usdPerEth) {
        uint32 obsTimestamp = _lastObservation.timestamp;
        if (obsTimestamp == 0) revert OracleNotReady();

        uint256 elapsed = block.timestamp - uint256(obsTimestamp);
        if (elapsed < TWAP_PERIOD) revert TwapPeriodNotElapsed();

        uint256 currentCumulative = _currentCumulativeUsdPerEth();
        usdPerEth = (currentCumulative - _lastObservation.priceCumulativeUsdPerEth) / elapsed;
        if (usdPerEth == 0) revert ZeroLiquidity();
    }

    /**
     * @dev Counterfactual cumulative matching MockUniswapV2Pair's 1e18 fixed-point encoding,
     * then scaled by `_usdAdjustment` so TWAP is 18-decimal USD per ETH.
     */
    function _currentCumulativeUsdPerEth() internal view returns (uint256) {
        uint256 priceCumulative =
            _usdIsToken0 ? ethUsdPair.price1CumulativeLast() : ethUsdPair.price0CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = ethUsdPair.getReserves();

        if (reserve0 == 0 || reserve1 == 0) revert ZeroLiquidity();

        uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;
        if (timeElapsed > 0) {
            if (_usdIsToken0) {
                priceCumulative += (uint256(reserve0) * 1e18 / uint256(reserve1)) * timeElapsed;
            } else {
                priceCumulative += (uint256(reserve1) * 1e18 / uint256(reserve0)) * timeElapsed;
            }
        }

        return priceCumulative * _usdAdjustment;
    }

    function _updateOracle() internal {
        uint256 cumulative = _currentCumulativeUsdPerEth();
        uint32 ts = uint32(block.timestamp);
        _lastObservation = PriceObservation({priceCumulativeUsdPerEth: cumulative, timestamp: ts});
        emit OracleUpdated(cumulative, ts);
    }
}
