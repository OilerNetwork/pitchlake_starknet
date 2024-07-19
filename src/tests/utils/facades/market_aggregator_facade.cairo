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

    // Const getters
    fn get_period_id_block(self: @MarketAggregatorFacade) -> felt252 {
        self.get_dispatcher().get_period_id_block()
    }

    fn get_period_id_time(self: @MarketAggregatorFacade) -> felt252 {
        self.get_dispatcher().get_period_id_time()
    }

    fn get_data_id_reserve_price(self: @MarketAggregatorFacade) -> felt252 {
        self.get_dispatcher().get_data_id_reserve_price()
    }

    fn get_data_id_cap_level(self: @MarketAggregatorFacade) -> felt252 {
        self.get_dispatcher().get_data_id_cap_level()
    }

    fn get_data_id_TWAP(self: @MarketAggregatorFacade) -> felt252 {
        self.get_dispatcher().get_data_id_TWAP()
    }

    // Getters
    fn _get_data(
        self: @MarketAggregatorFacade, data_id: felt252, period_id: felt252, from: u64, to: u64
    ) -> Option<felt252> {
        self.get_dispatcher().get_data(data_id, period_id, from, to)
    }

    fn get_reserve_price_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        let data_id = self.get_data_id_reserve_price();
        let period_id = self.get_dispatcher().get_period_id_block();
        let res = self._get_data(data_id, period_id, from, to).unwrap();
        Option::Some(res.into())
    }

    fn get_reserve_price_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        let data_id = self.get_data_id_reserve_price();
        let period_id = self.get_dispatcher().get_period_id_time();
        let res = self._get_data(data_id, period_id, from, to).unwrap();
        Option::Some(res.into())
    }

    fn get_cap_level_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u16> {
        let data_id = self.get_data_id_cap_level();
        let period_id = self.get_dispatcher().get_period_id_block();
        let res = self._get_data(data_id, period_id, from, to).unwrap();
        Option::Some(res.try_into().unwrap())
    }

    fn get_cap_level_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u16> {
        let data_id = self.get_data_id_cap_level();
        let period_id = self.get_dispatcher().get_period_id_time();
        let res = self._get_data(data_id, period_id, from, to).unwrap();
        Option::Some(res.try_into().unwrap())
    }


    fn get_TWAP_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64
    ) -> Option<u256> {
        let data_id = self.get_data_id_TWAP();
        let period_id = self.get_dispatcher().get_period_id_block();
        let res = self._get_data(data_id, period_id, from, to).unwrap();
        Option::Some(res.into())
    }

    fn get_TWAP_for_time_period(self: @MarketAggregatorFacade, from: u64, to: u64) -> Option<u256> {
        let data_id = self.get_data_id_TWAP();
        let period_id = self.get_dispatcher().get_period_id_time();
        let res: Option<felt252> = self._get_data(data_id, period_id, from, to);
        match res {
            Option::Some(value) => Option::Some(value.into()),
            Option::None => Option::Some(0),
        }
    }

    // Setters
    fn set_reserve_price_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u256
    ) {
        let data_id = self.get_data_id_reserve_price();
        let period_id = self.get_dispatcher().get_period_id_block();
        self
            .get_mock_dispatcher()
            .set_data(data_id, period_id, from, to, value.try_into().unwrap());
    }

    fn set_reserve_price_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u256
    ) {
        self
            .get_mock_dispatcher()
            .set_reserve_price_for_time_period(from, to, value.try_into().unwrap());
    }

    fn set_cap_level_for_block_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u16
    ) {
        self.get_mock_dispatcher().set_cap_level_for_block_period(from, to, value.into());
    }
    fn set_cap_level_for_time_period(
        self: @MarketAggregatorFacade, from: u64, to: u64, value: u16
    ) {
        self.get_mock_dispatcher().set_cap_level_for_time_period(from, to, value.into());
    }

    fn set_TWAP_for_block_period(self: @MarketAggregatorFacade, from: u64, to: u64, value: u256) {
        self.get_mock_dispatcher().set_TWAP_for_block_period(from, to, value.try_into().unwrap());
    }

    fn set_TWAP_for_time_period(self: @MarketAggregatorFacade, from: u64, to: u64, value: u256) {
        self.get_mock_dispatcher().set_TWAP_for_time_period(from, to, value.try_into().unwrap());
    }
}

