#!/bin/bash

# Build the contracts
echo "Building contracts..."
scarb build

# Declare FossilClient contract
OUTPUT1=$(sncast declare -c FossilClient --fee-token eth)
FOSSIL_CLASS_HASH=$(echo "$OUTPUT1" | awk '/class_hash:/ {print $2}')
echo "FossilClient ClashHash: $FOSSIL_CLASS_HASH"
# Declare OptionRound contract
OUTPUT2=$(sncast declare -c OptionRound --fee-token eth)
OPTION_ROUND_CLASS_HASH=$(echo "$OUTPUT2" | awk '/class_hash:/ {print $2}')
echo "OptionRound ClashHash: $OPTION_ROUND_CLASS_HASH"
# Declare Vault contract
OUTPUT3=$(sncast declare -c Vault --fee-token eth)
VAULT_CLASS_HASH=$(echo "$OUTPUT3" | awk '/class_hash:/ {print $2}')
echo "Vault ClashHash: $VAULT_CLASS_HASH"

# Deploy FossilClient contract
OUTPUT4=$(sncast deploy --fee-token eth --class-hash $FOSSIL_CLASS_HASH --constructor-calldata 0xdeadbeef)
FOSSIL_CONTRACT_ADDRESS=$(echo "$OUTPUT4" | awk '/contract_address:/ {print $2}')
echo "FossilClient Address: $FOSSIL_CONTRACT_ADDRESS"
# Deploy Vault contract
OUTPUT5=$(sncast deploy --fee-token eth --class-hash $VAULT_CLASS_HASH --constructor-calldata $FOSSIL_CONTRACT_ADDRESS 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTION_ROUND_CLASS_HASH 5555 0)
VAULT_CONTRACT_ADDRESS=$(echo "$OUTPUT5" | awk '/contract_address:/ {print $2}')
echo "Vault Address: $VAULT_CONTRACT_ADDRESS"

# Manually set 1st round Fossil data
echo "Fetching 1st round JobRequest..."
OUTPUT6=$(sncast call --contract-address $VAULT_CONTRACT_ADDRESS --function get_request_to_start_first_round)
response_line=$(echo "$OUTPUT6" | grep 'response:')
contents=$(echo "$response_line" | sed 's/.*\[\(.*\)\].*/\1/')
contents=$(echo "$contents" | tr ',' ' ' | tr -s '[:space:]')
contents=$(echo "$contents" | sed 's/^ *//; s/ *$//')
CALLDATA1=$(echo "$contents" | sed 's/,\s*/ /g')
echo "Setting Fossil data..."
sncast invoke --contract-address $FOSSIL_CONTRACT_ADDRESS --function fossil_callback --calldata $CALLDATA1 0x6 0x02540be400 0x00 0x0d05 0x77359400 0x00 0x00 --fee-token eth
echo "Finished"

# Now you can use the class_hash variable as needed
