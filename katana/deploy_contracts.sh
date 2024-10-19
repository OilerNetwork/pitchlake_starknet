#!/bin/bash

# Ensure the script stops on the first error
set -e

# Declare the first contract
echo "Declaring pitch_lake_FossilClient contract..."
FOSSILCLIENT_HASH=$(starkli declare ../target/dev/pitch_lake_FossilClient.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Class hash declared: $FOSSILCLIENT_HASH"

# Deploy the first contract with salt
echo "Deploying pitch_lake_FossilClient contract..."
FOSSILCLIENT_ADDRESS=$(starkli deploy $FOSSILCLIENT_HASH 0xb3ff441a68610b30fd5e2abbf3a1548eb6ba6f3559f2862bf2dc757e5828ca --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
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
VAULT_ADDRESS=$(starkli deploy $VAULT_HASH $FOSSILCLIENT_ADDRESS 0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 $OPTIONROUND_HASH 5555 0 --salt 1 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "Contract deployed at: $VAULT_ADDRESS"

echo "All contracts declared and deployed successfully."
