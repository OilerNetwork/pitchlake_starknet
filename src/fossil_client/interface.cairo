use starknet::{ContractAddress, StorePacking};
use pitch_lake::vault::interface::{L1Data, L1DataProcessorCallbackReturn};

// *************************************************************************
//                            FOSSIL CLIENT
// *************************************************************************

#[starknet::interface]
trait IFossilClient<TContractState> {
    fn fossil_callback(
        ref self: TContractState, request: Span<felt252>, result: Span<felt252>
    ) -> L1DataProcessorCallbackReturn;
}

// *************************************************************************
//                            PITCH LAKE CLIENT
// *************************************************************************

#[derive(Copy, Drop)]
struct JobRequest {
    // Which vault is this request for
    vault_address: ContractAddress,
    // The timestamp the results are for
    timestamp: u64,
    // 'PITCH_LAKE_V1' (or program hash when proving ?)
    program_id: felt252, // 'PITCH_LAKE_V1'}
    // The riskiness of the vault
    alpha: u128,
    // The strike level of the vault
    k: i128,
}

impl SerdeJobRequest of Serde<JobRequest> {
    fn serialize(self: @JobRequest, ref output: Array<felt252>) {
        self.vault_address.serialize(ref output);
        self.timestamp.serialize(ref output);
        self.program_id.serialize(ref output);
        self.alpha.serialize(ref output);
        self.k.serialize(ref output);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<JobRequest> {
        let vault_address: ContractAddress = (*serialized.at(0))
            .try_into()
            .expect('failed to deserialize vault');
        let timestamp: u64 = (*serialized.at(1))
            .try_into()
            .expect('failed to deserialize timestamp');
        let program_id: felt252 = *serialized.at(2);
        let alpha: u128 = (*serialized.at(3)).try_into().expect('failed to deserialize alpha');
        let k: i128 = (*serialized.at(4)).try_into().expect('failed to deserialize k');
        Option::Some(JobRequest { program_id, vault_address, timestamp, alpha, k })
    }
}

#[derive(Copy, Drop)]
struct FossilResult {
    // TWAP, cap level, reserve price
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
        let cap_level: u128 = (*serialized.at(2)).try_into().expect('failed deserialize cap level');
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
                    cap_level,
                    reserve_price: u256 { low: reserve_price_low, high: reserve_price_high }
                },
                proof
            }
        )
    }
}

