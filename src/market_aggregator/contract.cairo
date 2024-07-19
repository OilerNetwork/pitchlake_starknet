#[starknet::contract]
mod MarketAggregator {
    use core::integer::BoundedInt;
    use core::array::ArrayTrait;
    use super::super::interface::{IMarketAggregator, IMarketAggregatorMock};
    use super::super::types::{
        PeriodTypes::{TIME, BLOCK}, DataTypes::{RESERVE_PRICE, CAP_LEVEL, TWAP}, Errors
    };

    /// *************************************************************************
    ///                              STORAGE
    /// *************************************************************************
    #[storage]
    struct Storage {
        data: LegacyMap<(felt252, felt252, u64, u64), (bool, felt252)>,
        cap_levels: LegacyMap<(felt252, u64, u64), (bool, u16)>,
        reserve_prices: LegacyMap<(felt252, u64, u64), (bool, u256)>,
        TWAPs: LegacyMap<(felt252, u64, u64), (bool, u256)>,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************
    #[constructor]
    fn constructor(ref self: ContractState) {}

    /// *************************************************************************
    ///                            IMPLEMENTATION
    /// *************************************************************************
    /// Set data using a single function
    #[abi(embed_v0)]
    impl MarketAggregatorImpl of IMarketAggregator<ContractState> {
        /// CONSTS ///
        fn get_period_id_block(self: @ContractState) -> felt252 {
            BLOCK
        }
        fn get_period_id_time(self: @ContractState) -> felt252 {
            TIME
        }
        fn get_data_id_cap_level(self: @ContractState) -> felt252 {
            CAP_LEVEL
        }
        fn get_data_id_reserve_price(self: @ContractState) -> felt252 {
            RESERVE_PRICE
        }
        fn get_data_id_TWAP(self: @ContractState) -> felt252 {
            TWAP
        }

        /// GETTERS ///
        //fn get_data(
        //    self: @ContractState, data_id: felt252, period_id: felt252, from: u64, to: u64
        //) -> Option<felt252> {
        //    let (is_set, data) = self.data.read((data_id, period_id, from, to));
        //    match is_set {
        //        true => { Option::Some(data) },
        //        false => (Option::None),
        //    }
        //}

        fn get_cap_level_for_block_period(self: @ContractState, from: u64, to: u64) -> Option<u16> {
            let (is_set, cap_level) = self.cap_levels.read((BLOCK, from, to));
            match is_set {
                true => Option::Some(cap_level),
                false => Option::None
            }
        }
        fn get_cap_level_for_time_period(self: @ContractState, from: u64, to: u64) -> Option<u16> {
            let (is_set, cap_level) = self.cap_levels.read((TIME, from, to));
            match is_set {
                true => Option::Some(cap_level),
                false => Option::None
            }
        }

        fn get_reserve_price_for_block_period(
            self: @ContractState, from: u64, to: u64
        ) -> Option<u256> {
            let (is_set, reserve_price) = self.reserve_prices.read((BLOCK, from, to));
            match is_set {
                true => Option::Some(reserve_price),
                false => Option::None
            }
        }
        fn get_reserve_price_for_time_period(
            self: @ContractState, from: u64, to: u64
        ) -> Option<u256> {
            let (is_set, reserve_price) = self.reserve_prices.read((TIME, from, to));
            match is_set {
                true => Option::Some(reserve_price),
                false => Option::None
            }
        }

        fn get_TWAP_for_block_period(self: @ContractState, from: u64, to: u64) -> Option<u256> {
            let (is_set, TWAP) = self.TWAPs.read((BLOCK, from, to));
            match is_set {
                true => Option::Some(TWAP),
                false => Option::None
            }
        }

        fn get_TWAP_for_time_period(self: @ContractState, from: u64, to: u64) -> Option<u256> {
            let (is_set, TWAP) = self.TWAPs.read((TIME, from, to));
            match is_set {
                true => Option::Some(TWAP),
                false => Option::None
            }
        }
    }

    /// *************************************************************************
    ///                         MOCK IMPLEMENTATION
    /// *************************************************************************
    /// Entry points to set the data for testing as a single function
    #[abi(embed_v0)]
    impl MarketAggregatorMock of IMarketAggregatorMock<ContractState> {
        /// SETTERS ///
        //fn set_data(
        //    ref self: ContractState,
        //    data_id: felt252,
        //    period_id: felt252,
        //    from: u64,
        //    to: u64,
        //    value: felt252
        //) {
        //    let (is_set, _) = self.data.read((data_id, period_id, from, to));
        //    //assert(!is_set, Errors::VALUE_ALREADY_SET);

        //    // Cap level is based on bps, so it should be less than 10000
        //    // @dev Cap level of 5,000 means the cap is 50%
        //    if (data_id == CAP_LEVEL) {
        //        assert(
        //            TryInto::<felt252, u16>::try_into(value).is_some(), Errors::CAP_LEVEL_TOO_BIG
        //        );
        //    }
        //
        //            self.data.write((data_id, period_id, from, to), (true, value));
        //        }

        /// CAP LEVEL ///
        fn set_cap_level_for_block_period(
            ref self: ContractState, from: u64, to: u64, cap_level: u16
        ) {
            let (is_set, _) = self.cap_levels.read((BLOCK, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.cap_levels.write((BLOCK, from, to), (true, cap_level));
        }

        fn set_cap_level_for_time_period(
            ref self: ContractState, from: u64, to: u64, cap_level: u16
        ) {
            let (is_set, _) = self.cap_levels.read((TIME, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.cap_levels.write((TIME, from, to), (true, cap_level));
        }

        /// RESERVE PRICE ///
        fn set_reserve_price_for_block_period(
            ref self: ContractState, from: u64, to: u64, reserve_price: u256
        ) {
            let (is_set, _) = self.reserve_prices.read((BLOCK, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.reserve_prices.write((BLOCK, from, to), (true, reserve_price));
        }

        fn set_reserve_price_for_time_period(
            ref self: ContractState, from: u64, to: u64, reserve_price: u256
        ) {
            let (is_set, _) = self.reserve_prices.read((TIME, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.reserve_prices.write((TIME, from, to), (true, reserve_price));
        }

        /// TWAP ///
        fn set_TWAP_for_block_period(ref self: ContractState, from: u64, to: u64, TWAP: u256) {
            let (is_set, _) = self.TWAPs.read((BLOCK, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.TWAPs.write((BLOCK, from, to), (true, TWAP));
        }

        fn set_TWAP_for_time_period(ref self: ContractState, from: u64, to: u64, TWAP: u256) {
            let (is_set, _) = self.TWAPs.read((TIME, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.TWAPs.write((TIME, from, to), (true, TWAP));
        }
    }
}
