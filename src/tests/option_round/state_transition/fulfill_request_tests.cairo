use starknet::{ContractAddress, contract_address_const, testing::set_contract_address};
use pitch_lake::{
    vault::interface::{VaultType}, fossil_client::interface::{L1Data, JobRequest, FossilResult},
    vault::contract::Vault, vault::contract::Vault::Errors as vErrors,
    fossil_client::contract::FossilClient::Errors as fErrors, option_round::interface::PricingData,
    library::pricing_utils,
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, timeskip_and_settle_round
                },
                setup::{setup_facade, FOSSIL_PROCESSOR},
                event_helpers::{assert_fossil_callback_success_event}, general_helpers::{to_gwei},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                fossil_client_facade::{FossilClientFacade, FossilClientFacadeTrait},
            },
        },
    }
};

fn get_mock_result() -> FossilResult {
    FossilResult {
        proof: array![].span(),
        l1_data: L1Data { twap: to_gwei(10), volatility: 5000, reserve_price: to_gwei(2) }
    }
}

// Test only the fossil processor can call the fossil callback
#[test]
#[available_gas(50000000)]
fn test_only_fossil_processor_can_call_fossil_callback() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_start_auction().serialize(ref request_serialized);
    get_mock_result().serialize(ref result_serialized);

    // Should fail
    set_contract_address(contract_address_const::<'NOT IT'>());
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result_serialized.span(), fErrors::CallerNotFossilProcessor
        );

    // Should not fail
    fossil_client.fossil_callback(request_serialized.span(), result_serialized.span());
}

// Test only fossil client can call fossil client callback
#[test]
#[available_gas(50000000)]
fn test_only_fossil_client_can_call_fossil_client_callback() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    let l1_data = L1Data { twap: to_gwei(10), volatility: 1234, reserve_price: to_gwei(2) };

    let timestamp = current_round.get_auction_start_date();

    // Should fail
    set_contract_address(contract_address_const::<'NOT IT'>());
    vault.fossil_client_callback_expect_error(l1_data, timestamp, vErrors::CallerNotFossilClient);

    // Should not fail
    vault.fossil_client_callback(l1_data, timestamp);
}

// Test invalid Fossil request fails
#[test]
#[available_gas(50000000)]
fn test_invalid_fossil_request_fails() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_start_auction().serialize(ref request_serialized);
    get_mock_result().serialize(ref result_serialized);

    // Should fail
    set_contract_address(FOSSIL_PROCESSOR());
    let _ = request_serialized.pop_front();
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result_serialized.span(), fErrors::FailedToDeserializeRequest
        );
}

// Test invalid Fossil result fails
#[test]
#[available_gas(50000000)]
fn test_invalid_fossil_result_fails() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_start_auction().serialize(ref request_serialized);
    get_mock_result().serialize(ref result_serialized);

    // Should fail
    set_contract_address(FOSSIL_PROCESSOR());
    let _ = result_serialized.pop_front();
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result_serialized.span(), fErrors::FailedToDeserializeResult
        );
}

// Test callback event
#[test]
#[available_gas(50000000)]
fn test_callback_event() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_start_auction().serialize(ref request_serialized);
    let mock_result: FossilResult = get_mock_result();
    mock_result.serialize(ref result_serialized);

    fossil_client.fossil_callback(request_serialized.span(), result_serialized.span());
    assert_fossil_callback_success_event(
        vault.get_fossil_client_facade().contract_address,
        vault.contract_address(),
        mock_result.l1_data,
        current_round.get_deployment_date()
    );
}

// Test successfull callback sets the pricing data for the first round
#[test]
#[available_gas(50000000)]
fn test_callback_sets_pricing_data_for_first_round() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let fossil_client = vault.get_fossil_client_facade();

    // Fossil API callback
    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_start_auction().serialize(ref request_serialized);
    let mock_result = get_mock_result();
    mock_result.serialize(ref result_serialized);
    fossil_client.fossil_callback(request_serialized.span(), result_serialized.span());

    let L1Data { twap, volatility, reserve_price } = mock_result.l1_data;
    let strike_price = pricing_utils::calculate_strike_price(
        vault.get_vault_type(), twap, volatility
    );
    let cap_level = pricing_utils::calculate_cap_level(vault.get_alpha(), volatility);

    assert_eq!(current_round.get_strike_price(), strike_price);
    assert_eq!(current_round.get_cap_level(), cap_level);
    assert_eq!(current_round.get_reserve_price(), reserve_price);
}

// Test successfull callback can update the pricing data while Open if in range
#[test]
#[available_gas(50000000)]
fn test_callback_updates_pricing_data_if_in_bounds_Open() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let fossil_client = vault.get_fossil_client_facade();

    // Fossil API callback
    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_start_auction().serialize(ref request_serialized);
    let mock_result = get_mock_result();
    mock_result.serialize(ref result_serialized);
    fossil_client.fossil_callback(request_serialized.span(), result_serialized.span());

    let L1Data { twap, volatility, reserve_price } = mock_result.l1_data;
    let strike_price = pricing_utils::calculate_strike_price(
        vault.get_vault_type(), twap, volatility
    );
    let cap_level = pricing_utils::calculate_cap_level(vault.get_alpha(), volatility);

    assert_eq!(current_round.get_strike_price(), strike_price);
    assert_eq!(current_round.get_cap_level(), cap_level);
    assert_eq!(current_round.get_reserve_price(), reserve_price);

    // Fossil API callback with new data
    let mut request_serialized = array![];
    let mut result_serialized = array![];
    let mut request = vault.get_request_to_start_auction();
    let mut result = get_mock_result();

    let new_data = L1Data { twap: to_gwei(1000), volatility: 10000, reserve_price: to_gwei(1000), };
    result.l1_data = new_data;
    request.timestamp = current_round.get_auction_start_date();

    request.serialize(ref request_serialized);
    result.serialize(ref result_serialized);

    fossil_client.fossil_callback(request_serialized.span(), result_serialized.span());

    let strike_price = pricing_utils::calculate_strike_price(
        vault.get_vault_type(), new_data.twap, new_data.volatility
    );
    let cap_level = pricing_utils::calculate_cap_level(vault.get_alpha(), new_data.volatility);

    assert_eq!(current_round.get_strike_price(), strike_price);
    assert_eq!(current_round.get_cap_level(), cap_level);
    assert_eq!(current_round.get_reserve_price(), new_data.reserve_price);
}


// Test callbacks fail if round is Auctioning
#[test]
#[available_gas(50000000)]
fn test_callback_fails_if_requests_not_accepted() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_settle_round().serialize(ref request_serialized);
    get_mock_result().serialize(ref result_serialized);

    // Should fail
    accelerate_to_auctioning(ref vault);
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result_serialized.span(), vErrors::L1DataNotAcceptedNow
        );
}

// @note todo Add test for default data set failing

// Test empty L1 data is not accepted
#[test]
#[available_gas(50000000)]
fn test_default_l1_data_fails() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result_serialized = array![];
    vault.get_request_to_settle_round().serialize(ref request_serialized);

    let mut result = get_mock_result();
    result.l1_data = Default::default();
    result.serialize(ref result_serialized);

    // Should fail
    accelerate_to_auctioning(ref vault);
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result_serialized.span(), vErrors::InvalidL1Data
        );
}

// Test callback to start a round fails if out of range
#[test]
#[available_gas(50000000)]
fn test_callback_out_of_range_fails_Open() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let fossil_client = vault.get_fossil_client_facade();

    // Starting the round
    let request = vault.get_request_to_start_auction();
    let result = get_mock_result();

    let invalid_req1 = JobRequest {
        timestamp: request.timestamp - 1,
        vault_address: request.vault_address,
        program_id: request.program_id
    };
    let invalid_req2 = JobRequest {
        timestamp: current_round.get_auction_start_date() + 1,
        vault_address: request.vault_address,
        program_id: request.program_id
    };

    // Both should fail
    let mut request1_serialized = array![];
    let mut request2_serialized = array![];
    let mut result_serialized = array![];

    result.serialize(ref result_serialized);
    invalid_req1.serialize(ref request1_serialized);
    invalid_req2.serialize(ref request2_serialized);

    fossil_client
        .fossil_callback_expect_error(
            request1_serialized.span(), result_serialized.span(), vErrors::L1DataOutOfRange
        );
    fossil_client
        .fossil_callback_expect_error(
            request2_serialized.span(), result_serialized.span(), vErrors::L1DataOutOfRange
        );
}

// Test callback to settle a round fails if out of range
#[test]
#[available_gas(50000000)]
fn test_callback_out_of_range_fails_Running() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    let fossil_client = vault.get_fossil_client_facade();

    // Starting the round
    let request = vault.get_request_to_settle_round();
    let result = get_mock_result();

    let invalid_req1 = JobRequest {
        timestamp: request.timestamp - 1,
        vault_address: request.vault_address,
        program_id: request.program_id
    };
    let invalid_req2 = JobRequest {
        timestamp: current_round.get_option_settlement_date() + 1,
        vault_address: request.vault_address,
        program_id: request.program_id
    };

    // Both should fail
    let mut request1_serialized = array![];
    let mut request2_serialized = array![];
    let mut result_serialized = array![];

    result.serialize(ref result_serialized);
    invalid_req1.serialize(ref request1_serialized);
    invalid_req2.serialize(ref request2_serialized);

    fossil_client
        .fossil_callback_expect_error(
            request1_serialized.span(), result_serialized.span(), vErrors::L1DataOutOfRange
        );
    fossil_client
        .fossil_callback_expect_error(
            request2_serialized.span(), result_serialized.span(), vErrors::L1DataOutOfRange
        );
}


// Test callback settles round and deploys next correctly
#[test]
#[available_gas(50000000)]
fn test_callback_works_as_expected() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    let fossil_client = vault.get_fossil_client_facade();

    // Settling the round
    let mut request_serialized = array![];
    let mut result_serialized = array![];

    let request = vault.get_request_to_settle_round();
    let result = get_mock_result();

    request.serialize(ref request_serialized);
    result.serialize(ref result_serialized);

    fossil_client.fossil_callback(request_serialized.span(), result_serialized.span());

    timeskip_and_settle_round(ref vault);
    let mut next_round = vault.get_current_round();

    let strike = pricing_utils::calculate_strike_price(
        vault.get_vault_type(), result.l1_data.twap, result.l1_data.volatility
    );
    let cap = pricing_utils::calculate_cap_level(vault.get_alpha(), result.l1_data.volatility);

    assert_eq!(current_round.get_settlement_price(), result.l1_data.twap);

    assert_eq!(next_round.get_reserve_price(), result.l1_data.reserve_price,);
    assert_eq!(next_round.get_cap_level(), cap);
    assert_eq!(next_round.get_strike_price(), strike);
}
