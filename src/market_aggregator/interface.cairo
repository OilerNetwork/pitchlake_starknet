/// *************************************************************************
///                                 CORE
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregator<TContractState> {
    /// RESERVE PRICE ///
    fn get_reserve_price_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_reserve_price_for_block_period(
        self: @TContractState, from: u64, to: u64
    ) -> Option<u256>;
    /// CAP LEVEL ///
    fn get_cap_level_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u128>;
    fn get_cap_level_for_block_period(self: @TContractState, from: u64, to: u64) -> Option<u128>;
    /// SRIKE PRICE ///
    fn get_strike_price_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_strike_price_for_block_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;

    /// TWAP ///
    fn get_TWAP_for_block_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_TWAP_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
}

/// *************************************************************************
///                                 MOCK
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregatorMock<TContractState> {
    /// RESERVE PRICE ///
    fn set_reserve_price_for_time_period(
        ref self: TContractState, from: u64, to: u64, reserve_price: u256
    );
    fn set_reserve_price_for_block_period(
        ref self: TContractState, from: u64, to: u64, reserve_price: u256
    );
    /// CAP LEVEL ///
    fn set_cap_level_for_time_period(ref self: TContractState, from: u64, to: u64, cap_level: u128);
    fn set_cap_level_for_block_period(
        ref self: TContractState, from: u64, to: u64, cap_level: u128
    );
    /// STRIKE PRICE ///
    fn set_strike_price_for_time_period(
        ref self: TContractState, from: u64, to: u64, strike_price: u256
    );
    fn set_strike_price_for_block_period(
        ref self: TContractState, from: u64, to: u64, strike_price: u256
    );
    /// TWAP ///
    fn set_TWAP_for_block_period(ref self: TContractState, from: u64, to: u64, TWAP: u256);
    fn set_TWAP_for_time_period(ref self: TContractState, from: u64, to: u64, TWAP: u256);
}
