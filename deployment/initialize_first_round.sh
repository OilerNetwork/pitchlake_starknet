#!/bin/bash

# Ensure the script stops on the first error
set -e

echo
echo "================================"
echo "Initialize First Round for Vaults"
echo "================================"
echo

# Load configuration from JSON file
CONFIG_FILE="deployment_config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found"
    exit 1
fi

# Load vault addresses
if [ ! -f "vault_addresses.env" ]; then
    echo "ERROR: vault_addresses.env not found. Please run deploy_vaults.sh first"
    exit 1
fi
source vault_addresses.env

# Extract values from JSON
RPC=$(jq -r '.deployment.network.rpc' "$CONFIG_FILE")
DEPLOYER_ADDRESS=$(jq -r '.deployment.network.deployer_address' "$CONFIG_FILE")
DEPLOYER_PRIVATE_KEY=$(jq -r '.deployment.network.deployer_private_key' "$CONFIG_FILE")
FOSSIL_API_URL=$(jq -r '.first_round_initialization.fossil_api_url' "$CONFIG_FILE")
FOSSIL_API_KEY=$(jq -r '.first_round_initialization.fossil_api_key' "$CONFIG_FILE")

echo
echo "Configuration loaded from $CONFIG_FILE:"
echo "RPC: $RPC"
echo "DEPLOYER_ADDRESS: $DEPLOYER_ADDRESS"
echo "DEPLOYER_PRIVATE_KEY: ${DEPLOYER_PRIVATE_KEY:0:10}..."
echo "FOSSIL_API_KEY: ${FOSSIL_API_KEY:0:10}..."
echo "FOSSIL_API_URL: $FOSSIL_API_URL"
echo

# Check if all required values are set
if [ -z "$RPC" ] || [ -z "$DEPLOYER_ADDRESS" ] || [ -z "$DEPLOYER_PRIVATE_KEY" ] || 
   [ -z "$FOSSIL_API_URL" ] || [ -z "$FOSSIL_API_KEY" ]; then
    echo "ERROR - One or more required configuration values are missing."
    exit 1
fi

# Set Starknet environment variables
export STARKNET_ACCOUNT="deployer_account.json"
export STARKNET_PRIVATE_KEY=$DEPLOYER_PRIVATE_KEY
export STARKNET_RPC=$RPC

# Initialize each vault
# Get number of vault addresses from vault_addresses.env
VAULT_COUNT=$(grep -c "VAULT_ADDRESS_" vault_addresses.env)

for ((i=1; i<=$VAULT_COUNT; i++)); do
    VAULT_ADDRESS_VAR="VAULT_ADDRESS_$i"
    VAULT_ADDRESS=${!VAULT_ADDRESS_VAR}
    
    # Get round duration from vault contract
    ROUND_DURATION_HEX=$(starkli call $VAULT_ADDRESS get_round_duration | jq -r '.[0]')
    # Convert hex to decimal (strip 0x prefix if present)
    ROUND_DURATION=$((16#${ROUND_DURATION_HEX#0x}))
    
    # Calculate windows for each metric
    TWAP_CALCULATION_WINDOW_SECONDS=$ROUND_DURATION
    VOLATILITY_CALCULATION_WINDOW_SECONDS=$((ROUND_DURATION * 3))
    RESERVE_PRICE_CALCULATION_WINDOW_SECONDS=$((ROUND_DURATION * 3))
    
    echo
    echo "Vault $i Configuration:"
    echo "VAULT_ADDRESS: $VAULT_ADDRESS"
    echo "ROUND_DURATION: $ROUND_DURATION"
    echo "TWAP calculation window: $TWAP_CALCULATION_WINDOW_SECONDS seconds"
    echo "Volatility calculation window: $VOLATILITY_CALCULATION_WINDOW_SECONDS seconds"
    echo "Reserve price calculation window: $RESERVE_PRICE_CALCULATION_WINDOW_SECONDS seconds"
    echo

    # Get fossil client address from vault contract
    FOSSIL_CLIENT_ADDRESS=$(starkli call $VAULT_ADDRESS get_fossil_client_address | jq -r '.[0]')
    echo "Fossil Client Address: $FOSSIL_CLIENT_ADDRESS"

    # Get request to settle round
    REQUEST_DATA=$(starkli call $VAULT_ADDRESS get_request_to_start_first_round)
    echo "Settlement request data: $REQUEST_DATA"

    # Format request for Fossil API
    VAULT_ADDRESS=$(echo $REQUEST_DATA | jq -r '.[1]')
    TIMESTAMP_HEX=$(echo $REQUEST_DATA | jq -r '.[2]')
    IDENTIFIER=$(echo $REQUEST_DATA | jq -r '.[3]')
    # Convert hex timestamp to decimal (strip 0x and convert)
    TIMESTAMP=$((16#${TIMESTAMP_HEX#0x}))

    TWAP_FROM=$(($TIMESTAMP - $TWAP_CALCULATION_WINDOW_SECONDS))
    VOLATILITY_FROM=$(($TIMESTAMP - $VOLATILITY_CALCULATION_WINDOW_SECONDS))
    RESERVE_PRICE_FROM=$(($TIMESTAMP - $RESERVE_PRICE_CALCULATION_WINDOW_SECONDS))

    echo
    echo "Request Parameters:"
    echo
    echo "Current time: $(date -r $TIMESTAMP)"
    echo "TWAP from: $(date -r $TWAP_FROM)"
    echo "Volatility from: $(date -r $VOLATILITY_FROM)" 
    echo "Reserve price from: $(date -r $RESERVE_PRICE_FROM)"
    echo "Vault address: $VAULT_ADDRESS"
    echo "Timestamp: $TIMESTAMP"
    echo "Identifier: $IDENTIFIER"
    echo

    FOSSIL_RESPONSE=$(curl -X POST "$FOSSIL_API_URL/pricing_data" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $FOSSIL_API_KEY" \
        -d "{
            \"identifiers\":[\"$IDENTIFIER\"],
            \"params\": {
                \"twap\": [$TWAP_FROM, $TIMESTAMP], 
                \"volatility\": [$VOLATILITY_FROM, $TIMESTAMP],
                \"reserve_price\": [$RESERVE_PRICE_FROM, $TIMESTAMP]
            },
            \"client_info\": {
                \"client_address\": \"$FOSSIL_CLIENT_ADDRESS\",
                \"vault_address\": \"$VAULT_ADDRESS\",
                \"timestamp\": $TIMESTAMP
            }
        }")

    echo "Fossil response: $FOSSIL_RESPONSE"
    JOB_ID=$(echo $FOSSIL_RESPONSE | jq -r '.job_id')
    echo "Fossil job ID: $JOB_ID"

    # Poll Fossil status endpoint until request is fulfilled
    while true; do
        echo "Polling Fossil request status..."
        STATUS_RESPONSE=$(curl -s "$FOSSIL_API_URL/job_status/$JOB_ID")
        STATUS=$(echo $STATUS_RESPONSE | jq -r '.status')
        echo "Fossil status: $STATUS"
        
        if [ "$STATUS" = "Completed" ]; then
            echo "Request fulfilled by Fossil"
            break
        elif [ "$STATUS" = "Failed" ]; then
            echo "ERROR: Fossil request failed"
            echo "Response: $STATUS_RESPONSE"
            exit 1
        fi
        
        sleep 10
    done

    echo "Vault $i initialization complete"
    echo "----------------------------------------"
    echo
done

echo "All vaults initialized successfully!"