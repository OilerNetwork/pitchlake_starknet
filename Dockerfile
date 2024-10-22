# Use Ubuntu as the base image
FROM ubuntu:22.04

# Set environment variables
ENV SCARB_VERSION=2.8.4
ENV STARKLI_VERSION=0.2.8
ENV RUST_VERSION=1.75.0

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*


# Install Scarb
## TODO: Find out why this fails without || true
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v $SCARB_VERSION
ENV PATH="$PATH:/root/.local/bin"

# Verify Scarb installation
RUN which scarb && scarb --version

# Install Starkli
RUN curl https://get.starkli.sh | sh
ENV PATH="$PATH:/root/.starkli/bin"

# Verify Starkli installation
RUN starkli --version

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Build contracts
RUN scarb build

# Hardcoded account details
ENV SIGNER_PRIVATE_KEY="0x2bff1b26236b72d8a930be1dfbee09f79a536a49482a4c8b8f1030e2ab3bf1b"
ENV SIGNER_ADDRESS="0x101"
ENV STARKNET_RPC=http://localhost:6060
ENV STARKNET_ACCOUNT=~/.starkli-wallets/deployer/account.json
ENV STARKNET_PRIVATE_KEY=$SIGNER_PRIVATE_KEY

# Create keystore using starkli
# RUN echo "$ACCOUNT_PRIVATE_KEY" > private_key.txt && \
#     starkli signer keystore from-key private_key.txt ~/.starkli-wallets/deployer/keystore.json && \
#     rm private_key.txt

# Create account file using starkli
RUN starkli account fetch "$SIGNER_ADDRESS" --output ~/.starkli-wallets/deployer/account.json

# Send STRK tokens to the user
RUN starkli invoke 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d transfer $SIGNER_ADDRESS 1000000000000000000 --account ~/.starkli-wallets/deployer/account.json --keystore ~/.starkli-wallets/deployer/account.key

# Deploy contracts
RUN source .env && \
    ./katana/deploy_contracts_devnet.sh

# Save contract addresses
RUN echo "ETH_ADDRESS=$ETH_ADDRESS" >> /app/contract_addresses.env && \
    echo "FOSSILCLIENT_ADDRESS=$FOSSILCLIENT_ADDRESS" >> /app/contract_addresses.env && \
    echo "OPTIONROUND_HASH=$OPTIONROUND_HASH" >> /app/contract_addresses.env && \
    echo "VAULT_ADDRESS=$VAULT_ADDRESS" >> /app/contract_addresses.env

# Set the default command
CMD ["cat", "/app/contract_addresses.env"]
