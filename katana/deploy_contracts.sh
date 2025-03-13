#!/bin/bash

# Ensure the script stops on the first error
set -e

# Load environment variables
source ./.env

# Declare the first contract
echo "Declaring pitch_lake_FossilClient contract..."
FOSSILCLIENT_HASH=$(starkli declare ../target/dev/pitch_lake_FossilClient.contract_class.json --compiler-version 2.8.5 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $FOSSILCLIENT_HASH"

# Deploy the first contract with salt
echo "Deploying pitch_lake_FossilClient contract..."
FOSSILCLIENT_ADDRESS=$(starkli deploy $FOSSILCLIENT_HASH 0xb3ff441a68610b30fd5e2abbf3a1548eb6ba6f3559f2862bf2dc757e5828ca --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Contract deployed at: $FOSSILCLIENT_ADDRESS"

# Declare the second contract
echo "Declaring pitch_lake_OptionRound contract..."
OPTIONROUND_HASH=$(starkli declare ../target/dev/pitch_lake_OptionRound.contract_class.json --compiler-version 2.8.5 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $OPTIONROUND_HASH"

# Declare the third contract
echo "Declaring pitch_lake_Vault contract..."
VAULT_HASH=$(starkli declare ../target/dev/pitch_lake_Vault.contract_class.json --compiler-version 2.8.5 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $VAULT_HASH"

# Deploy the third contract with additional parameters and salt
echo "Deploying pitch_lake_Vault contract..."
VAULT_ADDRESS=$(starkli deploy $VAULT_HASH $FOSSILCLIENT_ADDRESS 0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTIONROUND_HASH $VAULT_ALPHA $VAULT_STRIKE --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Contract deployed at: $VAULT_ADDRESS"

# Perform the first call to get the round address
echo "Calling get_round_address on Vault contract..."
ROUND_ADDRESS=$(starkli call $VAULT_ADDRESS get_round_address u256:1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Round address: $ROUND_ADDRESS"

# Perform the second call to get the deployment date
echo "Calling get_deployment_date on the round contract..."
DEPLOYMENT_DATE_HEX=$(starkli call $ROUND_ADDRESS get_deployment_date | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Deployment date (hex): $DEPLOYMENT_DATE_HEX"

# Convert the hex deployment date to integer
DEPLOYMENT_DATE_INT=$((DEPLOYMENT_DATE_HEX))
echo "Deployment date (integer): $DEPLOYMENT_DATE_INT"

echo "All contracts declared, deployed, and calls executed successfully."

# Execute the curl command with the retrieved values
echo "Executing curl command to post pricing data..."

curl -X POST http://localhost:3000/pricing_data \
	-H 'Content-Type: application/json' \
	-H 'x-api-key: b2ed9cdc-2dd0-4b81-8ed4-bcefbf29ddc1' \
	-d '{
    "identifiers": ["PITCH_LAKE_V1"],
    "params": {
      "twap": ['$((DEPLOYMENT_DATE_INT - 86400))', '$DEPLOYMENT_DATE_INT'],
      "max_returns": ['$((DEPLOYMENT_DATE_INT - 259200))', '$DEPLOYMENT_DATE_INT'],
      "reserve_price": ['$((DEPLOYMENT_DATE_INT - 259200))', '$DEPLOYMENT_DATE_INT']
    },
    "client_info": {
      "client_address": "'$FOSSILCLIENT_ADDRESS'",
      "vault_address": "'$VAULT_ADDRESS'",
      "timestamp": '$DEPLOYMENT_DATE_INT'
    }
  }' &

#curl -X POST http://localhost:3000/pricing_data \
#	-H 'Content-Type: application/json' \
#	-H 'x-api-key: b2ed9cdc-2dd0-4b81-8ed4-bcefbf29ddc1' \
#	-d '{
#    "identifiers": ["PITCH_LAKE_V1"],
#    "params": {
#      "twap": ['1730053616', '1730140016'],
#      "max_returns": ['1729880816', '1730140016'],
#      "reserve_price": ['1729880816', '1730140016']
#    },
#    "client_info": {
#      "client_address": "'0x5fa4f6b4a8ac48fa9eef00ea08eab32538bb40084cd39c5247fcfa62ee0b4e4'",
#      "vault_address": "'0x586b503f2c806ec2555dfd763ef3d2e05d9789c0147da1c47b5057d46bbc6cc'",
#      "timestamp": '1730140016'
#    }
#  }' &

echo "All contracts declared and deployed successfully."
