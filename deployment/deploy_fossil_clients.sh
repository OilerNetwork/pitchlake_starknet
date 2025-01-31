#!/bin/bash

# Ensure the script stops on the first error
set -e

echo
echo "================================"
echo "Deploy Pitchlake Fossil Clients"
echo "================================"
echo

# Load configuration from JSON file
CONFIG_FILE="deployment_config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found"
    exit 1
fi

# Extract deployment values from JSON
COMPILER_VERSION=$(jq -r '.deployment.compiler_version' "$CONFIG_FILE")
RPC=$(jq -r '.deployment.network.rpc' "$CONFIG_FILE")
DEPLOYER_ADDRESS=$(jq -r '.deployment.network.deployer_address' "$CONFIG_FILE")
DEPLOYER_PRIVATE_KEY=$(jq -r '.deployment.network.deployer_private_key' "$CONFIG_FILE")

echo "Configuration loaded from $CONFIG_FILE:"
echo "COMPILER_VERSION: $COMPILER_VERSION"
echo "RPC: $RPC"
echo "DEPLOYER_ADDRESS: $DEPLOYER_ADDRESS"
echo "DEPLOYER_PRIVATE_KEY: ${DEPLOYER_PRIVATE_KEY:0:10}..."
echo

# Check if all required values are set
if [ -z "$COMPILER_VERSION" ] || [ -z "$RPC" ] || [ -z "$DEPLOYER_ADDRESS" ] || [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "ERROR - One or more required configuration values are missing."
    exit 1
fi

# Setup starknet environment
export STARKNET_ACCOUNT="deployer_account.json"
export STARKNET_PRIVATE_KEY=$DEPLOYER_PRIVATE_KEY
export STARKNET_RPC=$RPC

# Check if the account file already exists
if [ ! -f "$STARKNET_ACCOUNT" ]; then
    starkli account fetch $DEPLOYER_ADDRESS --output $STARKNET_ACCOUNT
else
    echo "Account config already exists at path $STARKNET_ACCOUNT"
fi

# Declare FossilClient contract
FOSSILCLIENT_HASH=$(starkli declare ../target/dev/pitch_lake_FossilClient.contract_class.json --compiler-version $COMPILER_VERSION --watch | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Fossil Client] Class hash declared: $FOSSILCLIENT_HASH"

# Deploy each FossilClient instance
FOSSIL_CLIENT_COUNT=$(jq -r '.deployment.contracts.FossilClient.constructor_args | length' "$CONFIG_FILE")
declare -a FOSSIL_CLIENT_ADDRESSES=()

for ((i=0; i<$FOSSIL_CLIENT_COUNT; i++)); do
    echo "Deploying Fossil Client $((i+1))..."
    
    # Get constructor args for this instance
    FOSSIL_PROCESSOR_ADDRESS=$(jq -r ".deployment.contracts.FossilClient.constructor_args[$i].fossil_processor_address" "$CONFIG_FILE")
    
    echo
    echo "Constructor Arguments:"
    echo "FOSSIL_PROCESSOR_ADDRESS: $FOSSIL_PROCESSOR_ADDRESS"
    echo
    
    # Deploy FossilClient
    ADDRESS=$(starkli deploy $FOSSILCLIENT_HASH $FOSSIL_PROCESSOR_ADDRESS --watch | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
    FOSSIL_CLIENT_ADDRESSES+=($ADDRESS)
    echo "[Fossil Client $((i+1))] Contract deployed at: $ADDRESS"
done

# Save deployment addresses to file
echo "# Fossil Client Addresses" > fossil_client_addresses.env
for ((i=0; i<${#FOSSIL_CLIENT_ADDRESSES[@]}; i++)); do
    echo "FOSSIL_CLIENT_ADDRESS_$((i+1))=${FOSSIL_CLIENT_ADDRESSES[$i]}" >> fossil_client_addresses.env
done

echo
echo "Deployment addresses saved to fossil_client_addresses.env:"
cat fossil_client_addresses.env 