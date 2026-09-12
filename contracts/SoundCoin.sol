// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SoundCoin is ERC20 {
    constructor() ERC20("Sound Coin", "MSC") {
        _mint(msg.sender, 500_000_000 * 10 ** decimals());
    }
}
