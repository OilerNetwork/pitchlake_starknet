# Use Ubuntu as the base image
FROM ubuntu:22.04
SHELL ["/bin/bash", "-c"]

ARG SCARB_VERSION
ARG STARKLI_VERSION
ARG COMPILER_VERSION

ENV SCARB_VERSION=${SCARB_VERSION}
ENV STARKLI_VERSION=${STARKLI_VERSION}
ENV COMPILER_VERSION=${COMPILER_VERSION}

# Starkli environment variables
ENV STARKNET_ACCOUNT=/root/starkli_deployer_account.json

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    curl \
    libssl-dev \
    dos2unix

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

COPY . .

# Enforce the unix line endings
RUN find . -type f -name "*.sh" -exec sh -c 'dos2unix "$1" && chmod +x "$1"' _ {} \;

# Build contracts
RUN scarb build

CMD cd katana && \
    echo "Environment in Dockerfile:" && \
    echo "DEPLOYER_ADDRESS=$DEPLOYER_ADDRESS" && \
    echo "FOSSIL_PROCESSOR_ADDRESS=$FOSSIL_PROCESSOR_ADDRESS" && \
    echo "VAULT_ALPHA=$VAULT_ALPHA" && \
    echo "VAULT_STRIKE=$VAULT_STRIKE" && \
    echo "ROUND_TRANSITION_DURATION=$ROUND_TRANSITION_DURATION" && \
    echo "AUCTION_DURATION=$AUCTION_DURATION" && \
    echo "ROUND_DURATION=$ROUND_DURATION" && \
    chmod +x deploy_contracts_devnet.sh && ./deploy_contracts_devnet.sh "$DEPLOYER_ADDRESS" "$FOSSIL_PROCESSOR_ADDRESS" "$VAULT_ALPHA" "$VAULT_STRIKE" "$ROUND_TRANSITION_DURATION" "$AUCTION_DURATION" "$ROUND_DURATION"