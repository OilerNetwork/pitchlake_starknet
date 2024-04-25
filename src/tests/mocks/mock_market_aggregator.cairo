use pitch_lake_starknet::market_aggregator::{IMarketAggregator, IMarketAggregatorDispatcher};

// NOTE ONLY USED IN TESTS FOR MOCKING PURPOSES
#[starknet::interface]
trait IMarketAggregatorSetter<TContractState> {
    fn set_average_base_fee(ref self: TContractState, base_fee: u256);

    fn set_standard_deviation_base_fee(ref self: TContractState, base_fee: u256);

    fn set_current_base_fee(ref self: TContractState, base_fee: u256);
}

#[starknet::contract]
mod MockMarketAggregator {
    use starknet::{ContractAddress, StorePacking};
    use starknet::contract_address::ContractAddressZeroable;
    #[storage]
    struct Storage {
        average_base_fee: u256,
        standard_deviation_base_fee: u256,
        current_base_fee: u256,
    }
    #[abi(embed_v0)]
    impl MockMarketAggregatorSetterImpl of super::IMarketAggregatorSetter<ContractState> {
        fn set_average_base_fee(ref self: ContractState, base_fee: u256) {
            self.average_base_fee.write(base_fee);
        }

        fn set_standard_deviation_base_fee(ref self: ContractState, base_fee: u256) {
            self.standard_deviation_base_fee.write(base_fee);
        }

        fn set_current_base_fee(ref self: ContractState, base_fee: u256) {
            self.current_base_fee.write(base_fee);
        }
    }
    #[abi(embed_v0)]
    impl MockMarketAggregatorImpl of super::IMarketAggregator<ContractState> {
        // this is the average base fee for the previous round, returns in wei
        fn get_average_base_fee(self: @ContractState) -> u256 {
            self.average_base_fee.read()
        }

        // this is the standard deviation of the base fee for the previous round, returns in wei
        fn get_standard_deviation_base_fee(self: @ContractState) -> u256 {
            self.standard_deviation_base_fee.read()
        }

        // this is the current base fee, returns in wei
        fn get_current_base_fee(self: @ContractState) -> u256 {
            self.current_base_fee.read()
        }
    }
}
