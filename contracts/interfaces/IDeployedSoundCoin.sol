// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @dev ABI of the currently deployed SoundCoin on Base (mintable Ownable version).
 * Used only for one-time supply finalization; source SoundCoin.sol is now fixed-supply.
 */
interface IDeployedSoundCoin {
    function mint(address to, uint256 amount) external;
    function disableMinting() external;
    function renounceOwnership() external;
    function totalSupply() external view returns (uint256);
    function owner() external view returns (address);
    function isMintable() external view returns (bool);
}
