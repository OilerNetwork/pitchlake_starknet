# Declare Argent contract

# Check required environment variables
if [ -z "$STARKNET_ACCOUNT" ] || [ -z "$STARKNET_RPC" ] || [ -z "$STARKNET_PRIVATE_KEY" ]; then
    echo "Error: Required environment variables not set"
    echo "Please ensure STARKNET_ACCOUNT, STARKNET_RPC and STARKNET_PRIVATE_KEY are set"
    exit 1
fi

echo "Environment variables:"
echo "STARKNET_ACCOUNT: $STARKNET_ACCOUNT"
echo "STARKNET_RPC: $STARKNET_RPC" 
echo "STARKNET_PRIVATE_KEY: $STARKNET_PRIVATE_KEY"
echo

# Assign command line arguments to variables
ADDRESS=$1
SALT=$2
ARG1=$3

# Check if all required arguments are provided
if [ $# -ne 3 ]; then
    echo "Error: Did not provide all arguments"
    echo "Usage: $0 <ARGENT_WALLET_ADDRESS> <ARGENT_WALLET_SALT> <ARGENT_WALLET_CONSTRUCTOR_ARG1>"
    exit 1
fi

starkli account fetch $SIGNER_ADDRESS --output $STARKNET_ACCOUNT

# Deploy Argent wallet
ARGENT_HASH=$(starkli declare --watch argent_ArgentAccount.contract_class.json --compiler-version 2.8.2 | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)
echo "[Argent Wallet] Class hash declared: $ARGENT_HASH"

if starkli class-hash-at $ADDRESS; then
    echo "Argent wallet already deployed at $ADDRESS"
    exit 1
fi

DEPLOYED_ARGENT_ADDRESS=$(starkli deploy --watch $ARGENT_HASH 0 $ARG1 1 --salt $SALT --not-unique | grep -o '0x[a-fA-F0-9]\{64\}' | head -1)

echo "Expected wallet address: $ADDRESS"
echo "Deployed wallet address: $DEPLOYED_ARGENT_ADDRESS"

# Verify addresses match
if [ "$ADDRESS" != "$DEPLOYED_ARGENT_ADDRESS" ]; then
    echo "Error: Deployed address does not match expected address"
    exit 1
fi

# OUTPUT=$(starkli invoke --watch 0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 transfer $ADDRESS 10000 0)
# echo "Funded wallet $OUTPUT"