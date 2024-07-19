mod Errors {
    const VALUE_NOT_SET: felt252 = 'Value not set in storage';
    const VALUE_ALREADY_SET: felt252 = 'Value already set in storage';
}

mod Identifiers {
    const BLOCK_TIMESTAMP: felt252 = 'BLOCK TIMESTAMP';
    const BLOCK_NUMBER: felt252 = 'BLOCK NUMBER';
}

#[starknet::contract]
mod MarketAggregator {
    use starknet::{ContractAddress, StorePacking};
    use super::{Identifiers::{BLOCK_TIMESTAMP, BLOCK_NUMBER}, Errors};
    use super::super::interface::{IMarketAggregator, IMarketAggregatorSetter};


    #[storage]
    struct Storage {
        cap_levels: LegacyMap<u64, (bool, u16)>,
        reserve_prices: LegacyMap<u64, (bool, u256)>,
        // TWAP for base fee over a period of time
        TWAPs: LegacyMap<(felt252, u64, u64), (bool, u256)>,
    }

    #[abi(embed_v0)]
    impl MarketAggregatorImpl of IMarketAggregator<ContractState> {
        fn get_cap_level(self: @ContractState, date: u64) -> Result<u16, felt252> {
            let (is_set, cap_level) = self.cap_levels.read((date));
            match is_set {
                true => Result::Ok(cap_level),
                false => Result::Err(Errors::VALUE_NOT_SET)
            }
        }

        fn get_reserve_price(self: @ContractState, date: u64) -> Result<u256, felt252> {
            let (is_set, reserve_price) = self.reserve_prices.read((date));
            match is_set {
                true => Result::Ok(reserve_price),
                false => Result::Err(Errors::VALUE_NOT_SET)
            }
        }


        fn get_TWAP_over_block_timestamps(
            self: @ContractState, block_timestamp_from: u64, block_timestamp_to: u64
        ) -> Result<u256, felt252> {
            let (is_set, TWAP) = self
                .TWAPs
                .read((BLOCK_TIMESTAMP, block_timestamp_from, block_timestamp_to));

            match is_set {
                true => Result::Ok(TWAP),
                false => Result::Err(Errors::VALUE_NOT_SET)
            }
        }

        fn get_TWAP_over_block_numbers(
            self: @ContractState, block_number_from: u64, block_number_to: u64
        ) -> Result<u256, felt252> {
            let (is_set, TWAP) = self
                .TWAPs
                .read((BLOCK_NUMBER, block_number_from, block_number_to));
            match is_set {
                true => Result::Ok(TWAP),
                false => Result::Err(Errors::VALUE_NOT_SET)
            }
        }
    }

    #[abi(embed_v0)]
    impl MarketAggregatorSetterImpl of IMarketAggregatorSetter<ContractState> {
        fn set_cap_level(ref self: ContractState, date: u64, cap_level: u16) {
            let (is_set, _) = self.cap_levels.read((date));
            assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.cap_levels.write(date, (true, cap_level));
        }
        fn set_reserve_price(ref self: ContractState, date: u64, reserve_price: u256) {
            let (is_set, _) = self.reserve_prices.read((date));
            assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.reserve_prices.write(date, (true, reserve_price));
        }

        fn set_TWAP_over_block_timestamps(ref self: ContractState, from: u64, to: u64, TWAP: u256) {
            let (is_set, _) = self.TWAPs.read((BLOCK_TIMESTAMP, from, to));
            assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.TWAPs.write((BLOCK_TIMESTAMP, from, to), (true, TWAP));
        }

        fn set_TWAP_over_block_numbers(ref self: ContractState, from: u64, to: u64, TWAP: u256) {
            let (is_set, _) = self.TWAPs.read((BLOCK_NUMBER, from, to));
            assert(!is_set, Errors::VALUE_ALREADY_SET);
            self.TWAPs.write((BLOCK_NUMBER, from, to), (true, TWAP));
        }
    }
}
