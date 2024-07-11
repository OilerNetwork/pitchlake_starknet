#!/bin/bash

# Find available port using Python
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')

echo "Starting katana on port $PORT"
katana --chain-id SN_SEPOLIA --host 127.0.0.1 --port $PORT --accounts "1" --seed "1" &

while ! nc -z localhost $PORT; do   
  sleep 0.1 # wait for 1/10 of the second before check again
done

# Run your Node script
echo "Running scripts on port $PORT"
echo "Declaring all the contracts"
node ./scripts/declareContracts.js dev $PORT
echo "Declaration of all the contracts done"
echo "Deploying all the contracts"
node ./scripts/deployContracts.js dev $PORT
echo "Deployment of all the contracts done "
# STARKNET_NETWORK=katana poetry run python3 scripts/deploy_vault.py --port $PORT
