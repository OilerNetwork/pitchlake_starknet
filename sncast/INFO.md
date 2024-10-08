[Install starknet-foundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) [0.30.0]

Copy .starknet_accounts/ex.starknet_open_zeppelin_accounts.json into: .starknet_accounts/starknet_open_zeppelin_accounts.json (Can either go through the docs to setup an account or ping Matt for user1's credentials)

### Declaring contracts:

`sncast declare -c OptionRound --fee-token eth`

> Class Hash: 0x206074c201341c3dc87307bb00ffdf51eec278bdd0874cbb24db011ad3fe360 (1830 UTC oct 8)

`sncast declare -c Vault --fee-token eth`

> Class Hash: 0x2371bb19822ba557db6b2f27d9c9dd262ec133d84f26dfe5987113db9583a7a (1830 UTC oct 8)

### Deploying a Vault

#### Constructor Args

1. Address for Fossil request fulfiller contract (doesnt matter for now)
2. Eth contract address
3. OptionRound class Hash
4. VaultType (doesnt matter right now)

`sncast deploy --fee-token eth --class-hash 0x2371bb19822ba557db6b2f27d9c9dd262ec133d84f26dfe5987113db9583a7a --constructor-calldata 0xdeadbeef 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 0x206074c201341c3dc87307bb00ffdf51eec278bdd0874cbb24db011ad3fe360 0x0`

> Vault: 0x01227dc95e9b169a2818f6f7575d6a952e4d7432089b1b868d4aad86f618afc2 (1830 UTC oct 8)

### Allowing a Vault or OptionRound to spend tokens

Go to the Sepolia ETH contract [here](https://sepolia.voyager.online/contract/0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7#writeContract) and invoke function 1 `increase_allowance`. The spender should be a Vault or OptionRound's contract address. Added value is the amount to increase the spender's allowance by.
