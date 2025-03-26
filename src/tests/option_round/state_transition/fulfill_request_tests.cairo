use starknet::{
    get_block_timestamp, ContractAddress, contract_address_const,
    testing::{set_contract_address, set_block_timestamp}
};
use pitch_lake::{
    fossil_client::interface::{L1Data, JobRequest, FossilResult, FossilCallbackReturn},
    vault::contract::Vault, vault::contract::Vault::Errors as vErrors,
    fossil_client::contract::FossilClient::Errors as fErrors, option_round::interface::PricingData,
    library::pricing_utils,
    tests::{
        utils::{
            lib::{test_accounts::{liquidity_provider_1,}},
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_auctioning_custom,
                    accelerate_to_running_custom, accelerate_to_running,
                    accelerate_to_settled_custom, timeskip_to_settlement_date, accelerate_to_settled
                },
                setup::{
                    eth_supply_and_approve_all_providers, eth_supply_and_approve_all_bidders,
                    deploy_eth, deploy_vault, setup_facade, FOSSIL_PROCESSOR
                },
                event_helpers::{clear_event_logs, assert_fossil_callback_success_event},
                general_helpers::{to_gwei},
                fossil_client_helpers::{
                    get_mock_l1_data, get_mock_result, get_mock_result_serialized, get_request,
                    get_request_serialized
                }
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                fossil_client_facade::{FossilClientFacade, FossilClientFacadeTrait},
            },
        },
    }
};

use pitch_lake::library::pricing_utils::{calculate_strike_price};
use core::integer::{I128Neg};


// Test only the fossil processor can call the fossil callback

// Fossil Client Contract
// @note Un-ignore this after Fossil processor is setup
#[test]
#[available_gas(50000000)]
fn test_only_fossil_processor_can_call_fossil_callback() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let request = get_request_serialized(ref vault);
    let result = get_mock_result_serialized();

    // Should fail
    set_contract_address(contract_address_const::<'NOT IT'>());
    fossil_client.fossil_callback_expect_error(request, result, fErrors::CallerNotFossilProcessor);

    // Should not fail
    set_contract_address(FOSSIL_PROCESSOR());
    fossil_client.fossil_callback(request, result);
}

// Test invalid request fails
#[test]
#[available_gas(50000000)]
fn test_invalid_request_fails() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let mut request = get_request_serialized(ref vault);
    let result = get_mock_result_serialized();

    // Should fail
    set_contract_address(FOSSIL_PROCESSOR());
    let _ = request.pop_front();
    fossil_client
        .fossil_callback_expect_error(request, result, fErrors::FailedToDeserializeRequest);
}

// Test invalid Fossil result fails
#[test]
#[available_gas(50000000)]
fn test_invalid_result_fails() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let request = get_request_serialized(ref vault);
    let mut result = get_mock_result_serialized();

    // Should fail
    set_contract_address(FOSSIL_PROCESSOR());
    let _ = result.pop_front();
    fossil_client.fossil_callback_expect_error(request, result, fErrors::FailedToDeserializeResult);
}

// Test empty L1 data is not accepted
#[test]
#[available_gas(50000000)]
fn test_default_l1_data_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let fossil_client = vault.get_fossil_client_facade();

    let mut request_serialized = array![];
    let mut result1_serialized = array![];
    //let mut result2_serialized = array![];
    let mut result3_serialized = array![];

    vault.get_request_to_settle_round().serialize(ref request_serialized);

    let mut result1 = get_mock_result();
    //let mut result2 = get_mock_result();
    let mut result3 = get_mock_result();

    result1.l1_data.twap = 0;
    //result2.l1_data.volatility = 0;
    result3.l1_data.reserve_price = 0;

    result1.serialize(ref result1_serialized);
    //result2.serialize(ref result2_serialized);
    result3.serialize(ref result3_serialized);

    // Should fail
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result1_serialized.span(), vErrors::InvalidL1Data
        );
    //fossil_client
    //    .fossil_callback_expect_error(
    //        request_serialized.span(), result2_serialized.span(), vErrors::InvalidL1Data
    //    );
    fossil_client
        .fossil_callback_expect_error(
            request_serialized.span(), result3_serialized.span(), vErrors::InvalidL1Data
        );
}

// Vault Callback for Client

// Test only fossil client can call fossil client callback
#[test]
#[available_gas(50000000)]
fn test_only_fossil_client_can_call_fossil_client_callback() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let mut current_round = vault.get_current_round();
    let l1_data = get_mock_l1_data();
    let settlement_date = current_round.get_option_settlement_date();

    // Should fail
    set_contract_address(contract_address_const::<'NOT IT'>());
    vault
        .fossil_client_callback_expect_error(
            l1_data, settlement_date, vErrors::CallerNotFossilClient
        );

    // Should not fail
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_client_callback(l1_data, settlement_date);
}

// Test successfull callback sets the pricing data for the round
#[test]
#[available_gas(50000000)]
fn test_callback_sets_pricing_data_for_round() {
    let (mut vault, _) = setup_facade();
    let fossil_client = vault.get_fossil_client_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    // Fossil API callback - gets calculation data and settles the round
    let request = get_request_serialized(ref vault);
    let result = get_mock_result_serialized();
    set_contract_address(vault.get_fossil_client_address());
    fossil_client.fossil_callback(request, result);

    // Check pricing data set as expected
    let mut current_round = vault.get_current_round();
    let L1Data { twap, volatility, reserve_price } = get_mock_l1_data();
    let exp_strike_price = pricing_utils::calculate_strike_price(vault.get_strike_level(), twap);
    let exp_cap_level = pricing_utils::calculate_cap_level(
        vault.get_alpha(), vault.get_strike_level(), volatility
    );

    assert_eq!(current_round.get_strike_price(), exp_strike_price);
    assert_eq!(current_round.get_cap_level(), exp_cap_level);
    assert_eq!(current_round.get_reserve_price(), reserve_price);
}

// Test first callback fails if round is round not open
#[test]
#[available_gas(50000000)]
#[ignore]
// @note ignored for now, not sure we need this logic, first round's data can only be set if the
// round is 1 and open, else fails
fn test_first_round_callback_fails_if_now_is_auction_start_date() {
    let eth_address = deploy_eth().contract_address;
    let mut vault = VaultFacade { vault_dispatcher: deploy_vault(1234, 1234, eth_address) };
    let mut current_round = vault.get_current_round();

    let l1_data = get_mock_l1_data();
    let settlement_date = current_round.get_deployment_date();

    set_block_timestamp(current_round.get_auction_start_date());
    set_contract_address(vault.get_fossil_client_address());
    // Should fail
    vault
        .fossil_client_callback_expect_error(
            l1_data, settlement_date, vErrors::L1DataNotAcceptedNow
        );
}

// Test callback fails if round > 1 is open
#[test]
#[available_gas(50000000)]
fn test_round_callback_fails_if_non_first_round_open() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, to_gwei(4));

    let mut current_round = vault.get_current_round();
    let l1_data = get_mock_l1_data();
    let timestamp = current_round.get_deployment_date();

    // Should fail
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_client_callback_expect_error(l1_data, timestamp, vErrors::L1DataNotAcceptedNow);
}

// Test callbacks fail if round is Auctioning
#[test]
#[available_gas(50000000)]
fn test_callback_fails_if_current_round_auctioning() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);

    let l1_data = get_mock_l1_data();
    let timestamp = current_round.get_deployment_date();

    // Should fail
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_client_callback_expect_error(l1_data, timestamp, vErrors::L1DataNotAcceptedNow);
}

// Test callback can init first round if in range
#[test]
#[available_gas(50000000)]
fn test_callback_for_first_round_if_in_range() {
    let eth_address = deploy_eth().contract_address;
    let mut vault = VaultFacade { vault_dispatcher: deploy_vault(1234, 1234, eth_address) };
    let mut current_round = vault.get_current_round();

    let L1Data { twap, volatility, reserve_price } = get_mock_l1_data();
    let l1_data = L1Data { twap, volatility, reserve_price };
    let deployment_date = current_round.get_deployment_date();

    set_block_timestamp(current_round.get_auction_start_date() - 1);
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_client_callback(l1_data, deployment_date);

    let expected_strike = pricing_utils::calculate_strike_price(vault.get_strike_level(), twap);
    let expected_cap = pricing_utils::calculate_cap_level(
        vault.get_alpha(), vault.get_strike_level(), volatility
    );

    assert_eq!(current_round.get_strike_price(), expected_strike);
    assert_eq!(current_round.get_cap_level(), expected_cap);
    assert_eq!(current_round.get_reserve_price(), reserve_price);
}


// Test callback to start first round fails if out of range
#[test]
#[available_gas(50000000)]
fn test_callback_out_of_range_fails_first_round_start() {
    set_block_timestamp(123);
    let eth_address = deploy_eth().contract_address;
    let mut vault = VaultFacade { vault_dispatcher: deploy_vault(1234, 1234, eth_address) };
    let mut current_round = vault.get_current_round();

    let L1Data { twap, volatility, reserve_price } = get_mock_l1_data();
    let l1_data = L1Data { twap, volatility, reserve_price };
    let deployment_date = current_round.get_deployment_date();

    set_block_timestamp(current_round.get_auction_start_date() - 1);
    set_contract_address(vault.get_fossil_client_address());

    // Should fail
    vault
        .fossil_client_callback_expect_error(
            l1_data, deployment_date - 1, vErrors::L1DataOutOfRange
        );
    vault
        .fossil_client_callback_expect_error(
            l1_data, deployment_date + 1, vErrors::L1DataOutOfRange
        );
}

// Test callback to settle a round fails if out of range
#[test]
#[available_gas(50000000)]
fn test_callback_out_of_range_fails_settle_current_round() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    let L1Data { twap, volatility, reserve_price } = get_mock_l1_data();
    let l1_data = L1Data { twap, volatility, reserve_price };
    let settlement_date = current_round.get_option_settlement_date();

    set_block_timestamp(current_round.get_auction_start_date() - 1);
    set_contract_address(vault.get_fossil_client_address());

    // Should fail
    vault
        .fossil_client_callback_expect_error(
            l1_data, settlement_date + 1, vErrors::L1DataOutOfRange
        );
    vault
        .fossil_client_callback_expect_error(
            l1_data, settlement_date - 1, vErrors::L1DataOutOfRange
        );
}


// Test callback settles round and deploys next correctly
#[test]
#[available_gas(50000000)]
fn test_callback_works_as_expected() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let fossil_client = vault.get_fossil_client_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    // Callback
    let request = get_request_serialized(ref vault);
    let result = get_mock_result_serialized();
    fossil_client.fossil_callback(request, result);

    let mut next_round = vault.get_current_round();
    let l1_data = get_mock_l1_data();
    let strike = pricing_utils::calculate_strike_price(vault.get_strike_level(), l1_data.twap);
    let cap = pricing_utils::calculate_cap_level(
        vault.get_alpha(), vault.get_strike_level(), l1_data.volatility
    );

    assert_eq!(next_round.get_cap_level(), cap);
    assert_eq!(next_round.get_strike_price(), strike);
    assert_eq!(next_round.get_reserve_price(), l1_data.reserve_price);
    assert_eq!(current_round.get_settlement_price(), l1_data.twap);
}

#[test]
#[available_gas(90000000)]
fn test_0_rounds() {
    let (mut vault, _) = setup_facade();
    // need to customize each to do 0s
    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running_custom(ref vault, array![].span(), array![].span(), array![].span());
    accelerate_to_settled(ref vault, 123456789);

    let _x = vault.get_lp_locked_balance(liquidity_provider_1());
    let _y = vault.get_lp_unlocked_balance(liquidity_provider_1());
    let _z = vault.get_lp_stashed_balance(liquidity_provider_1());

    accelerate_to_auctioning_custom(ref vault, array![].span(), array![].span());
    accelerate_to_running_custom(ref vault, array![].span(), array![].span(), array![].span());
    accelerate_to_settled(ref vault, 123456789);

    let _x = vault.get_lp_locked_balance(liquidity_provider_1());
    let _y = vault.get_lp_unlocked_balance(liquidity_provider_1());
    let _z = vault.get_lp_stashed_balance(liquidity_provider_1());

    vault.deposit(100, liquidity_provider_1());
}

