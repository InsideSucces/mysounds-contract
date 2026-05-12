// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {CouponManager} from "../contracts/CouponManager.sol";
import {SoundCoin} from "../contracts/SoundCoin.sol";

contract CouponManagerTest is Test {
    CouponManager public manager;
    SoundCoin public coin;

    uint256 public signerPrivateKey = 0x1234;
    address public signer;
    address public user = address(0xABCD);

    bytes32 private constant COUPON_TYPEHASH = keccak256(
        "Coupon(address user,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        signer = vm.addr(signerPrivateKey);
        coin = new SoundCoin();
        manager = new CouponManager(address(coin), signer);
        
        // Fund the manager with tokens
        coin.transfer(address(manager), 1000 * 10**18);
    }

    function test_RedeemSuccessful() public {
        uint256 amount = 100 * 10**18;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 100;

        bytes32 structHash = keccak256(
            abi.encode(COUPON_TYPEHASH, user, amount, nonce, deadline)
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        manager.redeem(amount, nonce, deadline, signature);

        assertEq(coin.balanceOf(user), amount);
        assertEq(manager.nonces(user), 1);
    }

    function test_RevertIfInsufficientBalance() public {
        uint256 amount = 2000 * 10**18; // More than manager has
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 100;

        bytes32 structHash = keccak256(
            abi.encode(COUPON_TYPEHASH, user, amount, nonce, deadline)
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(CouponManager.InsufficientContractBalance.selector);
        manager.redeem(amount, nonce, deadline, signature);
    }

    function test_EmergencyWithdraw() public {
        uint256 amount = 500 * 10**18;
        address recipient = address(0x999);
        
        manager.emergencyWithdraw(recipient, amount);
        
        assertEq(coin.balanceOf(recipient), amount);
    }

    function test_RevertIfExpired() public {
        uint256 amount = 100 * 10**18;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp - 1;

        bytes memory signature = "";

        vm.prank(user);
        vm.expectRevert(CouponManager.DeadlineExpired.selector);
        manager.redeem(amount, nonce, deadline, signature);
    }

    function test_RevertIfInvalidNonce() public {
        uint256 amount = 100 * 10**18;
        uint256 nonce = 1; // Correct should be 0
        uint256 deadline = block.timestamp + 100;

        bytes memory signature = "";

        vm.prank(user);
        vm.expectRevert(CouponManager.InvalidSignature.selector);
        manager.redeem(amount, nonce, deadline, signature);
    }

    function test_RevertIfInvalidSigner() public {
        uint256 amount = 100 * 10**18;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 100;

        uint256 wrongPrivateKey = 0x5678;
        
        bytes32 structHash = keccak256(
            abi.encode(COUPON_TYPEHASH, user, amount, nonce, deadline)
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(CouponManager.UnauthorizedSigner.selector);
        manager.redeem(amount, nonce, deadline, signature);
    }

    function test_RevertIfReused() public {
        uint256 amount = 100 * 10**18;
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 100;

        bytes32 structHash = keccak256(
            abi.encode(COUPON_TYPEHASH, user, amount, nonce, deadline)
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(user);
        manager.redeem(amount, nonce, deadline, signature);
        
        vm.expectRevert(CouponManager.InvalidSignature.selector);
        manager.redeem(amount, nonce, deadline, signature);
        vm.stopPrank();
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("CouponManager"),
                keccak256("1"),
                block.chainid,
                address(manager)
            )
        );
    }
}
