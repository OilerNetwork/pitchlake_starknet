/// *************************************************************************
///                                 CORE
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregator<TContractState> {
    /// TWAP ///
    fn get_TWAP_for_block_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;
    fn get_TWAP_for_time_period(self: @TContractState, from: u64, to: u64) -> Option<u256>;

    /// RESERVE PRICE ///
    /// VOLATILITY ///
    /// CAP LEVEL ///
    fn get_reserve_price_for_round(
        self: @TContractState, vault_address: starknet::ContractAddress, round_id: u256
    ) -> Option<u256>;
    fn get_volatility_for_round(
        self: @TContractState, vault_address: starknet::ContractAddress, round_id: u256
    ) -> Option<u128>;
    fn get_cap_level_for_round(
        self: @TContractState, vault_address: starknet::ContractAddress, round_id: u256
    ) -> Option<u128>;
}

/// *************************************************************************
///                                 MOCK
/// *************************************************************************
#[starknet::interface]
trait IMarketAggregatorMock<TContractState> {
    /// TWAP ///
    fn set_TWAP_for_block_period(ref self: TContractState, from: u64, to: u64, TWAP: u256);
    fn set_TWAP_for_time_period(ref self: TContractState, from: u64, to: u64, TWAP: u256);

    /// RESERVE PRICE ///
    /// VOLATILITY ///
    /// CAP LEVEL ///
    fn set_reserve_price_for_round(
        ref self: TContractState,
        vault_address: starknet::ContractAddress,
        round_id: u256,
        reserve_price: u256
    );
    fn set_volatility_for_round(
        ref self: TContractState,
        vault_address: starknet::ContractAddress,
        round_id: u256,
        vol: u128
    );
    fn set_cap_level_for_round(
        ref self: TContractState,
        vault_address: starknet::ContractAddress,
        round_id: u256,
        cap_level: u128
    );
}
