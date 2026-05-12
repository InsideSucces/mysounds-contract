// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CouponManager is EIP712, Ownable, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    IERC20 public immutable soundCoin;
    
    bytes32 private constant COUPON_TYPEHASH = keccak256(
        "Coupon(address user,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    mapping(address => uint256) public nonces;
    mapping(address => bool) public authorizedSigners;

    event CouponRedeemed(address indexed user, uint256 amount, uint256 nonce);
    event SignerStatusChanged(address indexed signer, bool status);

    error InvalidSignature();
    error DeadlineExpired();
    error UnauthorizedSigner();
    error ZeroAddress();
    error InsufficientContractBalance();

    constructor(address _soundCoin, address _initialSigner) 
        EIP712("CouponManager", "1") 
        Ownable(msg.sender) 
    {
        if (_soundCoin == address(0) || _initialSigner == address(0)) revert ZeroAddress();
        soundCoin = IERC20(_soundCoin);
        authorizedSigners[_initialSigner] = true;
        emit SignerStatusChanged(_initialSigner, true);
    }

    function redeem(
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (nonce != nonces[msg.sender]) revert InvalidSignature();

        bytes32 structHash = keccak256(
            abi.encode(COUPON_TYPEHASH, msg.sender, amount, nonce, deadline)
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        if (!authorizedSigners[signer]) revert UnauthorizedSigner();
        if (soundCoin.balanceOf(address(this)) < amount) revert InsufficientContractBalance();

        nonces[msg.sender]++;
        
        soundCoin.safeTransfer(msg.sender, amount);

        emit CouponRedeemed(msg.sender, amount, nonce);
    }

    function setSignerStatus(address signer, bool status) external onlyOwner {
        if (signer == address(0)) revert ZeroAddress();
        authorizedSigners[signer] = status;
        emit SignerStatusChanged(signer, status);
    }

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        soundCoin.safeTransfer(to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
