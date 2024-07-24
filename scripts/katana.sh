#!/bin/bash

# Find available port using Python
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

echo "Starting katana on port $PORT"
katana --chain-id SN_SEPOLIA --host 127.0.0.1 --port 5050 --accounts "25" --seed "1" -b 2000 --dev &
# while ! nc -z localhost $PORT; do   
#   sleep 0.1 # wait for 1/10 of the second before check again
# done

./generate_abi.sh

# Run your Node script
echo "Running main.js on port $PORT"
cd scripts
node --loader ts-node/esm main.ts dev 5050

# echo "Running smokeTesting.js on port $PORT"
# node ./scripts/intergration_test/smokeTesting.js dev $PORT

# STARKNET_NETWORK=katana poetry run python3 scripts/deploy_vault.py --port $PORT
