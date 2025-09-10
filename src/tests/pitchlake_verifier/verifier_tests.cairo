use pitch_lake::tests::utils::facades::vault_facade::VaultFacadeTrait;
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running, timeskip_to_settlement_date,
};
use pitch_lake::tests::utils::helpers::general_helpers::to_gwei;
use pitch_lake::tests::utils::helpers::setup::setup_facade;
use pitch_lake::vault::contract::Vault::Errors;
use pitch_lake::vault::interface::{JobRequest, L1Data, VerifierData};

// TODO: Change these after verifier cleanup

#[test]
fn test_job_request_serialization() {
    let job = JobRequest {
        vault_address: 0xbeef.try_into().unwrap(), timestamp: 1234, program_id: 'PITCH_LAKE_V1',
    };
    let mut job_as_span = array![0xbeef, 1234, 'PITCH_LAKE_V1'].span();

    // Test serialize
    let mut serialized: Array<felt252> = array![];
    job.serialize(ref serialized);
    assert_eq!(serialized.span(), job_as_span);
}

#[test]
fn test_job_request_deserialization() {
    let job = JobRequest {
        vault_address: 0xbeef.try_into().unwrap(), timestamp: 1234, program_id: 'PITCH_LAKE_V1',
    };
    let mut job_as_span = array![0xbeef, 1234, 'PITCH_LAKE_V1'].span();

    // Test deserialize
    let deserialized: JobRequest = Serde::deserialize(ref job_as_span)
        .expect('failed to deser job request');
    assert(job == deserialized, 'deserialized does not match');
}

#[test]
fn test_verifier_serialization() {
    let verifier_data = VerifierData {
        reserve_price_start_timestamp: 1000,
        reserve_price_end_timestamp: 2000,
        reserve_price: 3000,
        twap_start_timestamp: 4000,
        twap_end_timestamp: 5000,
        twap_result: 6000,
        max_return_start_timestamp: 7000,
        max_return_end_timestamp: 8000,
        max_return: 9000,
    };
    let mut serialized_span = array![1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000].span();

    // Test serialize
    let mut serialized: Array<felt252> = array![];
    verifier_data.serialize(ref serialized);
    assert_eq!(serialized.span(), serialized_span);
}

#[test]
fn test_verifier_deserialization() {
    let verifier_data = VerifierData {
        reserve_price_start_timestamp: 1000,
        reserve_price_end_timestamp: 2000,
        reserve_price: 3000,
        twap_start_timestamp: 4000,
        twap_end_timestamp: 5000,
        twap_result: 6000,
        max_return_start_timestamp: 7000,
        max_return_end_timestamp: 8000,
        max_return: 9000,
    };
    let mut serialized_span = array![1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000].span();

    // Test deserialize
    let deserialized: VerifierData = Serde::deserialize(ref serialized_span)
        .expect('failed to deser verifier data');
    assert(verifier_data == deserialized, 'deserialized does not match');
}

#[test]
fn test_caller_not_verifier_fossil_callback() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    starknet::testing::set_contract_address('not verifier'.try_into().unwrap());

    let l1_data = L1Data { twap: to_gwei(1111), max_return: 2222, reserve_price: to_gwei(3333) };

    let request = vault.get_request_to_settle_round_serialized();
    let result = vault.generate_custom_job_result_from_l1_data_serialized(l1_data);

    vault.fossil_callback_expect_error(request, result, Errors::CallerNotVerifier);
}
