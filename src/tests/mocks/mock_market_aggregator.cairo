#[starknet::interface]
trait IMarketAggregatorSetter<TContractState> {
    fn set_value_without_proof(
        ref self: TContractState, start_date: u64, end_date: u64, avg_base_fee: u256
    ) -> Result<bool, felt252>;


    fn get_value(
        self: @TContractState, start_date: u64, end_date: u64
    ) -> Result<(u256, Span<felt252>), felt252>;
}

// @note Needs store and get value, use structs for the store lookup, value and proof

#[starknet::contract]
mod MockMarketAggregator {
    use starknet::{ContractAddress};

    #[storage]
    struct Storage {
        // (start date, end date) -> avg base fee
        values: LegacyMap<(u64, u64), u256>,
        // (start date, end date, index) -> proof chunk
        // @note First index is the length of the proof
        proofs: LegacyMap<(u64, u64, u32), felt252>,
    }

    #[abi(embed_v0)]
    impl IMarketAggregatorSetterImpl of super::IMarketAggregatorSetter<ContractState> {
        fn get_value(
            self: @ContractState, start_date: u64, end_date: u64
        ) -> Result<(u256, Span<felt252>), felt252> {
            let proof = array![].span();
            Result::Ok((self.values.read((start_date, end_date)), proof))
        }

        fn set_value_without_proof(
            ref self: ContractState, start_date: u64, end_date: u64, avg_base_fee: u256
        ) -> Result<bool, felt252> {
            self.values.write((start_date, end_date), avg_base_fee);
            Result::Ok(true)
        }
    }
}

