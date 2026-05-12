// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title vMSC (Vesting Sound Coin)
 * @notice Represents locked/vesting MSC tokens.
 * @dev Non-transferable token. Can only be minted and burned by the owner (Vesting Contract).
 */
contract vMSC is ERC20, Ownable {
    constructor() ERC20("Vesting Sound Coin", "vMSC") Ownable(msg.sender) {}

    /**
     * @notice Mints vMSC tokens to a user.
     * @dev Only callable by the owner (Vesting Contract).
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns vMSC tokens from a user.
     * @dev Only callable by the owner (Vesting Contract).
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @notice Overrides transfer function to prevent transfers.
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("vMSC: Non-transferable");
    }

    /**
     * @notice Overrides transferFrom function to prevent transfers.
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("vMSC: Non-transferable");
    }
}
