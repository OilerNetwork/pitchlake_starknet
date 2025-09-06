use pitch_lake::fossil_client::interface::{JobRequest, VerifierData};

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
        start_timestamp: 1000,
        end_timestamp: 2000,
        reserve_price: 3000,
        floating_point_tolerance: 10,
        reserve_price_tolerance: 20,
        twap_tolerance: 30,
        gradient_tolerance: 40,
        twap_result: 5000,
        max_return: 6000
    };
    let mut serialized_span = array![1000, 2000, 3000, 10, 20, 30, 40, 5000, 6000].span();

    // Test serialize
    let mut serialized: Array<felt252> = array![];
    verifier_data.serialize(ref serialized);
    assert_eq!(serialized.span(), serialized_span);
}

#[test]
fn test_verifier_deserialization() {
    let verifier_data = VerifierData {
        start_timestamp: 1000,
        end_timestamp: 2000,
        reserve_price: 3000,
        floating_point_tolerance: 10,
        reserve_price_tolerance: 20,
        twap_tolerance: 30,
        gradient_tolerance: 40,
        twap_result: 5000,
        max_return: 6000
    };
    let mut serialized_span = array![1000, 2000, 3000, 10, 20, 30, 40, 5000, 6000].span();

    // Test deserialize
    let deserialized: VerifierData = Serde::deserialize(ref serialized_span)
        .expect('failed to deser verifier data');
    assert(verifier_data == deserialized, 'deserialized does not match');
}

