use pitch_lake::fossil_client::interface::{JobRequest, VerifierData};
use pitch_lake::fossil_client::contract::FossilClient::Errors;
use pitch_lake::tests::utils::helpers::setup::{deploy_fossil_client};
use pitch_lake::tests::utils::helpers::setup::{FOSSIL_CLIENT_OWNER, PITCHLAKE_VERIFIER};
use pitch_lake::tests::utils::facades::fossil_client_facade::{
    FossilClientFacade, FossilClientFacadeTrait
};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_access::ownable::{OwnableComponent::Errors as OErrors};

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

#[test]
fn test_deploy_verifier() {
    let fossil_client = deploy_fossil_client();

    assert_eq!(fossil_client.is_verifier_set(), false);
    assert_eq!(fossil_client.get_verifier().into(), 0);
}

#[test]
fn test_initialize_verifier() {
    let fossil_client = deploy_fossil_client();

    fossil_client.initialize_verifier(0xb00b.try_into().unwrap());

    assert_eq!(fossil_client.is_verifier_set(), true);
    assert_eq!(fossil_client.get_verifier().into(), 0xb00b);
}

#[test]
fn test_initialize_verifier_only_once() {
    let fossil_client = deploy_fossil_client();

    fossil_client.initialize_verifier(0xb00b.try_into().unwrap());
    fossil_client
        .initialize_verifier_expect_error(0xc0de.try_into().unwrap(), Errors::VerifierAlreadySet);

    assert_eq!(fossil_client.is_verifier_set(), true);
    assert_eq!(fossil_client.get_verifier(), 0xb00b.try_into().unwrap());
}

#[test]
fn test_initialize_verifier_only_owner() {
    let fossil_client = deploy_fossil_client();

    starknet::testing::set_contract_address(0xdead.try_into().unwrap());
    fossil_client.initialize_verifier_expect_error(0xb00b.try_into().unwrap(), OErrors::NOT_OWNER);

    assert_eq!(fossil_client.is_verifier_set(), false);
    assert_eq!(fossil_client.get_verifier().into(), 0);
}

#[test]
fn test_caller_not_verifier_fossil_callback() {
    let fossil_client = deploy_fossil_client();

    // Set verifier
    fossil_client.initialize_verifier(0xdead.try_into().unwrap());

    // Call from non-verifier
    starknet::testing::set_contract_address(0xbeef.try_into().unwrap());
    fossil_client
        .fossil_callback_expect_error(array![].span(), array![].span(), Errors::CallerNotVerifier);
}

