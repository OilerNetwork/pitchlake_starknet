use core::integer::I128Neg;
use pitch_lake::library::pricing_utils;
use pitch_lake::library::pricing_utils::calculate_strike_price;
use pitch_lake::option_round::interface::PricingData;
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{
    VaultFacade, VaultFacadeImpl, VaultFacadeTrait,
};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
    accelerate_to_running_custom, accelerate_to_settled, accelerate_to_settled_custom,
    timeskip_to_settlement_date,
};
use pitch_lake::tests::utils::helpers::event_helpers::{
    assert_fossil_callback_success_event, clear_event_logs,
};
use pitch_lake::tests::utils::helpers::general_helpers::to_gwei;
use pitch_lake::tests::utils::helpers::setup::{
    PITCHLAKE_VERIFIER, deploy_eth, deploy_vault, eth_supply_and_approve_all_bidders,
    eth_supply_and_approve_all_providers, setup_facade,
};
use pitch_lake::tests::utils::lib::test_accounts::liquidity_provider_1;
use pitch_lake::vault::contract::Vault;
use pitch_lake::vault::contract::Vault::Errors as vErrors;
use pitch_lake::vault::interface::{JobRequest, L1Data, VerifierData};
use starknet::testing::{set_block_timestamp, set_contract_address};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};


fn get_mock_l1_data() -> L1Data {
    L1Data { twap: to_gwei(33) / 100, max_return: 1009, reserve_price: to_gwei(11) / 10 }
}

fn get_request(ref vault: VaultFacade) -> JobRequest {
    vault.get_request_to_settle_round()
}

fn get_request_serialized(ref vault: VaultFacade) -> Span<felt252> {
    let mut request_serialized = array![];
    get_request(ref vault).serialize(ref request_serialized);
    request_serialized.span()
}

// Test only the fossil processor can call the fossil callback

// Fossil Client Contract
// @note Un-ignore this after Fossil processor is setup
#[test]
#[available_gas(50000000)]
fn test_only_pitchlake_verifier_can_call_fossil_callback() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    // Should fail
    set_contract_address(contract_address_const::<'NOT IT'>());
    vault.fossil_callback_expect_error(req, res, vErrors::CallerNotVerifier);

    // Should not fail
    set_contract_address(PITCHLAKE_VERIFIER());
    vault.fossil_callback(req, res);
}

// Test invalid request fails
#[test]
#[available_gas(50000000)]
fn test_invalid_request_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let mut req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    // Should fail
    set_contract_address(PITCHLAKE_VERIFIER());
    let _ = req.pop_front();
    vault.fossil_callback_expect_error(req, res, vErrors::FailedToDeserializeJobRequest);
}

// Test invalid Fossil result fails
#[test]
#[available_gas(50000000)]
fn test_invalid_result_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let req = vault.get_request_to_settle_round_serialized();
    let mut res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    // Should fail
    set_contract_address(PITCHLAKE_VERIFIER());
    let _ = res.pop_front();
    vault.fossil_callback_expect_error(req, res, vErrors::FailedToDeserializeVerifierData);
}

// Test empty L1 data is not accepted
#[test]
#[available_gas(50000000)]
fn test_default_l1_data_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    let l1_data = L1Data { twap: 0, max_return: 1, reserve_price: 1 };
    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(l1_data);

    // Should fail
    vault.fossil_callback_expect_error(req, res, vErrors::InvalidL1Data);

    let l1_data = L1Data { twap: 1, max_return: 1, reserve_price: 0 };
    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(l1_data);

    // Should fail
    vault.fossil_callback_expect_error(req, res, vErrors::InvalidL1Data);
}

// Test callback event
#[test]
#[available_gas(100000000)]
fn test_callback_event() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    set_contract_address(PITCHLAKE_VERIFIER());

    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    clear_event_logs(array![vault.contract_address()]);
    vault.fossil_callback(req, res);

    assert_fossil_callback_success_event(
        vault.contract_address(), get_mock_l1_data(), current_round.get_option_settlement_date(),
    );
}

// Vault Callback for Client

// Test only pitch lake client can call pitch client callback
#[test]
#[available_gas(50000000)]
fn test_only_fossil_client_can_call_fossil_client_callback() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    //let mut current_round = vault.get_current_round();
    let l1_data = get_mock_l1_data();
    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(l1_data);
    //let settlement_date = current_round.get_option_settlement_date();

    // Should fail
    set_contract_address(contract_address_const::<'NOT IT'>());
    vault.fossil_callback_expect_error(req, res, vErrors::CallerNotVerifier);

    // Should not fail
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_callback(req, res);
}

// Test successfull callback sets the pricing data for the round
#[test]
#[available_gas(50000000)]
fn test_callback_sets_pricing_data_for_round() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    // Settle round using callback data
    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_callback(req, res);

    // Check pricing data set as expected
    let mut current_round = vault.get_current_round();
    let L1Data { twap, max_return, reserve_price } = get_mock_l1_data();
    let exp_strike_price = pricing_utils::calculate_strike_price(vault.get_strike_level(), twap);
    let exp_cap_level = pricing_utils::calculate_cap_level(
        vault.get_alpha(), vault.get_strike_level(), max_return,
    );

    assert_eq!(current_round.get_strike_price(), exp_strike_price);
    assert_eq!(current_round.get_cap_level(), exp_cap_level);
    assert_eq!(current_round.get_reserve_price(), reserve_price);
}

// Test callback fails if round > 1 is open
#[test]
#[available_gas(50000000)]
fn test_round_callback_fails_if_non_first_round_open() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, to_gwei(4));

    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    // Should fail
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_callback_expect_error(req, res, vErrors::L1DataNotAcceptedNow);
}

// Test callbacks fail if round is Auctioning
#[test]
#[available_gas(50000000)]
fn test_callback_fails_if_current_round_auctioning() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    // Should fail
    set_contract_address(vault.get_fossil_client_address());
    vault.fossil_callback_expect_error(req, res, vErrors::L1DataNotAcceptedNow);
}

// Test callback can init first round if in range
#[test]
#[available_gas(50000000)]
fn test_callback_for_first_round_if_in_range() {
    set_block_timestamp(123456789);
    let eth_address = deploy_eth().contract_address;
    let mut vault = VaultFacade { vault_dispatcher: deploy_vault(1234, 1234, eth_address) };
    set_block_timestamp(get_block_timestamp() + vault.get_proving_delay());
    let mut current_round = vault.get_current_round();

    let l1_data = get_mock_l1_data();
    let req = vault.get_request_to_start_first_round_serialized();
    let res = vault.generate_first_round_result_serialized(l1_data);

    set_contract_address(vault.get_fossil_client_address());

    vault.fossil_callback(req, res);

    let expected_strike = pricing_utils::calculate_strike_price(
        vault.get_strike_level(), l1_data.twap,
    );
    let expected_cap = pricing_utils::calculate_cap_level(
        vault.get_alpha(), vault.get_strike_level(), l1_data.max_return,
    );

    assert_eq!(current_round.get_strike_price(), expected_strike);
    assert_eq!(current_round.get_cap_level(), expected_cap);
    assert_eq!(current_round.get_reserve_price(), l1_data.reserve_price);
}


// Test callback to start first round fails if out of range
#[test]
#[available_gas(50000000)]
fn test_callback_out_of_range_fails_first_round_start() {
    set_block_timestamp(123456789);
    let eth_address = deploy_eth().contract_address;
    let mut vault = VaultFacade { vault_dispatcher: deploy_vault(1234, 1234, eth_address) };
    set_block_timestamp(get_block_timestamp() + vault.get_proving_delay());

    let mut current_round = vault.get_current_round();
    let deployment_date = current_round.get_deployment_date();

    let req = vault.generate_custom_job_request_serialized(deployment_date - 1);
    let req2 = vault.generate_custom_job_request_serialized(deployment_date + 1);
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    set_block_timestamp(current_round.get_auction_start_date() - 1);
    set_contract_address(vault.get_fossil_client_address());

    // Should fail
    vault.fossil_callback_expect_error(req, res, vErrors::L1DataOutOfRange);
    vault.fossil_callback_expect_error(req2, res, vErrors::L1DataOutOfRange);
}

// Test callback to settle a round fails if out of range
#[test]
#[available_gas(50000000)]
fn test_callback_out_of_range_fails_settle_current_round() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let settlement_date = current_round.get_option_settlement_date();

    let req = vault.generate_custom_job_request_serialized(settlement_date - 1);
    let req2 = vault.generate_custom_job_request_serialized(settlement_date + 1);
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    set_block_timestamp(current_round.get_auction_start_date() - 1);
    set_contract_address(vault.get_fossil_client_address());

    // Should fail
    vault.fossil_callback_expect_error(req, res, vErrors::L1DataOutOfRange);
    vault.fossil_callback_expect_error(req2, res, vErrors::L1DataOutOfRange);
}

// Test callback settles round and deploys next correctly
#[test]
#[available_gas(50000000)]
fn test_callback_works_as_expected() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_to_settlement_date(ref vault);

    // Callback/settle round
    let req = vault.get_request_to_settle_round_serialized();
    let res = vault.generate_settle_round_result_serialized(get_mock_l1_data());

    vault.fossil_callback(req, res);

    let mut next_round = vault.get_current_round();
    let l1_data = get_mock_l1_data();
    let strike = pricing_utils::calculate_strike_price(vault.get_strike_level(), l1_data.twap);
    let cap = pricing_utils::calculate_cap_level(
        vault.get_alpha(), vault.get_strike_level(), l1_data.max_return,
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

