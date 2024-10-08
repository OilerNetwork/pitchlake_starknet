#[starknet::contract]
mod PitchLakeClient {
    use starknet::{ContractAddress, StorePacking};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};

    use pitch_lake::fossil_client::interface::{
        FossilRequest, FossilResult, IFossilClient, L1Data, IPitchLakeClient,
    };
    use pitch_lake::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
    use pitch_lake::option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
    // *************************************************************************
    //                              Constants
    // *************************************************************************

    // *************************************************************************
    //                              STORAGE
    // *************************************************************************

    #[storage]
    struct Storage {
        fulfilled_requests: Map<ContractAddress, Map<u256, Option<L1Data>>>,
    }

    // *************************************************************************
    //                              Constructor
    // *************************************************************************

    #[constructor]
    fn constructor(ref self: ContractState) {}

    // *************************************************************************
    //                            IMPLEMENTATIONS
    // *************************************************************************

    #[abi(embed_v0)]
    impl FossilClientImpl of IFossilClient<ContractState> {
        fn fulfill_request(ref self: ContractState, request: FossilRequest, result: FossilResult) {
            //let timestamp: u64 = (*request.program_inputs.at(0)).try_into().expect('no
            //timestamp');

            let context = request.context;
            let vault_address: ContractAddress = (*context.at(0))
                .try_into()
                .expect('no vault address');
            // get current round, if open, check timestamp between deployment date and auction start
            // date, if running check timestamp is option settlemendate minus tolerance
            let vault = IVaultDispatcher { contract_address: vault_address };
            let current_round_id = vault.get_current_round_id();
            let current_round = IOptionRoundDispatcher {
                contract_address: vault.get_round_address(current_round_id)
            };
            let state = current_round.get_state();

            // validate program hash
            // validate program input (timestamp is within bounds)
            // prove data
            // store data
            let mut l1_data_raw = result.program_outputs;
            let l1_data: L1Data = Serde::<L1Data>::deserialize(ref l1_data_raw)
                .expect('Failed to deserialize L1 data');

            assert(l1_data != Default::default(), 'L1 data is empty');

            self
                .fulfilled_requests
                .entry(vault_address)
                .entry(current_round_id)
                .write(Option::Some(l1_data));
        }
    }

    #[abi(embed_v0)]
    impl PitchLakeClientImpl of IPitchLakeClient<ContractState> {//  fn get_data_for_vault_round(
    //      self: @ContractState, vault_address: ContractAddress, round_id: u256
    //  ) -> Option<FossilData> { //
    //      //get data from storage
    //      // return data

    //      self.fulfilled_requests.entry(vault_address).entry(round_id).read()
    //  }
    }

    // *************************************************************************
    //                          INTERNAL FUNCTIONS
    // *************************************************************************

    #[generate_trait]
    impl InternalImpl of PitchLakeClientInternalTrait {
        fn l1_data_to_pricing_data(self: @ContractState, l1_data: L1Data) -> () {}
    }
}

