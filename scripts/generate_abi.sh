#!/bin/bash

# Script for generating the ABI files from the contract JSON files
OPTION_ROUND_JSON="../target/dev/pitch_lake_starknet_OptionRound.contract_class.json"
VAULT_JSON="../target/dev/pitch_lake_starknet_Vault.contract_class.json"

if [ ! -f "$OPTION_ROUND_JSON" ] || [ ! -f "$VAULT_JSON" ]; then
    echo "One or both JSON files are missing. Executing 'scarb build'..."
    cd ..
    scarb build
    cd scripts
fi

npx abi-wan-kanabi --input "$OPTION_ROUND_JSON" --output ./abi/optionRound.ts && \
npx abi-wan-kanabi --input "$VAULT_JSON" --output ./abi/vault.ts