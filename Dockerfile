# Use Ubuntu as the base image
FROM ubuntu:22.04
SHELL ["/bin/bash", "-c"]

# Set environment variables
ENV SCARB_VERSION=2.8.4
ENV STARKLI_VERSION=0.3.5

# Starkli environment variables
ENV STARKNET_ACCOUNT=/root/starkli_deployer_account.json

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
