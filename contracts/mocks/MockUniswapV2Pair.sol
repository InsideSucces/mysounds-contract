// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockUniswapV2Pair {
    address public token0;
    address public token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 public blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
        blockTimestampLast = uint32(block.timestamp);
    }

    function setReserves(uint112 r0, uint112 r1) public {
        _syncCumulativePrices();
        reserve0 = r0;
        reserve1 = r1;
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function sync() external {
        _syncCumulativePrices();
    }

    function _syncCumulativePrices() private {
        uint32 timeElapsed = blockTimestampLast == 0
            ? 0
            : uint32(block.timestamp) - blockTimestampLast;

        if (timeElapsed > 0 && reserve0 > 0 && reserve1 > 0) {
            price0CumulativeLast += (uint256(reserve1) * 1e18 / reserve0) * timeElapsed;
            price1CumulativeLast += (uint256(reserve0) * 1e18 / reserve1) * timeElapsed;
        }

        blockTimestampLast = uint32(block.timestamp);
    }
}
