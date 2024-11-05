#!/bin/bash

cd argent
FOSSIL_PROCESSOR=$(grep '^FOSSIL_PROCESSOR=' .env | cut -d '=' -f2 | tr -d '"')
echo "Fossil processor address: $FOSSIL_PROCESSOR"
cd ../

# Declare Contracts
echo "Declaring contracts..."
#   sleep 2
#   OUTPUT1=$(sncast declare -c FossilClient --fee-token eth)
#   FOSSIL_CLASS_HASH=$(echo "$OUTPUT1" | awk '/class_hash:/ {print $2}')
FOSSIL_CLASS_HASH=0x0711b785a4c9741c731b01a7487e3aaaf73acb2d9da9f68704a06a39baa4f1b6
CONSTRUCTOR_CALLDATA=$(echo "$OUTPUT1" | awk '/constructor_calldata:/ {print $2}')
#echo "Fossil client clash hash: $FOSSIL_CLASS_HASH"

#   sleep 2
#   OUTPUT2=$(sncast declare -c OptionRound --fee-token eth)
#   OPTION_ROUND_CLASS_HASH=$(echo "$OUTPUT2" | awk '/class_hash:/ {print $2}')
OPTION_ROUND_CLASS_HASH=0x1125dca25aa13f10c7c929bef4ea39ff68672b2abc93cdce2f27c7c66ac0365

#   sleep 2
#   OUTPUT3=$(sncast declare -c Vault --fee-token eth)
#   VAULT_CLASS_HASH=$(echo "$OUTPUT3" | awk '/class_hash:/ {print $2}')
VAULT_CLASS_HASH=0x0740110b337e39f3c1099a89faf4fcac867442b21a81c490b98897f682cc7ae4

# Deploy contracts
echo "Deploying contracts..."
sleep 2
OUTPUT4=$(sncast deploy --fee-token eth --class-hash $FOSSIL_CLASS_HASH --constructor-calldata $FOSSIL_PROCESSOR)
FOSSIL_CONTRACT_ADDRESS=$(echo "$OUTPUT4" | awk '/contract_address:/ {print $2}')

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

### HERE IS WHERE WE CAN LOAD THE DEFAULT/FIRST VAULT INTO THE DB

# ...

### BELOW IS FOR USING ARGENT WALLETS ON DEVNET ###

# Declare Argent contract

sleep 2
echo "Declaring argent..."
cd argent
OUTPUTA=$(sncast declare -c ArgentAccount --fee-token eth)
ARGENT_CLASS_HASH=$(echo "$OUTPUTA" | awk '/class_hash:/ {print $2}')
echo "Argent clash hash: $ARGENT_CLASS_HASH"

# Deploy Argent contract
ADDRESS=$(grep '^ARGENT_WALLET_ADDRESS=' .env | cut -d '=' -f2 | tr -d '"')
SALT=$(grep '^ARGENT_WALLET_SALT=' .env | cut -d '=' -f2 | tr -d '"')
ARG1=$(grep '^ARGENT_WALLET_CONSTRUCTOR_ARG1=' .env | cut -d '=' -f2 | tr -d '"')

OUTPUTA2=$(sncast deploy --fee-token eth --class-hash $ARGENT_CLASS_HASH -s $SALT --constructor-calldata 0 $ARG1 1 -v v1)
DEPLOYED_WALLET_ADDRESS=$(echo "$OUTPUTA2" | awk '/contract_address:/ {print $2}')
echo "Expected wallet address: $ADDRESS"
echo "Deployed wallet address: $DEPLOYED_WALLET_ADDRESS"

# Fund the wallet
OUTPUTA3=$(sncast invoke --contract-address 0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 -f transfer -c $ADDRESS 1000000000000000000000 0 --fee-token eth)
echo "Funded wallet $OUTPUTA3"
