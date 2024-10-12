#[starknet::contract]
mod FossilClient {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};

    use pitch_lake::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
    use pitch_lake::option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
    use pitch_lake::fossil_client::interface::{JobRequest, FossilResult, L1Data, IFossilClient,};

    // *************************************************************************
    //                              Constants
    // *************************************************************************

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        fossil_processor: ContractAddress,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState, fossil_processor: ContractAddress) {
        self.fossil_processor.write(fossil_processor);
        // save program id/hash ?

    }
    // *************************************************************************
    //                              ERRORS
    // *************************************************************************

    mod Errors {
        const CallerNotFossilProcessor: felt252 = 'Caller not the fossil processor';
        const FailedToDeserializeRequest: felt252 = 'Failed to deserialize request';
        const FailedToDeserializeResult: felt252 = 'Failed to deserialize result';
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
        fn fossil_callback(ref self: ContractState, request: Span<felt252>, result: Span<felt252>) {
            // Verify caller is the fossil processor
            assert(
                get_caller_address() == self.fossil_processor.read(),
                Errors::CallerNotFossilProcessor
            );

            // Deserialize request & result
            let mut raw_request = request;
            let mut raw_result = result;

            let JobRequest { vault_address, timestamp, program_id: _ } = Serde::deserialize(
                ref raw_request
            )
                .expect(Errors::FailedToDeserializeRequest);
            let FossilResult { l1_data, proof: _ } = Serde::deserialize(ref raw_result)
                .expect(Errors::FailedToDeserializeResult);

            // Once proving is implemented, remove caller assertion and verify inputs (timestamp &
            // program id)/outputs (l1 data)/proof

            // Relay the L1 data to the correct vault
            IVaultDispatcher { contract_address: vault_address }
                .fossil_client_callback(l1_data, timestamp);

            // Emit event
            self
                .emit(
                    Event::FossilCallbackSuccess(
                        FossilCallbackSuccess { vault_address, l1_data, timestamp }
                    )
                );
        }
    }
}

