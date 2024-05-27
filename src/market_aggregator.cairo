#[starknet::interface]
trait IMarketAggregator<TContractState> {
    fn set_value(
        ref self: TContractState,
        start_date: u64,
        end_date: u64,
        avg_base_fee: u256,
        proof: Span<felt252>
    ) -> Result<bool, felt252>;

    fn get_value(
        self: @TContractState, start_date: u64, end_date: u64,
    ) -> Result<(u256, Span<felt252>), felt252>;
}

#[starknet::contract]
mod MarketAggregator {
    use starknet::{ContractAddress, StorePacking};
    use starknet::contract_address::ContractAddressZeroable;
    #[storage]
    struct Storage {
        // (start date, end date) -> avg base fee
        values: LegacyMap<(u64, u64), u256>,
        // (start date, end date, index) -> proof chunk
        // @note First index is the length of the proof
        proofs: LegacyMap<(u64, u64, u32), felt252>,
    }

    #[abi(embed_v0)]
    impl IMarketAggregatorImpl of super::IMarketAggregator<ContractState> {
        fn get_value(
            self: @ContractState, start_date: u64, end_date: u64,
        ) -> Result<(u256, Span<felt252>), felt252> {
            // Assert there is a proof for this lookup (the value exists)
            assert(self.proofs.read((start_date, end_date, 0)) != 0, 'Value not set');
            // Build helper to create span of proof using proof length (found from reading proofs at slot 0)
            let proof = array![
                self.proofs.read((start_date, end_date, 1)),
                self.proofs.read((start_date, end_date, 2))
            ]
                .span();
            let avg_base_fee = self.values.read((start_date, end_date));

            Result::Ok((avg_base_fee, proof))
        }

        fn set_value(
            ref self: ContractState,
            start_date: u64,
            end_date: u64,
            avg_base_fee: u256,
            proof: Span<felt252>,
        ) -> Result<bool, felt252> {
            // Check lookup (derived from value) is not set yet
            // Verify proof of value
            // Set value and proof using lookup
            Result::Ok(true)
        }
    }
}
