# Fossil and Pitch Lake Integration Testing

## Fossil Server

To start the Fossil server:

1. Navigate to the server crate directory:
   ```bash
   cd crates/server
   ```

2. Run the server using Cargo:
   ```bash
   cargo run
   ```

## Pitch Lake Contracts Deployment

To deploy the Pitch Lake contracts and run the integration test:

1. Navigate to the `katana` directory:
   ```bash
   cd katana
   ```

2. Execute the deployment script:
   ```bash
   sh deploy_contracts.sh
   ```

This script will declare and deploy the necessary contracts, and then run the integration test performing an HTTP request to the Fossil server. 