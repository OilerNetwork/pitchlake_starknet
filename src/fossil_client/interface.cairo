use starknet::{ContractAddress, StorePacking};

// *************************************************************************
//                            FOSSIL CLIENT
// *************************************************************************

#[starknet::interface]
trait IFossilClient<TContractState> {
    // Set the verifier address, can only be called once
    fn initialize_verifier(ref self: TContractState, verifier: ContractAddress);

    // Called by Pitchlake Verifier
    fn fossil_callback(ref self: TContractState, job_request: Span<felt252>, result: Span<felt252>);
}

// *************************************************************************
//                            PITCH LAKE CLIENT
// *************************************************************************

// Job request sent to Fossil
// vault_address: Which vault is the data for
// timestamp: Upper bound timestamp of gas data used in data calculation
// program_id: 'PITCH_LAKE_V1'
#[derive(Copy, Drop, PartialEq)]
struct JobRequest {
    vault_address: ContractAddress,
    timestamp: u64,
    program_id: felt252,
}

// Fossil job results (args, data and tolerances)
#[derive(Copy, Drop, PartialEq)]
struct VerifierData {
    pub start_timestamp: u64,
    pub end_timestamp: u64,
    pub reserve_price: felt252,
    pub floating_point_tolerance: felt252,
    pub reserve_price_tolerance: felt252,
    pub twap_tolerance: felt252,
    pub gradient_tolerance: felt252,
    pub twap_result: felt252,
    pub max_return: felt252,
}

// JobRequest <-> Array<felt252>
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

// VerifierData <-> Array<felt252>
impl SerdeVerifierData of Serde<VerifierData> {
    fn serialize(self: @VerifierData, ref output: Array<felt252>) {
        self.start_timestamp.serialize(ref output);
        self.end_timestamp.serialize(ref output);
        self.reserve_price.serialize(ref output);
        self.floating_point_tolerance.serialize(ref output);
        self.reserve_price_tolerance.serialize(ref output);
        self.twap_tolerance.serialize(ref output);
        self.gradient_tolerance.serialize(ref output);
        self.twap_result.serialize(ref output);
        self.max_return.serialize(ref output);
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<VerifierData> {
        let start_timestamp: u64 = (*serialized.at(0))
            .try_into()
            .expect('failed to deser. start timestmp');
        let end_timestamp: u64 = (*serialized.at(1))
            .try_into()
            .expect('failed to deser. end timestamp');
        let reserve_price: felt252 = *serialized.at(2);
        let floating_point_tolerance: felt252 = *serialized.at(3);
        let reserve_price_tolerance: felt252 = *serialized.at(4);
        let twap_tolerance: felt252 = *serialized.at(5);
        let gradient_tolerance: felt252 = *serialized.at(6);
        let twap_result: felt252 = *serialized.at(7);
        let max_return: felt252 = *serialized.at(8);

        Option::Some(
            VerifierData {
                start_timestamp,
                end_timestamp,
                reserve_price,
                floating_point_tolerance,
                reserve_price_tolerance,
                twap_tolerance,
                gradient_tolerance,
                twap_result,
                max_return
            }
        )
    }
}

/// Old

#[derive(Copy, Drop)]
struct FossilResult {
    // TWAP, volatility, reserve price
    l1_data: L1Data,
    // Place holder for proof data
    proof: Span<felt252>,
}

// Fix this as per fossilmonorepo
impl SerdeFossilResult of Serde<FossilResult> {
    fn serialize(self: @FossilResult, ref output: Array<felt252>) {
        self.l1_data.serialize(ref output);
        self.proof.serialize(ref output);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<FossilResult> {
        let twap_low: u128 = (*serialized.at(0)).try_into().expect('failed deserialize twap');
        let twap_high: u128 = (*serialized.at(1)).try_into().expect('failed deserialize twap');
        let max_return: u128 = (*serialized.at(2))
            .try_into()
            .expect('failed deserialize max_return');
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
                    max_return,
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
    max_return: u128,
    reserve_price: u256,
}

