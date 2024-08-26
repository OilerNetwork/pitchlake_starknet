#!/bin/bash

# Find available port using Python

katana --chain-id SN_SEPOLIA --host 127.0.0.1 --port 5050 --accounts "25" --seed "1" -b 2000 --dev &
# while ! nc -z localhost $PORT; do
#   sleep 0.1 # wait for 1/10 of the second before check again
# done
cd scripts
./generate_abi.sh

node --loader ts-node/esm smokeTests.ts dev 5050
lsof -i tcp:5050 | awk 'NR!=1 {print $2}' | xargs kill

# echo "Running smokeTesting.js on port $PORT"
# node ./scripts/intergration_test/smokeTesting.js dev $PORT

# STARKNET_NETWORK=katana poetry run python3 scripts/deploy_vault.py --port $PORT
