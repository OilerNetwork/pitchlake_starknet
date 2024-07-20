#[starknet::contract]
mod MarketAggregator {
    use core::integer::BoundedInt;
    use core::array::ArrayTrait;
    use super::super::interface::{IMarketAggregator, IMarketAggregatorMock};
    use super::super::types::{PeriodTypes::{TIME, BLOCK}, Errors};

    /// *************************************************************************
    ///                              STORAGE
    /// *************************************************************************
    #[storage]
    struct Storage {
        cap_levels: LegacyMap<(felt252, u64, u64), (bool, u128)>,
        reserve_prices: LegacyMap<(felt252, u64, u64), (bool, u256)>,
        strike_prices: LegacyMap<(felt252, u64, u64), (bool, u256)>,
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
        fn get_cap_level_for_block_period(
            self: @ContractState, from: u64, to: u64
        ) -> Option<u128> {
            let (is_set, cap_level) = self.cap_levels.read((BLOCK, from, to));
            match is_set {
                true => Option::Some(cap_level),
                false => Option::None
            }
        }
        fn get_cap_level_for_time_period(self: @ContractState, from: u64, to: u64) -> Option<u128> {
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

        fn get_strike_price_for_block_period(
            self: @ContractState, from: u64, to: u64
        ) -> Option<u256> {
            let (is_set, reserve_price) = self.strike_prices.read((BLOCK, from, to));
            match is_set {
          true => Option::Some(reserve_price),
          false => Option::None
            }
        }

        fn get_strike_price_for_time_period(
            self: @ContractState, from: u64, to: u64
        ) -> Option<u256> {
            let (is_set, reserve_price) = self.strike_prices.read((TIME, from, to));
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
        /// CAP LEVEL ///
        fn set_cap_level_for_block_period(
            ref self: ContractState, from: u64, to: u64, cap_level: u128
        ) {
            let (is_set, _) = self.cap_levels.read((BLOCK, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.cap_levels.write((BLOCK, from, to), (true, cap_level));
        }

        fn set_cap_level_for_time_period(
            ref self: ContractState, from: u64, to: u64, cap_level: u128
        ) {
            let (is_set, _) = self.cap_levels.read((TIME, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.cap_levels.write((TIME, from, to), (true, cap_level));
        }

        /// STRKE PRICE ///
        fn set_strike_price_for_block_period(
            ref self: ContractState, from: u64, to: u64, strike_price: u256
        ) {
            let (is_set, _) = self.strike_prices.read((BLOCK, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.strike_prices.write((BLOCK, from, to), (true, strike_price));
        }

        fn set_strike_price_for_time_period(
            ref self: ContractState, from: u64, to: u64, strike_price: u256
        ) {
            let (is_set, _) = self.strike_prices.read((TIME, from, to));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.strike_prices.write((TIME, from, to), (true, strike_price));
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
