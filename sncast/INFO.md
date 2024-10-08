[Install starknet-foundry](https://foundry-rs.github.io/starknet-foundry/getting-started/installation.html) [0.30.0]

Copy .starknet_accounts/ex.starknet_open_zeppelin_accounts.json into: .starknet_accounts/starknet_open_zeppelin_accounts.json (Can either go through the docs to setup an account or ping Matt for user1's credentials)

### Declaring contracts:

`sncast declare -c OptionRound --fee-token eth`

> Class Hash: 0x414e758a0be04c15fde58f7cbfd9f72b05646a3a3ee6f2e708e67c24469adc3 (1900 UTC oct 8)

`sncast declare -c Vault --fee-token eth`

> Class Hash: 0x60309f37b2b47b167c41810f0d95b9018ec36a0f1f65b4d5d6bf2f0b7f1fc89 (1900 UTC oct 8)

### Deploying a Vault

#### Constructor Args

1. Address for Fossil request fulfiller contract (doesnt matter for now)
2. Eth contract address
3. OptionRound class Hash
4. VaultType (doesnt matter right now)

`sncast deploy --fee-token eth --class-hash 0x60309f37b2b47b167c41810f0d95b9018ec36a0f1f65b4d5d6bf2f0b7f1fc89 --constructor-calldata 0xdeadbeef 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7 0x414e758a0be04c15fde58f7cbfd9f72b05646a3a3ee6f2e708e67c24469adc3 0x0`

> Vault: 0x78c96c4238c1d0294b6cfacfbfdba1cc289e978685231284a3bd2ae00dd3f56 (1900 UTC oct 8)

### Allowing a Vault or OptionRound to spend tokens

Go to the Sepolia ETH contract [here](https://sepolia.voyager.online/contract/0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7#writeContract) and invoke function 1 `increase_allowance`. The spender should be a Vault or OptionRound's contract address. Added value is the amount to increase the spender's allowance by.
