# Fossil and Pitch Lake Integration Testing

## Step 1: Run Katana Devnet
Start the Katana devnet with the following command:

```bash
katana --disable-fee --disable-validate
```

This will launch the Starknet local devnet with fees and validations disabled.

---

## Step 2: Start the Fossil Server

1. Navigate to the server crate directory:

   ```bash
   cd crates/server
   ```

2. Run the server using Cargo:

   ```bash
   cargo run
   ```

---

## Step 3: Deploy Pitch Lake Contracts and Run Integration Test

1. Navigate to the `katana` directory:

   ```bash
   cd katana
   ```

2. Execute the deployment script:

   ```bash
   sh deploy_contracts.sh
   ```

This script will:

- Declare and deploy the required contracts.
- Perform calls to retrieve deployment-specific information.
- Trigger an HTTP request to the Fossil server as part of the integration test.

Make sure that both the Fossil server and Katana devnet are running to ensure the integration test completes successfully.