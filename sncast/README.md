## Dependencies

[Install starknet-foundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) [0.32.0]

### Setup account to declare/deploy (use `sncast`) from

1. Copy .starknet_accounts/ex.starknet_accounts.json into: .starknet_accounts/starknet_accounts.json

> If deploying to sepolia you need to use the credentials of a deployed & funded sepolia account

### Run Katana

1. In a separate terminal run `katana --allowed-origins http://localhost:3002 --disable-validate --eth-gas-price 0 --block-time 5000`

> Port 3002 assumes this is the port the frontend is running on (Fossil API is using 3000 at this time), --block-time is in milliseconds and is arbitrary

### Using Argent wallets on the devnet

To use an Argent wallet on the devnet you need to fund and deploy it first.

#### Add the devnet to your Argent extension

1. Open Argent > Settings > Developer Settings > Manage Networks > plus icon

2. Name the network accordingly (i.e. "Katana" or "Juno"), set the Chain ID to "SN_SEPOLIA", the RPC URL to "http://localhost:5050"

3. Open Advanced Settings and ensure the Account class hash is `0x36078334509b514626504edc9fb252328d1a240e4e948bef8d0c08dff45927f` and the Fee Token Address is `0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7`

#### Create a new account

1. Select the newly created network and create a new account

2. Open Settings > Developer Settings > Deployment Data

3. Copy `.sncast/.env-example` into `.sncast/.env` and populate the fields according to the deployment data in Argent

### Run the bash script (`.sncast/script.sh`)

1. Open the bash script in this directory and make sure the bottom section for declaring the Argent contract is not commented out.

2. From the root directory run `bash sncast/script.sh`

> This will deploy the contracts, handle the first round's fossil request, and deploy/fund your Argent account

### Running the Fossil API

1. Clone the Fossil API [repo](https://github.com/OilerNetwork/fossil-offchain-processor) and checkout the `headers-from-rpc` branch

2. Build the API using `cargo build` and run it using `cargo run`

### Running the Frontend

1. Clone the Fossil Frontend [repo](https://github.com/OilerNetwork/pitchlake-ui-new) and install the dependencies (`pnpm install`)

2. For now, we need to replace the vault address in the page.tsx file. Go to page.tsx, and at the top of the file is an array of vault addresses, only place the just deployed vault here

3. Run the frontend on port 3002 using `pnpm run dev -p 3002`
