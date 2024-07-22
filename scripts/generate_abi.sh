#!/bin/bash

# Define contracts and their file paths
# Add contracts here as "contract_name:abi_name"
contracts=(
    "OptionRound:optionRound"
    "Vault:vault"
    "MarketAggregator:marketAggregator"
)

echo "Running scarb build..."
cd .. && scarb build && cd scripts

# Generate ABIs
for contract in "${contracts[@]}"; do
    IFS=':' read -r contract_name abi_name <<< "$contract"
    json_file="../target/dev/pitch_lake_starknet_${contract_name}.contract_class.json"
    abi_file="./abi/${abi_name}.ts"
    
    npx abi-wan-kanabi --input "$json_file" --output "$abi_file"
done
