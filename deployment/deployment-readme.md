# Deployment guide

## Prerequisites

- Install [Starkli](https://book.starkli.rs/installation)
- Install [Scarb](https://docs.swmansion.com/scarb/download)

These scripts can be used to deploy multiple vaults and fossil clients at once. 
Let's say you want to deploy 2 vaults and 2 fossil clients. You can do this by adding 2 `constructor_args` entries under the `Vault` and `FossilClient` sections in the `deployment_config.json` file.

```json
//Example
"Vault": {
    "constructor_args": [
        {
            // ... Vault 1 constructor args here
        },
        {
            // ... Vault 2 constructor args here
        }
    ]
}
```
   
## Steps

#### 0. Build the contracts
First, build the contracts running `scarb build` in the `pitchlake_starknet` directory. Then, cd into the `deployment` directory.

#### 1. Create a config file from the template
Run the command below in the `deployment` directory, then fill in the values.
```bash
cp deployment_config.example.json deployment_config.json
```

#### 2. Deploy a fossil client
If you have one already, you can skip this step.
The script below deploys instances of the FossilClient and writes the addresses to `fossil_client_addresses.env`. If the file doesn't exist, it will be created. If it does, it will be overwritten. 
```bash
./deploy_fossil_client.sh
```

#### 3. Deploy the vault(s). 
If you're using a newly deployed FossilClient, make sure to add the fossil client address to Vault constructor args in the `deployment_config.json` file. The deployment script will deploy the vaults and write the addresses to `vault_addresses.env`.
```bash
./deploy_vaults.sh
```

#### 4. Initialize the first round for each vault. 
Now that the vaults have been deployed, you need to initialize the first round on each vault, by setting the initial pricing data. To do this, fill in the `calculation_window` for each vault in the `deployment_config.json` file. This argument is used to determine the time window for the pricing calculation.
```bash
./initialize_first_round.sh
```