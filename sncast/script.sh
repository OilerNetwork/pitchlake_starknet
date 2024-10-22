#!/bin/bash

# Build the contracts
echo "Building contracts..."
scarb build

# Declare FossilClient contract
OUTPUT1=$(sncast declare -c FossilClient --fee-token eth)
FOSSIL_CLASS_HASH=$(echo "$OUTPUT1" | awk '/class_hash:/ {print $2}')
# Declare OptionRound contract
OUTPUT2=$(sncast declare -c OptionRound --fee-token eth)
OPTION_ROUND_CLASS_HASH=$(echo "$OUTPUT2" | awk '/class_hash:/ {print $2}')
# Declare Vault contract
OUTPUT3=$(sncast declare -c Vault --fee-token eth)
VAULT_CLASS_HASH=$(echo "$OUTPUT3" | awk '/class_hash:/ {print $2}')

# Deploy FossilClient contract
OUTPUT4=$(sncast deploy --fee-token eth --class-hash $FOSSIL_CLASS_HASH --constructor-calldata 0xdeadbeef)
echo "Raw deployment ouput": $OUTPUT4
FOSSIL_CONTRACT_ADDRESS=$(echo "$OUTPUT4" | awk '/contract_address:/ {print $2}')
# Deploy Vault contract
OUTPUT5=$(sncast deploy --fee-token eth --class-hash $VAULT_CLASS_HASH --constructor-calldata $FOSSIL_CONTRACT_ADDRESS 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTION_ROUND_CLASS_HASH 5555 0)
VAULT_CONTRACT_ADDRESS=$(echo "$OUTPUT5" | awk '/contract_address:/ {print $2}')

# Now you can use the class_hash variable as needed
echo "Class Hashes:"
echo "FossilClient: $FOSSIL_CLASS_HASH"
echo "OptionRound: $OPTION_ROUND_CLASS_HASH"
echo "Vault: $VAULT_CLASS_HASH"
echo "Contract Addresses:"
echo "FossilClient: $FOSSIL_CONTRACT_ADDRESS"
echo "Vault: $VAULT_CONTRACT_ADDRESS"
