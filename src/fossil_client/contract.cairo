#[starknet::contract]
mod FossilClient {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};

    use pitch_lake::library::constants::PROGRAM_ID;
    use pitch_lake::vault::interface::{
        IVaultDispatcher, IVaultDispatcherTrait, L1DataCallbackReturn, L1Data,
    };
    use pitch_lake::option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
    use pitch_lake::fossil_client::interface::{JobRequest, FossilResult, IFossilClient};

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        fossil_processor: ContractAddress,
    }

    // *************************************************************************
    //                              ERRORS
    // *************************************************************************

    mod Errors {
        const CallerNotFossilProcessor: felt252 = 'Caller not the fossil processor';
        const FailedToDeserializeRequest: felt252 = 'Failed to deserialize request';
        const FailedToDeserializeResult: felt252 = 'Failed to deserialize result';
        const InvalidRequest: felt252 = 'Invalid request';
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState, fossil_processor: ContractAddress) {
        self.fossil_processor.write(fossil_processor);
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************

    #[event]
    #[derive(Serde, PartialEq, Drop, starknet::Event)]
    enum Event {
        FossilCallbackSuccess: FossilCallbackSuccess,
    }

    #[derive(Serde, Drop, starknet::Event, PartialEq)]
    struct FossilCallbackSuccess {
        vault_address: ContractAddress,
        l1_data: L1Data,
        timestamp: u64,
    }

    // *************************************************************************
    //                            IMPLEMENTATIONS
    // *************************************************************************

    #[abi(embed_v0)]
    impl FossilClientImpl of IFossilClient<ContractState> {
        fn fossil_callback(
            ref self: ContractState, mut request: Span<felt252>, mut result: Span<felt252>
        ) -> L1DataCallbackReturn {
            // Deserialize request & result
            let JobRequest { vault_address, timestamp, program_id } = Serde::deserialize(
                ref request
            )
                .expect(Errors::FailedToDeserializeRequest);

            let FossilResult { l1_data, proof: _ } = Serde::deserialize(ref result)
                .expect(Errors::FailedToDeserializeResult);

            // Validate the request
            assert(program_id == PROGRAM_ID, Errors::InvalidRequest);
            assert(timestamp.is_non_zero(), Errors::InvalidRequest);

            // Verify caller is the fossil processor
            // @note Once proving is implemented, remove caller assertion and verify inputs
            // (timestamp & program id)/outputs (l1 data)/proof

            // @note Skipping for now for testnet testing
            assert(
                get_caller_address() == self.fossil_processor.read(),
                Errors::CallerNotFossilProcessor
            );

            // Relay L1 data to the vault
            IVaultDispatcher { contract_address: vault_address }
                .l1_data_processor_callback(l1_data, timestamp)
        }
    }
}

