#[starknet::contract]
mod MarketAggregator {
    use core::integer::BoundedInt;
    use core::array::ArrayTrait;
    use starknet::ContractAddress;
    use super::super::interface::{IMarketAggregator, IMarketAggregatorMock};
    use super::super::types::{PeriodTypes::{TIME, BLOCK}, Errors};
    use pitch_lake_starknet::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};

    /// *************************************************************************
    ///                              STORAGE
    /// *************************************************************************
    #[storage]
    struct Storage {
        cap_levels: LegacyMap<(felt252, u64, u64), (bool, u128)>,
        reserve_prices: LegacyMap<(felt252, u64, u64), (bool, u256)>,
        strike_prices: LegacyMap<(felt252, u64, u64), (bool, u256)>,
        TWAPs: LegacyMap<(felt252, u64, u64), (bool, u256)>,
        vols: LegacyMap<(felt252, u64, u64), (bool, u128)>,
        reserve_prices_for_rounds: LegacyMap<(ContractAddress, u256), (bool, u256)>,
        volatility_for_rounds: LegacyMap<(ContractAddress, u256), (bool, u128)>,
        cap_level_for_rounds: LegacyMap<(ContractAddress, u256), (bool, u128)>,
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

        fn get_reserve_price_for_round(
            self: @ContractState, vault_address: ContractAddress, round_id: u256
        ) -> Option<u256> {
            let (is_set, reserve_price) = self
                .reserve_prices_for_rounds
                .read((vault_address, round_id));
            match is_set {
                true => Option::Some(reserve_price),
                false => Option::None
            }
        }

        fn get_volatility_for_round(
            self: @ContractState, vault_address: ContractAddress, round_id: u256
        ) -> Option<u128> {
            let (is_set, vol) = self.volatility_for_rounds.read((vault_address, round_id));
            match is_set {
                true => Option::Some(vol),
                false => Option::None
            }
        }


        fn get_cap_level_for_round(
            self: @ContractState, vault_address: ContractAddress, round_id: u256
        ) -> Option<u128> {
            let (is_set, cap_level) = self.cap_level_for_rounds.read((vault_address, round_id));
            match is_set {
                true => Option::Some(cap_level),
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

        /// RESERVE PRICE ///
        /// VOLATILITY ///
        /// CAP LEVEL ///
        fn set_reserve_price_for_round(
            ref self: ContractState,
            vault_address: ContractAddress,
            round_id: u256,
            reserve_price: u256
        ) {
            let (is_set, _) = self.reserve_prices_for_rounds.read((vault_address, round_id));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.reserve_prices_for_rounds.write((vault_address, round_id), (true, reserve_price));
        }

        fn set_volatility_for_round(
            ref self: ContractState, vault_address: ContractAddress, round_id: u256, vol: u128
        ) {
            let (is_set, _) = self.volatility_for_rounds.read((vault_address, round_id));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.volatility_for_rounds.write((vault_address, round_id), (true, vol));
        }

        fn set_cap_level_for_round(
            ref self: ContractState, vault_address: ContractAddress, round_id: u256, cap_level: u128
        ) {
            let (is_set, _) = self.cap_level_for_rounds.read((vault_address, round_id));
            //assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.cap_level_for_rounds.write((vault_address, round_id), (true, cap_level));
        }
    }
}
