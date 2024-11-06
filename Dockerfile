# Use Ubuntu as the base image
FROM ubuntu:22.04
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

# Starkli environment variables
ENV STARKNET_ACCOUNT=/root/starkli_deployer_account.json
ENV STARKNET_PRIVATE_KEY=$SIGNER_PRIVATE_KEY
ENV STARKNET_RPC=$DEVNET_RPC

ENV SIGNER_ADDRESS=$SIGNER_ADDRESS
ENV FOSSIL_PROCESSOR_ADDRESS=$FOSSIL_PROCESSOR_ADDRESS
ENV VAULT_ROUND_DURATION=$VAULT_ROUND_DURATION

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    libssl-dev 

    # build-essential \
    # pkg-config \
    # git \
    # && rm -rf /var/lib/apt/lists/*

# Install Scarb
ENV PATH="$PATH:/root/.local/bin"
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | bash -s -- -v $SCARB_VERSION

# Install Starkli
ENV PATH="$PATH:/root/.starkli/bin"
RUN curl https://get.starkli.sh | bash
# RUN . /root/.starkli/env
RUN starkliup

WORKDIR /contracts
# Copy project files
COPY . .

# Build contracts
RUN scarb build

# Create account file using starkli
CMD bash -c "starkli account fetch $SIGNER_ADDRESS --output $STARKNET_ACCOUNT && \
chmod +x ./katana/deploy_contracts_devnet.sh && \
./katana/deploy_contracts_devnet.sh $SIGNER_ADDRESS $FOSSIL_PROCESSOR_ADDRESS $VAULT_ROUND_DURATION"