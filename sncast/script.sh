#!/bin/bash

# Declare Contracts
echo "Declaring contracts..."
sleep 2
OUTPUT1=$(sncast declare -c FossilClient --fee-token eth)
FOSSIL_CLASS_HASH=$(echo "$OUTPUT1" | awk '/class_hash:/ {print $2}')
#echo "Fossil client clash hash: $FOSSIL_CLASS_HASH"

sleep 2
OUTPUT2=$(sncast declare -c OptionRound --fee-token eth)
OPTION_ROUND_CLASS_HASH=$(echo "$OUTPUT2" | awk '/class_hash:/ {print $2}')
#echo "Option round clash hash: $OPTION_ROUND_CLASS_HASH"

sleep 2
OUTPUT3=$(sncast declare -c Vault --fee-token eth)
VAULT_CLASS_HASH=$(echo "$OUTPUT3" | awk '/class_hash:/ {print $2}')
#echo "Vault clash hash: $VAULT_CLASS_HASH"

# Deploy contracts
echo "Deploying contracts..."
sleep 2
OUTPUT4=$(sncast deploy --fee-token eth --class-hash $FOSSIL_CLASS_HASH --constructor-calldata 0xdeadbeef)
FOSSIL_CONTRACT_ADDRESS=$(echo "$OUTPUT4" | awk '/contract_address:/ {print $2}')
#echo "Fossil client address: $FOSSIL_CONTRACT_ADDRESS"

sleep 2
OUTPUT5=$(sncast deploy --fee-token eth --class-hash $VAULT_CLASS_HASH --constructor-calldata $FOSSIL_CONTRACT_ADDRESS 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTION_ROUND_CLASS_HASH 5555 0)
VAULT_CONTRACT_ADDRESS=$(echo "$OUTPUT5" | awk '/contract_address:/ {print $2}')
echo "Vault address: $VAULT_CONTRACT_ADDRESS"

# Set pricing data for first round to start
echo "Fulfilling 1st round job request..."
sleep 2
OUTPUT6=$(sncast call --contract-address $VAULT_CONTRACT_ADDRESS --function get_request_to_start_first_round)
response_line=$(echo "$OUTPUT6" | grep 'response:')
contents=$(echo "$response_line" | sed 's/.*\[\(.*\)\].*/\1/')
contents=$(echo "$contents" | tr ',' ' ' | tr -s '[:space:]')
contents=$(echo "$contents" | sed 's/^ *//; s/ *$//')
CALLDATA1=$(echo "$contents" | sed 's/,\s*/ /g')
sleep 2
sncast invoke --contract-address $FOSSIL_CONTRACT_ADDRESS --function fossil_callback --calldata $CALLDATA1 0x6 0x02540be400 0x00 0x0d05 0x77359400 0x00 0x00 --fee-token eth
echo "Finished"

# Declare Argent contract
cd argent

sleep 2
echo "Decalring argent..."
OUTPUTA=$(sncast declare -c ArgentAccount --fee-token eth)
ARGENT_CLASS_HASH=$(echo "$OUTPUTA" | awk '/class_hash:/ {print $2}')
echo "Argent clash hash: $ARGENT_CLASS_HASH"
