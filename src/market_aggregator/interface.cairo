/// *************************************************************************
///                             CONSTANTS
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregatorConsts<TContractState> {
    /// CONSTS ///
    fn get_period_id_block_period(self: @TContractState) -> felt252;
    fn get_period_id_time_period(self: @TContractState) -> felt252;
    fn get_data_id_cap_level(self: @TContractState) -> felt252;
    fn get_data_id_reserve_price(self: @TContractState) -> felt252;
    fn get_data_id_TWAP(self: @TContractState) -> felt252;
}

/// *************************************************************************
///                             CORE (SINGLE)
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregatorSimple<TContractState> {
    fn get_data(
        self: @TContractState, data_id: felt252, period_id: felt252, from: u64, to: u64,
    ) -> Option<felt252>;
}

/// *************************************************************************
///                             CORE (SEPARATE)
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregator<TContractState> {
    /// RESERVE PRICE ///
    fn get_reserve_price_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_reserve_price_for_block_period(
        self: @TContractState, from: u64, to: u64
    ) -> Option<u256>;
    /// CAP LEVEL ///
    fn get_cap_level_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u16>;
    fn get_cap_level_for_block_period(self: @TContractState, from: u64, to: u64) -> Option<u16>;
    /// TWAP ///
    fn get_TWAP_for_block_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_TWAP_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
}

/// *************************************************************************
///                             MOCK (SINGLE)
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregatorMockSimple<TContractState> {
    fn set_data(
        ref self: TContractState,
        data_id: felt252,
        period_id: felt252,
        from: u64,
        to: u64,
        value: felt252
    );
}

/// *************************************************************************
///                             MOCK (SEPARATE)
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
    fn set_cap_level_for_time_period(ref self: TContractState, from: u64, to: u64, cap_level: u16);
    fn set_cap_level_for_block_period(ref self: TContractState, from: u64, to: u64, cap_level: u16);
    /// TWAP ///
    fn set_TWAP_for_block_period(ref self: TContractState, from: u64, to: u64, TWAP: u256);
    fn set_TWAP_for_time_period(ref self: TContractState, from: u64, to: u64, TWAP: u256);
}

