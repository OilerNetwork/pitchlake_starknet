[Install starknet-foundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) [0.30.0]

Copy .starknet_accounts/ex.starknet_open_zeppelin_accounts.json into: .starknet_accounts/starknet_open_zeppelin_accounts.json (Can either go through the docs to setup an account or ping Matt for user1's credentials)

### Declaring contracts:

`sncast declare -c FossilClient --fee-token eth`

> Class Hash: 0x5b5b7facaf410276e1f15c0093ec172066243e82257e923c710f35b1ca29b4d (1930 UTC oct 13)

`sncast declare -c OptionRound --fee-token eth`

> Class Hash: 0x0414e758a0be04c15fde58f7cbfd9f72b05646a3a3ee6f2e708e67c24469adc3 (1930 UTC oct 13)

`sncast declare -c Vault --fee-token eth`

> Class Hash: 0x413a8f2c623ab40e5820152018c6a5fb19085c30750641ced024061ff04c923 (1930 UTC oct 13)

### Deploying a Fossil Client

1. fossil_processor_address: doesnt matter for now

`sncast deploy --fee-token eth --class-hash 0x5b5b7facaf410276e1f15c0093ec172066243e82257e923c710f35b1ca29b4d --constructor-calldata 0xdeadbeef`

> Fossil Client: 0x698e701e57224d9200409b4516206630174817e038600a0da22386768251fc5 (1930 UTC oct 13)

### Deploying a Vault

#### Constructor Args

1. fossil_client_address
2. eth_contract_address
3. option_round_class_hash
4. vault_type

`sncast deploy --fee-token eth --class-hash 0x413a8f2c623ab40e5820152018c6a5fb19085c30750641ced024061ff04c923 --constructor-calldata 0x698e701e57224d9200409b4516206630174817e038600a0da22386768251fc5 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 0x0414e758a0be04c15fde58f7cbfd9f72b05646a3a3ee6f2e708e67c24469adc3 0x1`

> Vault: 0x7da35131106358927568c32faaee3eb2063b154578be6be2e3a2582db39fc56 (1930 UTC oct 13)

### Allowing a Vault or OptionRound to spend tokens

Go to the Sepolia ETH contract [here](https://sepolia.voyager.online/contract/0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7#writeContract) and invoke function 1 `increase_allowance`. The spender should be a Vault or OptionRound's contract address. Added value is the amount to increase the spender's allowance by.
