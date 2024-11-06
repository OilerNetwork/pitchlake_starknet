# Build stage
FROM ubuntu:22.04 AS builder
SHELL ["/bin/bash", "-c"]

# Set environment variables
ENV SCARB_VERSION=2.8.4
ENV STARKLI_VERSION=0.2.8

# Define build-time arguments
ARG SIGNER_PRIVATE_KEY
ARG DEVNET_RPC
ARG SIGNER_ADDRESS
ARG FOSSIL_PROCESSOR_ADDRESS
ARG VAULT_ROUND_DURATION

# Check if all required arguments are provided
RUN if [ -z "$SIGNER_PRIVATE_KEY" ] || \
       [ -z "$DEVNET_RPC" ] || \
       [ -z "$SIGNER_ADDRESS" ] || \
       [ -z "$FOSSIL_PROCESSOR_ADDRESS" ] || \
       [ -z "$VAULT_ROUND_DURATION" ]; then \
    echo "Error: All build arguments must be provided."; \
    exit 1; \
fi

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Scarb
ENV PATH="$PATH:/root/.local/bin"
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | bash -s -- -v $SCARB_VERSION

# Set working directory
WORKDIR /contracts

# Copy project files
COPY . .

# Build contracts
RUN scarb build

# Final stage
FROM ubuntu:22.04
SHELL ["/bin/bash", "-c"]

# Copy build artifacts from builder
COPY --from=builder /contracts/target /contracts/target

# Set environment variables
ENV STARKLI_VERSION=0.2.8

# Install necessary dependencies (minimal set)
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Starkli
ENV PATH="$PATH:/root/.starkli/bin"
RUN curl https://get.starkli.sh | bash
RUN starkliup

# Set Starkli environment variables
ENV STARKNET_ACCOUNT=/root/starkli_deployer_account.json
ENV STARKNET_PRIVATE_KEY=$SIGNER_PRIVATE_KEY
ENV STARKNET_RPC=$DEVNET_RPC

# Set working directory
WORKDIR /contracts

# Copy deployment scripts
COPY ./katana/deploy_contracts_devnet.sh .

# Create account file using starkli
RUN starkli account fetch $SIGNER_ADDRESS --output $STARKNET_ACCOUNT

# Make the deployment script executable
RUN chmod +x ./deploy_contracts_devnet.sh

# Set the command to run the deployment script and then display the contract addresses
CMD ["bash", "-c", "./deploy_contracts_devnet.sh $SIGNER_ADDRESS $FOSSIL_PROCESSOR_ADDRESS $VAULT_ROUND_DURATION"]
