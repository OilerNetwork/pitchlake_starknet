use pitch_lake_starknet::{
    tests::{
        utils::{
            setup::{setup_facade},
            accelerators::{accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
            },
            test_accounts::{option_bidder_buyer_1}, variables::{bps}, utils::{min, max},
        },
    }
};

// @dev This needs formal verification
// @note This should move to utils
fn calculate_expected_payout(ref round: OptionRoundFacade, settlement_price: u256,) -> u256 {
    let k = round.get_strike_price();
    let cl = round.get_cap_level();
    max(0, min((1 + cl) * k, settlement_price) - k)
}

/// Total Payout Tests ///

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_at_strike() {
    let (mut vault_facade, _) = setup_facade();

    accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    accelerate_to_running(ref vault_facade);
    let total_payout = accelerate_to_settled(ref vault_facade, current_round.get_strike_price());

    // Check payout balance is expected
    assert(total_payout == 0, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_higher_than_strike() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    accelerate_to_running(ref vault);

    let K = current_round.get_strike_price();
    let x = 11111; // 111.11% strike
    let settlement_price = x * K / bps();
    let expected_payout = calculate_expected_payout(ref current_round, settlement_price);
    let payout = accelerate_to_settled(ref vault, settlement_price);

    // Check payout balance is expected
    assert(payout == expected_payout, 'payout doesnt match expected');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_higher_than_strike_and_cap_level() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    accelerate_to_running(ref vault);

    let K = current_round.get_strike_price();
    let settlement_price = 3 * K;
    let expected_payout = calculate_expected_payout(ref current_round, settlement_price);
    let payout = accelerate_to_settled(ref vault, settlement_price);

    // Check payout balance is expected
    assert(payout == expected_payout, 'payout doesnt match expected');
}


#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_less_than_strike() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    accelerate_to_running(ref vault);

    let K = current_round.get_strike_price();
    let x = 3333; // 33.33% strike
    let settlement_price = (x * K) / bps();
    let payout = accelerate_to_settled(ref vault, settlement_price);

    // Check payout balance is expected
    assert(payout == 0, 'shd be no payout');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_amount_index_barely_less_than_strike() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    accelerate_to_running(ref vault);

    let K = current_round.get_strike_price();
    let x = 9999; // 99.99% strike
    let settlement_price = (x * K) / bps();
    let payout = accelerate_to_settled(ref vault, settlement_price);
    // Check payout balance is expected
    assert(payout == 0, 'shd be no payout');
}
/// Individual Payout Tests ///

// @note Check/add tests for OB individual payots


