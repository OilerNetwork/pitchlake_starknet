#!/bin/bash

# Ensure the script stops on the first error
set -e

echo
echo "=========================="
echo "Deploy Pitchlake Vaults"
echo "=========================="
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

echo
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

# Declare contracts
OPTIONROUND_HASH=$(starkli declare ../target/dev/pitch_lake_OptionRound.contract_class.json --compiler-version $COMPILER_VERSION --watch | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Option Round] Class hash declared: $OPTIONROUND_HASH"

VAULT_HASH=$(starkli declare ../target/dev/pitch_lake_Vault.contract_class.json --compiler-version $COMPILER_VERSION --watch | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Vault] Class hash declared: $VAULT_HASH"

# Deploy each Vault instance
VAULT_COUNT=$(jq -r '.deployment.contracts.Vault.constructor_args | length' "$CONFIG_FILE")
declare -a VAULT_ADDRESSES=()

for ((i = 0; i < $VAULT_COUNT; i++)); do
	echo "Deploying Vault $((i + 1))..."

	# Get constructor args for this instance
	ETH_ADDRESS=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].eth_address" "$CONFIG_FILE")
	FOSSIL_CLIENT_ADDRESS=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].fossil_client_address" "$CONFIG_FILE")
	ALPHA=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].alpha" "$CONFIG_FILE")
	STRIKE=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].strike" "$CONFIG_FILE")
	MINIMUM_CAP_LEVEL=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].minimum_cap_level" "$CONFIG_FILE")
	ROUND_TRANSITION_DURATION=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].round_transition_duration" "$CONFIG_FILE")
	AUCTION_DURATION=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].auction_duration" "$CONFIG_FILE")
	ROUND_DURATION=$(jq -r ".deployment.contracts.Vault.constructor_args[$i].round_duration" "$CONFIG_FILE")

	echo
	echo "Constructor Arguments:"
	echo "ETH_ADDRESS: $ETH_ADDRESS"
	echo "FOSSIL_CLIENT_ADDRESS: $FOSSIL_CLIENT_ADDRESS"
	echo "ALPHA: $ALPHA"
	echo "STRIKE: $STRIKE"
	echo "MINIMUM_CAP_LEVEL: $MINIMUM_CAP_LEVEL"
	echo "ROUND_TRANSITION_DURATION: $ROUND_TRANSITION_DURATION"
	echo "AUCTION_DURATION: $AUCTION_DURATION"
	echo "ROUND_DURATION: $ROUND_DURATION"
	echo

	# Deploy Vault
	ADDRESS=$(starkli deploy $VAULT_HASH $FOSSIL_CLIENT_ADDRESS $ETH_ADDRESS $OPTIONROUND_HASH $ALPHA $STRIKE $MINIMUM_CAP_LEVEL $ROUND_TRANSITION_DURATION $AUCTION_DURATION $ROUND_DURATION --watch | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
	VAULT_ADDRESSES+=($ADDRESS)
	echo "[Vault $((i + 1))] Contract deployed at: $ADDRESS"
done

# Save deployment addresses to file
echo "# Vault Addresses" >vault_addresses.env
for ((i = 0; i < ${#VAULT_ADDRESSES[@]}; i++)); do
	echo "VAULT_ADDRESS_$((i + 1))=${VAULT_ADDRESSES[$i]}" >>vault_addresses.env
done

echo
echo "Deployment addresses saved to vault_addresses.env:"
cat vault_addresses.env
