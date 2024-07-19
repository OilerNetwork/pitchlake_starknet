#[starknet::interface]
trait IMarketAggregator<TContractState> {
    fn get_cap_level(self: @TContractState, date: u64) -> Result<u16, felt252>;
    fn get_reserve_price(self: @TContractState, date: u64) -> Result<u256, felt252>;
    fn get_TWAP_over_block_timestamps(
        self: @TContractState, block_timestamp_from: u64, block_timestamp_to: u64
    ) -> Result<u256, felt252>;
    fn get_TWAP_over_block_numbers(
        self: @TContractState, block_number_from: u64, block_number_to: u64
    ) -> Result<u256, felt252>;
}

#[starknet::interface]
trait IMarketAggregatorSetter<TContractState> {
    fn set_cap_level(ref self: TContractState, date: u64, cap_level: u16);
    fn set_reserve_price(ref self: TContractState, date: u64, reserve_price: u256);
    fn set_TWAP_over_block_timestamps(ref self: TContractState, from: u64, to: u64, TWAP: u256);
    fn set_TWAP_over_block_numbers(ref self: TContractState, from: u64, to: u64, TWAP: u256);
}

