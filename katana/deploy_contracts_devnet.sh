#!/bin/bash

# Ensure the script stops on the first error
set -e

echo
echo "============================"
echo "Deploy Pitchlake Contracts"
echo "============================"
echo

# Set compiler version
COMPILER_VERSION="2.8.2"

# Print environment variables
echo "Environment variables:"
echo "STARKNET_ACCOUNT: $STARKNET_ACCOUNT"
echo "STARKNET_PRIVATE_KEY: ${STARKNET_PRIVATE_KEY:0:10}..." # Only show first 10 characters for security
echo "STARKNET_RPC: $STARKNET_RPC"

# Check if environment variables exist
if [ -z "$STARKNET_ACCOUNT" ] || [ -z "$STARKNET_PRIVATE_KEY" ] || [ -z "$STARKNET_RPC" ]; then
	echo "Error: One or more required environment variables are missing."
	exit 1
fi

# Check if all required arguments are provided
if [ $# -ne 4 ]; then
	echo "Usage: $0 <SIGNER_ADDRESS> <FOSSIL_PROCESSOR_ADDRESS> <VAULT_ALPHA> <VAULT_STRIKE> <ROUND_TRANSITION_DURATION> <AUCTION_DURATION> <ROUND_DURATION>"
	exit 1
fi

# Assign command line arguments to variables
SIGNER_ADDRESS=$1
FOSSIL_PROCESSOR_ADDRESS=$2
VAULT_ALPHA=$3
VAULT_STRIKE=$4
ROUND_TRANSITION_DURATION=$5
AUCTION_DURATION=$6
ROUND_DURATION=$7

# Check if deployment_addresses.env exists
if [ -f "deployment_addresses.env" ]; then
	echo "Contracts already deployed"
	echo "Deployment addresses:"
	cat deployment_addresses.env
	echo "Exiting..."
	exit 0
fi

# Check if the account file already exists
if [ ! -f "$STARKNET_ACCOUNT" ]; then
	starkli account fetch $SIGNER_ADDRESS --output $STARKNET_ACCOUNT
else
	echo "Acount config already exists at path $STARKNET_ACCOUNT"
fi

# Declare and deploy the ETH contract
# sleep 2
# ETH_HASH=$(starkli declare ../target/dev/pitch_lake_Eth.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
# echo "[ETH] Class hash declared"

# sleep 2
# ETH_ADDRESS=$(starkli deploy $ETH_HASH 1000000000000000000000 0 $SIGNER_ADDRESS --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
# echo "[ETH] Contract deployed"

ETH_ADDRESS="0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7"

# Declare the first contract
sleep 2
FOSSILCLIENT_HASH=$(starkli declare ../target/dev/pitch_lake_FossilClient.contract_class.json --compiler-version $COMPILER_VERSION | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Fossil Client] Class hash declared"

# Deploy the first contract with salt and FOSSIL_PROCESSOR_ADDRESS
sleep 2
FOSSILCLIENT_ADDRESS=$(starkli deploy $FOSSILCLIENT_HASH $FOSSIL_PROCESSOR_ADDRESS --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Fossil Client] Contract deployed"

# Declare the second contract
sleep 2
OPTIONROUND_HASH=$(starkli declare ../target/dev/pitch_lake_OptionRound.contract_class.json --compiler-version $COMPILER_VERSION | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Option Round] Class hash declared"

# Declare the third contract
sleep 2
VAULT_HASH=$(starkli declare ../target/dev/pitch_lake_Vault.contract_class.json --compiler-version $COMPILER_VERSION | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Vault] Class hash declared"

# Deploy the third contract with additional parameters and salt
sleep 2
VAULT_ADDRESS=$(starkli deploy $VAULT_HASH $FOSSILCLIENT_ADDRESS $ETH_ADDRESS $OPTIONROUND_HASH $VAULT_ALPHA $VAULT_STRIKE $ROUND_TRANSITION_DURATION $AUCTION_DURATION $ROUND_DURATION --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Vault] Contract deployed"

# Set pricing data for first round to start
echo "Fulfilling 1st round job request..."
sleep 2
OUTPUT6=$(starkli call $VAULT_ADDRESS get_request_to_start_first_round)
CALLDATA1=$(echo "$OUTPUT6" | tr -d '[]"' | tr ',' ' ' | tr -s '[:space:]' | sed 's/^ *//; s/ *$//')
echo $CALLDATA1
sleep 2
starkli invoke --watch $FOSSILCLIENT_ADDRESS fossil_callback $CALLDATA1 0x6 0x02540be400 0x00 0x0d05 0x77359400 0x00 0x00
echo "Finished"

{
	echo "ETH_ADDRESS=$ETH_ADDRESS"
	echo "FOSSILCLIENT_ADDRESS=$FOSSILCLIENT_ADDRESS"
	echo "VAULT_ADDRESS=$VAULT_ADDRESS"
} >deployment_addresses.env

echo "Deployment addresses"
cat deployment_addresses.env
