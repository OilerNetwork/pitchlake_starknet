// https://www.sciencedirect.com/book/9780123745071/auction-theory
// https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4123018

// TODO:
// underlying
// setting expiry
// setting strike price
// collateralization
// settlement
// premium
// batch auction
// historical volatility
// liquidity provision
// option minting
// liquidity roll-over
// reserve price (this will be difficult?)
// liquidity cap
// fossil
use starknet::{ContractAddress, StorePacking};
use array::{Array};
use traits::{Into, TryInto};
use pitch_lake_starknet::vault::{Vault, IVault, IVaultDispatcher};


#[starknet::interface]
trait IPitchLake<TContractState> {
    fn in_the_money_vault(self: @TContractState) -> IVaultDispatcher;
    fn out_the_money_vault(self: @TContractState) -> IVaultDispatcher;
    fn at_the_money_vault(self: @TContractState) -> IVaultDispatcher;
}

#[starknet::contract]
mod PitchLake {
    use starknet::{ContractAddress, StorePacking};
    use starknet::contract_address::ContractAddressZeroable;
    use pitch_lake_starknet::vault::{Vault, IVault, IVaultDispatcher};
    use pitch_lake_starknet::market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher};

    #[storage]
    struct Storage {
        in_the_money_vault: IVaultDispatcher,
        out_the_money_vault: IVaultDispatcher,
        at_the_money_vault: IVaultDispatcher,
        market_aggregator: IMarketAggregatorDispatcher,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        in_the_money_vault_: IVaultDispatcher,
        out_the_money_vault_: IVaultDispatcher,
        at_the_money_vault_: IVaultDispatcher,
        market_aggregator_: IMarketAggregatorDispatcher
    ) { // self.option_round_class_hash.write( option_round_class_hash_);
    }

    #[external(v0)]
    impl PitchLakeImpl of super::IPitchLake<ContractState> {
        fn in_the_money_vault(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: ContractAddressZeroable::zero() }
        }
        fn out_the_money_vault(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: ContractAddressZeroable::zero() }
        }
        fn at_the_money_vault(self: @ContractState) -> IVaultDispatcher {
            IVaultDispatcher { contract_address: ContractAddressZeroable::zero() }
        }
    }
}
