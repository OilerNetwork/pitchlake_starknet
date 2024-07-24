use pitch_lake_starknet::vault::interface::{IVaultDispatcher};

#[starknet::interface]
trait IPitchLake<TContractState> {
    fn in_the_money_vault(self: @TContractState) -> IVaultDispatcher;
    fn out_the_money_vault(self: @TContractState) -> IVaultDispatcher;
    fn at_the_money_vault(self: @TContractState) -> IVaultDispatcher;
}

#[starknet::contract]
mod PitchLake {
    use starknet::{ContractAddress, contract_address::ContractAddressZeroable};
    use pitch_lake_starknet::{
        vault::{interface::{IVault, IVaultDispatcher}},
        market_aggregator::interface::{IMarketAggregator, IMarketAggregatorDispatcher}
    };

    #[storage]
    struct Storage {
        in_the_money_vault: ContractAddress,
        out_the_money_vault: ContractAddress,
        at_the_money_vault: ContractAddress,
        market_aggregator: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        in_the_money_vault_: ContractAddress,
        out_the_money_vault_: ContractAddress,
        at_the_money_vault_: ContractAddress,
        market_aggregator_: ContractAddress
    ) { // self.option_round_class_hash.write( option_round_class_hash_);
        self.in_the_money_vault.write(in_the_money_vault_);
        self.out_the_money_vault.write(out_the_money_vault_);
        self.at_the_money_vault.write(at_the_money_vault_);
        self.in_the_money_vault.write(market_aggregator_);
    }

    #[abi(embed_v0)]
    impl PitchLakeImpl of super::IPitchLake<ContractState> {
        fn in_the_money_vault(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: self.in_the_money_vault.read() }
        }
        fn out_the_money_vault(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: self.out_the_money_vault.read() }
        }
        fn at_the_money_vault(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: self.at_the_money_vault.read() }
        }
    }
}
