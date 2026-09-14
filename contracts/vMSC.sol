// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title vMSC (Vesting Sound Coin)
 * @notice Represents locked/vesting MSC tokens.
 * @dev Non-transferable. Mint/burn only by owner (MSCVesting). Transfers blocked via `_update`.
 */
contract vMSC is ERC20, Ownable {
    error NonTransferable();

    constructor() ERC20("Vesting Sound Coin", "vMSC") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /// @dev Blocks all peer-to-peer transfers; mint (from=0) and burn (to=0) remain allowed.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert NonTransferable();
        super._update(from, to, value);
    }
}
