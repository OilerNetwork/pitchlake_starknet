[Install starknet-foundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) [0.30.0]

Copy .starknet_accounts/ex.starknet_open_zeppelin_accounts.json into: .starknet_accounts/starknet_open_zeppelin_accounts.json (Can either go through the docs to setup an account or ping Matt for user1's credentials)

### Declaring contracts:

`sncast declare -c FossilClient --fee-token eth`

> Class Hash: 0x5b5b7facaf410276e1f15c0093ec172066243e82257e923c710f35b1ca29b4d (0400 UTC oct 17)

`sncast declare -c OptionRound --fee-token eth`

> Class Hash: 0xc3120f7bdeaa79d89614731abb645e64cb5bc4e05b2807e18ba57179fd6547 (0400 UTC oct 17)

`sncast declare -c Vault --fee-token eth`

> Class Hash: 0x1bf112592e295c5ca2f9a1fc580893305fd9cb84e480e59994d757d60676376 (0400 UTC oct 17)

### Deploying a Fossil Client

1. fossil_processor_address: doesnt matter for now

`sncast deploy --fee-token eth --class-hash 0x5b5b7facaf410276e1f15c0093ec172066243e82257e923c710f35b1ca29b4d --constructor-calldata 0xdeadbeef`

> Fossil Client: 0x611f705ff76a332f8861cbedaa267ba2ab4b9d5a5929dcb28dbb46b02f5db16 (0400 UTC oct 17)

### Deploying a Vault

#### Constructor Args

1. fossil_client_address
2. eth_contract_address
3. option_round_class_hash
4. alpha
5. strike_level

`sncast deploy --fee-token eth --class-hash 0x1bf112592e295c5ca2f9a1fc580893305fd9cb84e480e59994d757d60676376 --constructor-calldata 0x611f705ff76a332f8861cbedaa267ba2ab4b9d5a5929dcb28dbb46b02f5db16 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 0xc3120f7bdeaa79d89614731abb645e64cb5bc4e05b2807e18ba57179fd6547 5555 0`

> Vault: 0x115736e919f6825a64431760d228a937680ebae18a672f03b2c996fe1405a68 (0400 UTC oct 17)

### Allowing a Vault or OptionRound to spend tokens

Go to the Sepolia ETH contract [here](https://sepolia.voyager.online/contract/0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7#writeContract) and invoke function 1 `increase_allowance`. The spender should be a Vault or OptionRound's contract address. Added value is the amount to increase the spender's allowance by.
