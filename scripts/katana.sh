#!/bin/bash

# Find available port using Python
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

echo "Starting katana on port $PORT"
output=$(katana --chain-id SN_SEPOLIA --host 127.0.0.1 --port $PORT --accounts "1" --seed "1" --json-log)&


while ! nc -z localhost $PORT; do   
  sleep 0.1 # wait for 1/10 of the second before check again
done
# Run your Node script
echo "Running main.js on port $output"
npx ts-node ./scripts/main.ts dev $PORT 

# STARKNET_NETWORK=katana poetry run python3 scripts/deploy_vault.py --port $PORT
