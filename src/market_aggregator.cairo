// how the market aggregator works and comes up with the values is TBD.
#[starknet::interface]
trait IMarketAggregator<TContractState> {
    // this is the average base fee for the previous round, returns in wei
    fn get_average_base_fee(self: @TContractState) -> u256;

    // this is the standard deviation of the base fee for the previous round, returns in wei
    fn get_standard_deviation_base_fee(self: @TContractState) -> u256;

    // this is the current base fee, returns in wei
    fn get_current_base_fee(self: @TContractState) -> u256;
}

#[starknet::contract]
mod MarketAggregator {
    use starknet::{ContractAddress, StorePacking};
    use starknet::contract_address::ContractAddressZeroable;
    #[storage]
    struct Storage {
        average_base_fee: u256,
        standard_deviation_base_fee: u256,
        current_base_fee: u256,
    }

    #[abi(embed_v0)]
    impl IMarketAggregatorImpl of super::IMarketAggregator<ContractState> {
        // TODO add time period. 
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
