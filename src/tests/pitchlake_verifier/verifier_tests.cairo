use pitch_lake::vault::contract::Vault::Errors;
use pitch_lake::tests::utils::helpers::setup::{PITCHLAKE_VERIFIER};
//use pitch_lake::tests::utils::facades::fossil_client_facade::{
//    FossilClientFacade, FossilClientFacadeTrait
//};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_access::ownable::{OwnableComponent::Errors as OErrors};
use pitch_lake::{
    library::{eth::Eth, constants::PROGRAM_ID}, vault::interface::{JobRequest, VerifierData},
    vault::{
        contract::Vault::L1Data,
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait,
            IVaultSafeDispatcherTrait,
        }
    },
    option_round::contract::OptionRound::Errors as rErrors, option_round::interface::PricingData,
    tests::{
        utils::{
            helpers::{
                general_helpers::{
                    get_portion_of_amount, create_array_linear, create_array_gradient,
                    get_erc20_balances, sum_u256_array, to_gwei,
                },
                event_helpers::{
                    clear_event_logs, assert_event_option_settle, assert_event_transfer,
                    assert_no_events_left, pop_log, assert_event_option_round_deployed_single,
                    assert_event_option_round_deployed,
                },
                accelerators::{
                    timeskip_to_settlement_date, accelerate_to_auctioning, accelerate_to_running,
                    accelerate_to_settled, accelerate_to_auctioning_custom,
                    accelerate_to_running_custom
                },
                setup::{
                    deploy_vault_with_events, setup_facade, setup_test_auctioning_providers,
                    setup_test_running, AUCTION_DURATION, ROUND_TRANSITION_DURATION, ROUND_DURATION
                },
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get, liquidity_provider_3, liquidity_provider_4,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{
                    l1_data_to_verifier_data_serialized, l1_data_to_verifier_data, VaultFacade,
                    VaultFacadeTrait
                },
                option_round_facade::{OptionRoundState, OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};

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
        max_return: 9000
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
        max_return: 9000
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
    let result = vault.generate_job_result_serialized_from_l1_data_custom(l1_data);

    vault.fossil_callback_expect_error(request, result, Errors::CallerNotVerifier);
}

