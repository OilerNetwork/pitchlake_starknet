#!/bin/bash

# Ensure the script stops on the first error
set -e

# Check if deployment_addresses.env exists
if [ -f "deployment_addresses.env" ]; then
    echo "deployment_addresses.env already exists. Exiting..."
    exit 0
fi


# Print environment variables
echo "Environment variables:"
echo "STARKNET_ACCOUNT: $STARKNET_ACCOUNT"
echo "STARKNET_PRIVATE_KEY: ${STARKNET_PRIVATE_KEY:0:10}..." # Only show first 10 characters for security
echo "STARKNET_RPC: $STARKNET_RPC"

# Check if all required arguments are provided
if [ $# -ne 3 ]; then
    echo "Usage: $0 <ETH_RECEIVER_ADDRESS> <FOSSIL_PROCESSOR_ADDRESS> <VAULT_ROUND_DURATION>"
    exit 1
fi

# Assign command line arguments to variables
ETH_RECEIVER_ADDRESS=$1
FOSSIL_PROCESSOR_ADDRESS=$2
VAULT_ROUND_DURATION=$3

# Validate the arguments
if [ -z "$ETH_RECEIVER_ADDRESS" ]; then
    echo "Error: ETH_RECEIVER_ADDRESS is not provided."
    exit 1
fi
echo "ETH receiver address: $ETH_RECEIVER_ADDRESS"

if [ -z "$FOSSIL_PROCESSOR_ADDRESS" ]; then
    echo "Error: FOSSIL_PROCESSOR_ADDRESS is not provided."
    exit 1
fi
echo "Fossil Processor address: $FOSSIL_PROCESSOR_ADDRESS"

if [ -z "$VAULT_ROUND_DURATION" ]; then
    echo "Error: VAULT_ROUND_DURATION is not provided."
    exit 1
fi
echo "Vault Round Duration: $VAULT_ROUND_DURATION"

# Declare the ETH contract
sleep 2
ETH_HASH=$(starkli declare ../target/dev/pitch_lake_Eth.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[ETH] Class hash declared"

# Deploy the ETH contract
sleep 2
ETH_ADDRESS=$(starkli deploy $ETH_HASH 1000000000000000000000 0 $ETH_RECEIVER_ADDRESS --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[ETH] Contract deployed"

# Declare the first contract
sleep 2
FOSSILCLIENT_HASH=$(starkli declare ../target/dev/pitch_lake_FossilClient.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Fossil Client] Class hash declared"

# Deploy the first contract with salt and FOSSIL_PROCESSOR_ADDRESS
sleep 2
FOSSILCLIENT_ADDRESS=$(starkli deploy $FOSSILCLIENT_HASH $FOSSIL_PROCESSOR_ADDRESS --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Fossil Client] Contract deployed"

# Declare the second contract
sleep 2
OPTIONROUND_HASH=$(starkli declare ../target/dev/pitch_lake_OptionRound.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Option Round] Class hash declared"

# Declare the third contract
sleep 2
VAULT_HASH=$(starkli declare ../target/dev/pitch_lake_Vault.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Vault] Class hash declared"

# Deploy the third contract with additional parameters and salt
sleep 2
VAULT_ADDRESS=$(starkli deploy $VAULT_HASH $FOSSILCLIENT_ADDRESS $ETH_ADDRESS $OPTIONROUND_HASH $VAULT_ROUND_DURATION 0 --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Vault] Contract deployed"

{
    echo "ETH_ADDRESS=$ETH_ADDRESS"
    echo "FOSSILCLIENT_ADDRESS=$FOSSILCLIENT_ADDRESS"
    echo "VAULT_ADDRESS=$VAULT_ADDRESS"
} > deployment_addresses.env

echo "Deployment addresses"
cat deployment_addresses.env
