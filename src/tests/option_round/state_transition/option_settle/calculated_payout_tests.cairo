use pitch_lake::library::constants::BPS_u256;
use pitch_lake::library::utils::{max, min};
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
};
use pitch_lake::tests::utils::helpers::setup::{setup_facade, setup_test_running};
use pitch_lake::tests::utils::lib::test_accounts::option_bidder_buyer_1;
use pitch_lake::tests::utils::lib::variables::bps;


fn calculate_expected_payout(ref round: OptionRoundFacade, settlement_price: u256) -> u256 {
    let strike_price = round.get_strike_price();
    let cap_level = round.get_cap_level();
    let max_payout_per_option = (cap_level.into() * strike_price) / BPS_u256;

    if (settlement_price <= strike_price) {
        0
    } else {
        let uncapped = settlement_price - strike_price;
        let capped = max_payout_per_option;
        let number_of_options_sold = round.total_options_sold();

        number_of_options_sold * min(capped, uncapped)
    }
}

// @note These tests should move to
// ./src/tests/option_round/state_transition/option_settled_tests.cairo
/// Total Payout Tests ///

#[test]
#[available_gas(50000000)]
fn test_option_payout_amount_index_at_strike() {
    let (mut vault_facade, mut current_round) = setup_test_running();

    let total_payout = accelerate_to_settled(ref vault_facade, current_round.get_strike_price());

    // Check payout balance is expected
    assert(total_payout == 0, 'expected payout doesnt match');
}

#[test]
#[available_gas(50000000)]
fn test_option_payout_amount_index_higher_than_strike() {
    let (mut vault, mut current_round) = setup_test_running();

    let K = current_round.get_strike_price();
    let x = 11111; // K * 1.1111
    let settlement_price = (x * K) / BPS_u256;

    let expected_payout = calculate_expected_payout(ref current_round, settlement_price);
    let payout = accelerate_to_settled(ref vault, settlement_price);

    // Check payout balance is expected
    assert(payout == expected_payout, 'payout doesnt match expected');

    let diff = settlement_price - K;
    assert(payout == current_round.total_options_sold() * diff, 'asdf');
}

#[test]
#[available_gas(50000000)]
fn test_option_payout_amount_index_higher_than_strike_and_cap_level() {
    let (mut vault, mut current_round) = setup_test_running();

    let K = current_round.get_strike_price();
    let settlement_price = 3 * K;
    let expected_payout = calculate_expected_payout(ref current_round, settlement_price);
    let payout = accelerate_to_settled(ref vault, settlement_price);

    // Check payout balance is expected
    assert(payout == expected_payout, 'payout doesnt match expected');
}


#[test]
#[available_gas(50000000)]
fn test_option_payout_amount_index_less_than_strike() {
    let (mut vault, mut current_round) = setup_test_running();

    let K = current_round.get_strike_price();
    let x = 3333; // 33.33% strike
    let settlement_price = (x * K) / BPS_u256;
    let payout = accelerate_to_settled(ref vault, settlement_price);

    // Check payout balance is expected
    assert(payout == 0, 'shd be no payout');
}

#[test]
#[available_gas(50000000)]
fn test_option_payout_amount_index_barely_less_than_strike() {
    let (mut vault, mut current_round) = setup_test_running();

    let K = current_round.get_strike_price();
    let x = 9999; // 99.99% strike
    let settlement_price = (x * K) / BPS_u256;
    let payout = accelerate_to_settled(ref vault, settlement_price);
    // Check payout balance is expected
    assert(payout == 0, 'shd be no payout');
}
/// Individual Payout Tests ///

// @note Check/add tests for OB individual payots
// @note add tests for payout matching expected for more realistic scenarios (talk with tomasz/finn)


