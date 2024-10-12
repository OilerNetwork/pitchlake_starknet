use starknet::{ContractAddress, StorePacking};

// *************************************************************************
//                            FOSSIL CLIENT
// *************************************************************************

#[starknet::interface]
trait IFossilClient<TContractState> {
    fn fossil_callback(ref self: TContractState, request: Span<felt252>, result: Span<felt252>);
}

// *************************************************************************
//                            PITCH LAKE CLIENT
// *************************************************************************

#[derive(Copy, Drop, Serde)]
struct JobRequest {
    // Identifiers
    program_id: felt252, // 'PITCH_LAKE_V1'
    vault_address: ContractAddress, // Which vault is this request for
    // Timestamp
    timestamp: u64, // Timestamp of the request computed
}

#[derive(Copy, Drop, Serde)]
struct FossilResult {
    l1_data: L1Data, // Results of the computation
    proof: Span<felt252>, // Place holder for proof data
}

#[derive(Default, Copy, Drop, Serde, PartialEq, starknet::Store)]
struct L1Data {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
}

