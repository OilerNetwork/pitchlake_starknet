use starknet::{ContractAddress, StorePacking};

// *************************************************************************
//                            FOSSIL CLIENT
// *************************************************************************

#[starknet::interface]
trait IFossilClient<TContractState> {
    fn fossil_callback(ref self: TContractState, job_request: Span<felt252>, result: Span<felt252>);
}

// *************************************************************************
//                            PITCH LAKE CLIENT
// *************************************************************************

#[derive(Copy, Drop)]
struct JobRequest {
    vault_address: ContractAddress, // Which vault is this request for
    // The timestamp the results are for
    timestamp: u64,
    // 'PITCH_LAKE_V1' (or program hash when proving ?)
    program_id: felt252, // 'PITCH_LAKE_V1'}
}

impl SerdeJobRequest of Serde<JobRequest> {
    fn serialize(self: @JobRequest, ref output: Array<felt252>) {
        self.vault_address.serialize(ref output);
        self.timestamp.serialize(ref output);
        self.program_id.serialize(ref output);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<JobRequest> {
        let vault_address: ContractAddress = (*serialized.at(0))
            .try_into()
            .expect('failed to deserialize vault');
        let timestamp: u64 = (*serialized.at(1))
            .try_into()
            .expect('failed to deserialize timestamp');
        let program_id: felt252 = *serialized.at(2);
        Option::Some(JobRequest { program_id, vault_address, timestamp })
    }
}

#[derive(Copy, Drop)]
struct FossilResult {
    // TWAP, volatility, reserve price
    l1_data: L1Data,
    // Place holder for proof data
    proof: Span<felt252>,
}

impl SerdeFossilResult of Serde<FossilResult> {
    fn serialize(self: @FossilResult, ref output: Array<felt252>) {
        self.l1_data.serialize(ref output);
        self.proof.serialize(ref output);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<FossilResult> {
        let twap_low: u128 = (*serialized.at(0)).try_into().expect('failed deserialize twap');
        let twap_high: u128 = (*serialized.at(1)).try_into().expect('failed deserialize twap');
        let volatility: u128 = (*serialized.at(2))
            .try_into()
            .expect('failed deserialize volatility');
        let reserve_price_low: u128 = (*serialized.at(3))
            .try_into()
            .expect('failed deserialize reserve');
        let reserve_price_high: u128 = (*serialized.at(4))
            .try_into()
            .expect('failed deserialize reserve');
        let proof: Span<felt252> = serialized.slice(5, serialized.len() - 5);
        Option::Some(
            FossilResult {
                l1_data: L1Data {
                    twap: u256 { low: twap_low, high: twap_high },
                    volatility,
                    reserve_price: u256 { low: reserve_price_low, high: reserve_price_high }
                },
                proof
            }
        )
    }
}

#[derive(Default, Copy, Drop, Serde, PartialEq, starknet::Store)]
struct L1Data {
    twap: u256,
    volatility: u128,
    reserve_price: u256,
}

