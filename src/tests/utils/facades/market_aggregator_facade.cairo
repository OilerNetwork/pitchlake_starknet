use starknet::ContractAddress;
use pitch_lake_starknet::{
    market_aggregator::{
        contract::{MarketAggregator}, types::{DataTypes, PeriodTypes},
        interface::{
            IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
            IMarketAggregatorMockDispatcher, IMarketAggregatorMockDispatcherTrait,
        }
    },
};


#[derive(Drop, Copy)]
struct MarketAggregatorFacade {
    contract_address: ContractAddress
}

#[generate_trait]
impl MarketAggregatorFacadeImpl of MarketAggregatorFacadeTrait {
    // Helpers
    fn get_dispatcher(self: @MarketAggregatorFacade) -> IMarketAggregatorDispatcher {
        IMarketAggregatorDispatcher { contract_address: *self.contract_address }
    }

    fn get_mock_dispatcher(self: @MarketAggregatorFacade) -> IMarketAggregatorMockDispatcher {
        IMarketAggregatorMockDispatcher { contract_address: *self.contract_address }
    }

    // Getters
    fn get_reserve_price_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        self.get_dispatcher().get_reserve_price_for_block_period(from, to)
    }

    fn get_reserve_price_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        self.get_dispatcher().get_reserve_price_for_time_period(from, to)
    }

    fn get_cap_level_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u128> {
        self.get_dispatcher().get_cap_level_for_block_period(from, to)
    }

    fn get_cap_level_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u128> {
        self.get_dispatcher().get_cap_level_for_time_period(from, to)
    }

    fn get_strike_price_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        self.get_dispatcher().get_strike_price_for_block_period(from, to)
    }

    fn get_strike_price_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        self.get_dispatcher().get_strike_price_for_time_period(from, to)
    }

    fn get_TWAP_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        self.get_dispatcher().get_TWAP_for_block_period(from, to)
    }

    fn get_TWAP_for_time_period(self: @MarketAggregatorFacade, from: u64, to: u64) -> Option<u256> {
        self.get_dispatcher().get_TWAP_for_time_period(from, to)
    }

    // Setters
    fn set_reserve_price_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u256
    ) {
        self.get_mock_dispatcher().set_reserve_price_for_block_period(from, to, value)
    }

    fn set_reserve_price_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u256
    ) {
        self.get_mock_dispatcher().set_reserve_price_for_time_period(from, to, value);
    }

    fn set_cap_level_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u128
    ) {
        self.get_mock_dispatcher().set_cap_level_for_block_period(from, to, value);
    }
    fn set_cap_level_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u128
    ) {
        self.get_mock_dispatcher().set_cap_level_for_time_period(from, to, value);
    }

    fn set_strike_price_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u256
    ) {
        self.get_mock_dispatcher().set_strike_price_for_block_period(from, to, value);
    }

    fn set_strike_price_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u256
    ) {
        self.get_mock_dispatcher().set_strike_price_for_time_period(from, to, value);
    }

    fn set_TWAP_for_block_period(self: @MarketAggregatorFacade, from: u64, to: u64, value: u256) {
        self.get_mock_dispatcher().set_TWAP_for_block_period(from, to, value);
    }

    fn set_TWAP_for_time_period(self: @MarketAggregatorFacade, from: u64, to: u64, value: u256) {
        self.get_mock_dispatcher().set_TWAP_for_time_period(from, to, value);
    }
}

