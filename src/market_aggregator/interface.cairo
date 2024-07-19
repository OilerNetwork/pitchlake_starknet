#[starknet::interface]
trait IMarketAggregator<TContractState> {
    fn get_cap_level(self: @TContractState, date: u64) -> Option<u16>;
    fn get_reserve_price(self: @TContractState, date: u64) -> Option<u256>;
    fn get_TWAP_over_block_numbers(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_TWAP_over_block_timestamps(self: @TContractState, from: u64, to: u64) -> Option<u256>;
}

#[starknet::interface]
trait IMockMarketAggregator<TContractState> {
    fn set_cap_level(ref self: TContractState, date: u64, cap_level: u16);
    fn set_reserve_price(ref self: TContractState, date: u64, reserve_price: u256);
    fn set_TWAP_over_block_numbers(ref self: TContractState, from: u64, to: u64, TWAP: u256);
    fn set_TWAP_over_block_timestamps(ref self: TContractState, from: u64, to: u64, TWAP: u256);
}

