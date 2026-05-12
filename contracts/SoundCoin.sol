// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SoundCoin is ERC20, Ownable {
    bool public isMintable = true;
    uint256 public immutable maxSupply = 1_000_000_000 * 10 ** decimals();

    constructor() ERC20("Sound Coin", "MSC") Ownable(msg.sender) {
        _mint(msg.sender, 100_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(isMintable, "SoundCoin: Minting is disabled");
        require(totalSupply() + amount <= maxSupply, "SoundCoin: Exceeds max supply");
        _mint(to, amount);
    }

    function disableMinting() external onlyOwner {
        isMintable = false;
    }
}
