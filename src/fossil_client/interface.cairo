use starknet::{ContractAddress, StorePacking};

// *************************************************************************
//                            FOSSIL CLIENT
// *************************************************************************

#[derive(Copy, Drop, Serde)]
struct FossilRequest {
    program_hash: felt252, // Axiom uses querySchema by reading the circuit
    program_inputs: Span<felt252>, // Pitch Lake will pass timestamp
    context: Span<
        felt252
    >, // Used by client to understand the request further (Axiom used extraData)
}

#[derive(Copy, Drop, Serde)]
struct FossilResult {
    program_outputs: Span<felt252>,
    proof: Span<felt252>,
}

#[starknet::interface]
trait IFossilClient<TContractState> {
    fn fulfill_request(ref self: TContractState, request: FossilRequest, result: FossilResult);
}
// *************************************************************************
//                            PITCH LAKE CLIENT
// *************************************************************************

#[derive(Default, Copy, Drop, Serde, PartialEq, starknet::Store)]
struct L1Data {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
}

#[starknet::interface]
trait IPitchLakeClient<TContractState> {//    fn get_data_for_vault_round(
//        self: @TContractState, vault_address: ContractAddress, round_id: u256
//    ) -> Option<L1Data>;
}
