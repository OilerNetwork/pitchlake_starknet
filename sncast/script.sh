#!/bin/bash

# Declare Contracts
echo "Declaring contracts..."

OUTPUT1=$(sncast declare -c FossilClient --fee-token eth)
FOSSIL_CLASS_HASH=$(echo "$OUTPUT1" | awk '/class_hash:/ {print $2}')
#FOSSIL_CLASS_HASH=0x711b785a4c9741c731b01a7487e3aaaf73acb2d9da9f68704a06a39baa4f1b6
echo "Fossil class hash: $FOSSIL_CLASS_HASH"

OUTPUT2=$(sncast declare -c OptionRound --fee-token eth)
OPTION_ROUND_CLASS_HASH=$(echo "$OUTPUT2" | awk '/class_hash:/ {print $2}')
#OPTION_ROUND_CLASS_HASH=0x378211be15fa10df3a5d70e92bfd1bca0752a0196ea0bfcd5b3131491a1305
echo "Option round class hash: $OPTION_ROUND_CLASS_HASH"

OUTPUT3=$(sncast declare -c Vault --fee-token eth)
VAULT_CLASS_HASH=$(echo "$OUTPUT3" | awk '/class_hash:/ {print $2}')
#VAULT_CLASS_HASH=0x51653f39500cfb021b791c3bf9f2b2f1e294a862c8824be21f3b44a0ee40449
echo "Vault class hash: $VAULT_CLASS_HASH"

# Deploy contracts
echo "Deploying contracts..."

FOSSIL_PROCESSOR=$(grep '^FOSSIL_PROCESSOR=' .env | cut -d '=' -f2 | tr -d '"')
echo "Fossil processor address: $FOSSIL_PROCESSOR"

OUTPUT4=$(sncast deploy --fee-token eth --class-hash $FOSSIL_CLASS_HASH --constructor-calldata $FOSSIL_PROCESSOR)
FOSSIL_CONTRACT_ADDRESS=$(echo "$OUTPUT4" | awk '/contract_address:/ {print $2}')
#FOSSIL_CONTRACT_ADDRESS=0x585da9e93abbaa19e67e11b863040248652623d2762930086c3fd2a3a754158
echo "Fossil Client address: $FOSSIL_CONTRACT_ADDRESS"

# 12 minute vault
ROUND_TRANSITION_DURATION1=180 # 3 min
AUCTION_DURATION1=180          # 3 min
ROUND_DURATION1=720            # 12 min
sleep 30
OUTPUT5=$(sncast deploy --fee-token eth --class-hash $VAULT_CLASS_HASH --constructor-calldata $FOSSIL_CONTRACT_ADDRESS 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTION_ROUND_CLASS_HASH 5555 0 $ROUND_TRANSITION_DURATION1 $AUCTION_DURATION1 $ROUND_DURATION1)
VAULT_CONTRACT_ADDRESS=$(echo "$OUTPUT5" | awk '/contract_address:/ {print $2}')
echo "(1 minute) Vault address: $VAULT_CONTRACT_ADDRESS"
# 3 hour vault
ROUND_TRANSITION_DURATION2=1800 # 30 min
AUCTION_DURATION2=1800          # 30 min
ROUND_DURATION2=10800           # 3 hour
sleep 30
OUTPUT5_2=$(sncast deploy --fee-token eth --class-hash $VAULT_CLASS_HASH --constructor-calldata $FOSSIL_CONTRACT_ADDRESS 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTION_ROUND_CLASS_HASH 5555 0 $ROUND_TRANSITION_DURATION2 $AUCTION_DURATION2 $ROUND_DURATION2)
VAULT_CONTRACT_ADDRESS2=$(echo "$OUTPUT5_2" | awk '/contract_address:/ {print $2}')
echo "(15 minute) Vault address: $VAULT_CONTRACT_ADDRESS2"
1 month vault
sleep 30
ROUND_TRANSITION_DURATION3=10800 # 3 hours
AUCTION_DURATION3=10800          # 3 hours
ROUND_DURATION3=2592000          # 1 month
sleep 30
OUTPUT5_3=$(sncast deploy --fee-token eth --class-hash $VAULT_CLASS_HASH --constructor-calldata $FOSSIL_CONTRACT_ADDRESS 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTION_ROUND_CLASS_HASH 5555 0 $ROUND_TRANSITION_DURATION3 $AUCTION_DURATION3 $ROUND_DURATION3)
VAULT_CONTRACT_ADDRESS3=$(echo "$OUTPUT5_3" | awk '/contract_address:/ {print $2}')
echo "(30 day) Vault address: $VAULT_CONTRACT_ADDRESS3"
echo "Vaults: [$VAULT_CONTRACT_ADDRESS,$VAULT_CONTRACT_ADDRESS2,$VAULT_CONTRACT_ADDRESS3]"

# Set pricing data for first round to start
echo "Fulfilling 1st job request..."
sleep 10
OUTPUT6=$(sncast call --contract-address $VAULT_CONTRACT_ADDRESS --function get_request_to_start_first_round)
response_line=$(echo "$OUTPUT6" | grep 'response:')
contents=$(echo "$response_line" | sed 's/.*\[\(.*\)\].*/\1/')
contents=$(echo "$contents" | tr ',' ' ' | tr -s '[:space:]')
contents=$(echo "$contents" | sed 's/^ *//; s/ *$//')
CALLDATA1=$(echo "$contents" | sed 's/,\s*/ /g')
sleep 10
sncast invoke --contract-address $FOSSIL_CONTRACT_ADDRESS --function fossil_callback --calldata $CALLDATA1 0x6 0x02540be400 0x00 0x0d05 0x77359400 0x00 0x00 --fee-token eth

echo "Fulfilling 2nd job request..."
sleep 10
OUTPUT6_2=$(sncast call --contract-address $VAULT_CONTRACT_ADDRESS2 --function get_request_to_start_first_round)
response_line=$(echo "$OUTPUT6_2" | grep 'response:')
contents=$(echo "$response_line" | sed 's/.*\[\(.*\)\].*/\1/')
contents=$(echo "$contents" | tr ',' ' ' | tr -s '[:space:]')
contents=$(echo "$contents" | sed 's/^ *//; s/ *$//')
CALLDATA2=$(echo "$contents" | sed 's/,\s*/ /g')
sleep 10
sncast invoke --contract-address $FOSSIL_CONTRACT_ADDRESS --function fossil_callback --calldata $CALLDATA2 0x6 0x02540be400 0x00 0x0d05 0x77359400 0x00 0x00 --fee-token eth

echo "Fulfilling 3rd job request..."
sleep 10
OUTPUT6_3=$(sncast call --contract-address $VAULT_CONTRACT_ADDRESS3 --function get_request_to_start_first_round)
response_line=$(echo "$OUTPUT6_3" | grep 'response:')
contents=$(echo "$response_line" | sed 's/.*\[\(.*\)\].*/\1/')
contents=$(echo "$contents" | tr ',' ' ' | tr -s '[:space:]')
contents=$(echo "$contents" | sed 's/^ *//; s/ *$//')
CALLDATA3=$(echo "$contents" | sed 's/,\s*/ /g')
sleep 10
sncast invoke --contract-address $FOSSIL_CONTRACT_ADDRESS --function fossil_callback --calldata $CALLDATA3 0x6 0x02540be400 0x00 0x0d05 0x77359400 0x00 0x00 --fee-token eth
echo "Finished"

### - HERE IS WHERE WE COULD LOAD THE VAULT ADDRESSES INTO THE DB

### - Below is for deploying your argent account to devnet

# Declare Argent contract
sleep 1
echo "Declaring argent..."
cd argent
OUTPUTA=$(sncast declare -c ArgentAccount --fee-token eth)
ARGENT_CLASS_HASH=$(echo "$OUTPUTA" | awk '/class_hash:/ {print $2}')
echo "Argent clash hash: $ARGENT_CLASS_HASH"

# Deploy Argent contract (your wallet)
sleep 1
ADDRESS=$(grep '^ARGENT_WALLET_ADDRESS=' .env | cut -d '=' -f2 | tr -d '"')
SALT=$(grep '^ARGENT_WALLET_SALT=' .env | cut -d '=' -f2 | tr -d '"')
ARG1=$(grep '^ARGENT_WALLET_CONSTRUCTOR_ARG1=' .env | cut -d '=' -f2 | tr -d '"')
OUTPUTA2=$(sncast deploy --fee-token eth --class-hash $ARGENT_CLASS_HASH -s $SALT --constructor-calldata 0 $ARG1 1 -v v1)
DEPLOYED_WALLET_ADDRESS=$(echo "$OUTPUTA2" | awk '/contract_address:/ {print $2}')
echo "Expected wallet address: $ADDRESS"
echo "Deployed wallet address: $DEPLOYED_WALLET_ADDRESS"

# Fund the wallet
sleep 1
OUTPUTA3=$(sncast invoke --contract-address 0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 -f transfer -c $ADDRESS 1000000000000000000000 0 --fee-token eth)
echo "Funded wallet $OUTPUTA3"
