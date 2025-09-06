#[starknet::contract]
mod FossilClient {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};

    use openzeppelin_access::ownable::OwnableComponent;

    use pitch_lake::library::constants::PROGRAM_ID;
    use pitch_lake::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
    use pitch_lake::option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
    use pitch_lake::fossil_client::interface::{JobRequest, FossilResult, L1Data, IFossilClient,};

    // *************************************************************************
    //                              COMPONENTS
    // *************************************************************************

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        verifier: ContractAddress,
        is_verifier_set: bool,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    // *************************************************************************
    //                              ERRORS
    // *************************************************************************

    mod Errors {
        const VerifierAlreadySet: felt252 = 'Verifier already set';
        const CallerNotVerifier: felt252 = 'Caller not the verifier';
        const FailedToDeserializeRequest: felt252 = 'Failed to deserialize request';
        const FailedToDeserializeResult: felt252 = 'Failed to deserialize result';
        const InvalidRequest: felt252 = 'Invalid request';
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }

    // *************************************************************************
    //                              EVENTS
    // *************************************************************************

    #[event]
    #[derive(PartialEq, Drop, starknet::Event)]
    enum Event {
        FossilCallbackSuccess: FossilCallbackSuccess,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
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
        fn get_verifier(self: @ContractState) -> ContractAddress {
            self.verifier.read()
        }

        fn is_verifier_set(self: @ContractState) -> bool {
            self.is_verifier_set.read()
        }

        fn initialize_verifier(ref self: ContractState, verifier: ContractAddress) {
            assert(!self.is_verifier_set.read(), Errors::VerifierAlreadySet);
            self.ownable.assert_only_owner();
            self.verifier.write(verifier);
            self.is_verifier_set.write(true);
        }

        fn fossil_callback(
            ref self: ContractState, mut job_request: Span<felt252>, mut result: Span<felt252>
        ) {
            // Deserialize job_request & result
            let JobRequest { vault_address, timestamp, program_id } = Serde::deserialize(
                ref job_request
            )
                .expect(Errors::FailedToDeserializeRequest);

            let FossilResult { l1_data, proof: _ } = Serde::deserialize(ref result)
                .expect(Errors::FailedToDeserializeResult);

            // Validate the job_request
            assert(program_id == PROGRAM_ID, Errors::InvalidRequest);
            assert(timestamp.is_non_zero(), Errors::InvalidRequest);

            // Verify caller is the fossil processor
            // @note Once proving is implemented, remove caller assertion and verify inputs
            // (timestamp & program id)/outputs (l1 data)/proof

            // @note Skipping for now for testnet testing
            assert(get_caller_address() == self.verifier.read(), Errors::CallerNotVerifier);

            // Relay L1 data to the vault
            IVaultDispatcher { contract_address: vault_address }
                .fossil_client_callback(l1_data, timestamp);

            // Emit callback success event
            self
                .emit(
                    Event::FossilCallbackSuccess(
                        FossilCallbackSuccess { vault_address, l1_data, timestamp }
                    )
                );
        }
    }
}

