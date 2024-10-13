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
    // 'PITCH_LAKE_V1' (or program hash when proving ?)
    program_id: felt252, // 'PITCH_LAKE_V1'
    // The vault the request is for
    vault_address: ContractAddress, // Which vault is this request for
    // The timestamp the results are for
    timestamp: u64,
}

#[derive(Copy, Drop, Serde)]
struct FossilResult {
    // TWAP, volatility, reserve price
    l1_data: L1Data,
    // Place holder for proof data
    proof: Span<felt252>,
}

#[derive(Default, Copy, Drop, Serde, PartialEq, starknet::Store)]
struct L1Data {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
}

