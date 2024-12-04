# Use Ubuntu as the base image
FROM ubuntu:22.04
SHELL ["/bin/bash", "-c"]

# Set environment variables
ENV SCARB_VERSION=2.8.4
ENV STARKLI_VERSION=0.3.5

# Define build-time arguments
ARG SIGNER_PRIVATE_KEY
ARG DEVNET_RPC
ARG SIGNER_ADDRESS
ARG FOSSIL_PROCESSOR_ADDRESS
ARG VAULT_ALPHA
ARG VAULT_STRIKE
ARG ROUND_TRANSITION_DURATION
ARG AUCTION_DURATION
ARG ROUND_DURATION
ARG ARGENT_ADDRESS
ARG ARGENT_SALT
ARG ARGENT_CONSTRUCTOR_ARG1

# Check if all required arguments are provided
RUN if [ -z "$SIGNER_PRIVATE_KEY" ] || \
       [ -z "$DEVNET_RPC" ] || \
       [ -z "$SIGNER_ADDRESS" ] || \
       [ -z "$FOSSIL_PROCESSOR_ADDRESS" ] || \
       [ -z "$VAULT_ALPHA" ] || \
       [ -z "$VAULT_STRIKE" ] || \
       [ -z "$ROUND_TRANSITION_DURATION" ] || \
       [ -z "$AUCTION_DURATION" ] || \
       [ -z "$ROUND_DURATION" ] || \
       [ -z "$ARGENT_ADDRESS" ] || \
       [ -z "$ARGENT_SALT" ] || \
       [ -z "$ARGENT_CONSTRUCTOR_ARG1" ]; then \
    echo "Error: All build arguments must be provided."; \
    exit 1; \
fi

# Starkli environment variables
ENV STARKNET_ACCOUNT=/root/starkli_deployer_account.json
ENV STARKNET_PRIVATE_KEY=$SIGNER_PRIVATE_KEY
ENV STARKNET_RPC=$DEVNET_RPC

ENV SIGNER_ADDRESS=$SIGNER_ADDRESS
ENV FOSSIL_PROCESSOR_ADDRESS=$FOSSIL_PROCESSOR_ADDRESS
ENV VAULT_ALPHA=$VAULT_ALPHA
ENV VAULT_STRIKE=$VAULT_STRIKE
ENV ROUND_TRANSITION_DURATION=$ROUND_TRANSITION_DURATION
ENV AUCTION_DURATION=$AUCTION_DURATION
ENV ROUND_DURATION=$ROUND_DURATION
ENV ARGENT_ADDRESS=$ARGENT_ADDRESS
ENV ARGENT_SALT=$ARGENT_SALT
ENV ARGENT_CONSTRUCTOR_ARG1=$ARGENT_CONSTRUCTOR_ARG1

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    libssl-dev

# Install Scarb
ENV PATH="$PATH:/root/.local/bin"
RUN curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | bash -s -- -v $SCARB_VERSION

# Install Starkli
ENV PATH="$PATH:/root/.starkli/bin"
RUN curl -L https://github.com/xJonathanLEI/starkli/releases/download/v${STARKLI_VERSION}/starkli-x86_64-unknown-linux-gnu.tar.gz -o starkli.tar.gz && \
    mkdir -p /root/.starkli/bin && \
    tar -xvf starkli.tar.gz -C /root/.starkli/bin && \
    rm starkli.tar.gz

WORKDIR /contracts
# Copy project files
COPY . .

# Build contracts
RUN scarb build

# Create account file using starkli
CMD bash -c " cd katana && \
 chmod +x ./deploy_contracts_devnet.sh && \
 chmod +x ./deploy_and_fund_argent_wallet.sh && \
 ./deploy_contracts_devnet.sh $SIGNER_ADDRESS $FOSSIL_PROCESSOR_ADDRESS $VAULT_ALPHA $VAULT_STRIKE $ROUND_TRANSITION_DURATION $AUCTION_DURATION $ROUND_DURATION && \
 ./deploy_and_fund_argent_wallet.sh $ARGENT_ADDRESS $ARGENT_SALT $ARGENT_CONSTRUCTOR_ARG1"
