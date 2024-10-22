#!/bin/bash

# Ensure the script stops on the first error
set -e

# Fetch the user address from environment variables
if [ -z "$USER_ADDRESS" ]; then
    echo "Error: USER_ADDRESS environment variable is not set."
    exit 1
fi
echo "User address: $USER_ADDRESS"

# Fetch the FOSSIL_PROCESSOR_ADDRESS from environment variables
if [ -z "$FOSSIL_PROCESSOR_ADDRESS" ]; then
    echo "Error: FOSSIL_PROCESSOR_ADDRESS environment variable is not set."
    exit 1
fi
echo "Fossil Processor address: $FOSSIL_PROCESSOR_ADDRESS"

# Fetch the VAULT_ROUND_DURATION from environment variables
if [ -z "$VAULT_ROUND_DURATION" ]; then
    echo "Error: VAULT_ROUND_DURATION environment variable is not set."
    exit 1
fi
echo "Vault Round Duration: $VAULT_ROUND_DURATION"

# Declare the ETH contract
echo "Declaring pitch_lake_Eth contract..."
ETH_HASH=$(starkli declare ../target/dev/pitch_lake_Eth.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $ETH_HASH"

# Deploy the ETH contract
echo "Deploying pitch_lake_Eth contract..."
ETH_ADDRESS=$(starkli deploy $ETH_HASH 1000000000000000000000 $USER_ADDRESS --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "ETH contract deployed at: $ETH_ADDRESS"

# Declare the first contract
echo "Declaring pitch_lake_FossilClient contract..."
FOSSILCLIENT_HASH=$(starkli declare ../target/dev/pitch_lake_FossilClient.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $FOSSILCLIENT_HASH"

# Deploy the first contract with salt and FOSSIL_PROCESSOR_ADDRESS
echo "Deploying pitch_lake_FossilClient contract..."
FOSSILCLIENT_ADDRESS=$(starkli deploy $FOSSILCLIENT_HASH $FOSSIL_PROCESSOR_ADDRESS --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Contract deployed at: $FOSSILCLIENT_ADDRESS"

# Declare the second contract
echo "Declaring pitch_lake_OptionRound contract..."
OPTIONROUND_HASH=$(starkli declare ../target/dev/pitch_lake_OptionRound.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $OPTIONROUND_HASH"

# Declare the third contract
echo "Declaring pitch_lake_Vault contract..."
VAULT_HASH=$(starkli declare ../target/dev/pitch_lake_Vault.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $VAULT_HASH"

# Deploy the third contract with additional parameters and salt
echo "Deploying pitch_lake_Vault contract..."
VAULT_ADDRESS=$(starkli deploy $VAULT_HASH $FOSSILCLIENT_ADDRESS $ETH_ADDRESS $OPTIONROUND_HASH $VAULT_ROUND_DURATION 0 --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Contract deployed at: $VAULT_ADDRESS"

echo "All contracts declared and deployed successfully."
