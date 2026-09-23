#!/usr/bin/env bash
set -e

# Load environment variables
if [ -f .env ]; then
  source .env
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
  echo "Error: ETHERSCAN_API_KEY is not set in .env"
  exit 1
fi

CHAIN_ID=8453
VERIFIER_URL="https://api.etherscan.io/v2/api?chainid=8453"

echo "=== Verifying MySound Contracts on Base (Chain ID: $CHAIN_ID) via Etherscan API V2 ==="

# 1. SoundCoin (No constructor arguments)
echo ""
echo "--> 1. Verifying SoundCoin at 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A \
  contracts/SoundCoin.sol:SoundCoin \
  --watch || true

# 2. RewardManager
echo ""
echo "--> 2. Verifying RewardManager at 0x49E28E1bad4Acb5d1c3692834152D5fE62Fd6853..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args $(cast abi-encode "constructor(address,uint256,uint256,address,address)" 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A 62500000000000000000000000 1000000000000000000 0x79c49aA5743B0f82098045bc8eB2f9AC1e0B6904 0x79c49aA5743B0f82098045bc8eB2f9AC1e0B6904) \
  0x49E28E1bad4Acb5d1c3692834152D5fE62Fd6853 \
  contracts/RewardManager.sol:RewardManager \
  --watch || true

# 3. MusicArtistVoting
echo ""
echo "--> 3. Verifying MusicArtistVoting at 0xa2E9c1b22b5896f3b735C67146b6634Aa66A4949..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args $(cast abi-encode "constructor(address)" 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A) \
  0xa2E9c1b22b5896f3b735C67146b6634Aa66A4949 \
  contracts/MusicArtistVoting.sol:MusicArtistVoting \
  --watch || true

# 4. vMSC (No constructor arguments)
echo ""
echo "--> 4. Verifying vMSC at 0xDD42B9660553daaCc995Fe7d8b009e675a7a8Baf..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  0xDD42B9660553daaCc995Fe7d8b009e675a7a8Baf \
  contracts/vMSC.sol:vMSC \
  --watch || true

# 5. MSCVesting
echo ""
echo "--> 5. Verifying MSCVesting at 0x2074a5585DB261225B1D10cF1f3ED9E68fE9D54e..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args $(cast abi-encode "constructor(address,address)" 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A 0xDD42B9660553daaCc995Fe7d8b009e675a7a8Baf) \
  0x2074a5585DB261225B1D10cF1f3ED9E68fE9D54e \
  contracts/MSCVesting.sol:MSCVesting \
  --watch || true

# 6. CouponManager
echo ""
echo "--> 6. Verifying CouponManager at 0xc522AaA3Fa9ad1552B5FB8da645728106E563b9a..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args $(cast abi-encode "constructor(address,address)" 0x68B6E389e6633EAcec71f9be20a4B044db2c5c1A 0x79c49aA5743B0f82098045bc8eB2f9AC1e0B6904) \
  0xc522AaA3Fa9ad1552B5FB8da645728106E563b9a \
  contracts/CouponManager.sol:CouponManager \
  --watch || true

# 7. Presale
echo ""
echo "--> 7. Verifying Presale at 0x369706792f86877c6B2bdB8F7bC9053850DA7ce5..."
forge verify-contract \
  --chain-id "$CHAIN_ID" \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args 00000000000000000000000068b6e389e6633eacec71f9be20a4b044db2c5c1a000000000000000000000000000000000000000000000000000000006ab1bbbd000000000000000000000000000000000000000000000000000000006ad941bd00000000000000000000000088a43bbdf9d098eec7bceda4e2494615dfd9bb9c000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000009a6395f8456a8cde8cafc3e67cd5cf918a42d4cc \
  0x369706792f86877c6B2bdB8F7bC9053850DA7ce5 \
  contracts/Presale.sol:Presale \
  --watch || true

echo ""
echo "=== All Contract Verifications Submitted ==="
