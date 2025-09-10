use core::traits::Into;
use pitch_lake::option_round::contract::OptionRound::Errors;
use pitch_lake::tests::utils::facades::option_round_facade::OptionRoundFacadeTrait;
use pitch_lake::tests::utils::facades::vault_facade::VaultFacadeTrait;
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
    accelerate_to_settled,
};
use pitch_lake::tests::utils::helpers::event_helpers::{
    assert_event_options_exercised, clear_event_logs,
};
use pitch_lake::tests::utils::helpers::general_helpers::{create_array_linear, get_erc20_balance};
use pitch_lake::tests::utils::helpers::setup::setup_facade;
use pitch_lake::tests::utils::lib::test_accounts::{
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidders_get,
};


/// Failures ///

// Test exercising 0 options fails
// @note instead of returning 0 or failing, we should just include in each test an extra LP
// that has 0 options to exercise (after placing bids append an extra LP to the array,
// this way we know they have 0 options)
#[test]
#[available_gas(50000000)]
fn test_exercising_0_options() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();
    accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());

    // @dev OB 2 does not participate in the default accelerators
    current_round.exercise_options(option_bidder_buyer_2());
}

// Test evercising options before round settles fails
#[test]
#[available_gas(50000000)]
fn test_exercise_options_before_round_settles_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    // Try to exercise before round settles
    let mut current_round = vault.get_current_round();
    current_round
        .exercise_options_expect_error(option_bidder_buyer_1(), Errors::OptionRoundNotSettled);
}

/// Event Tests ///

// Test exercising emits correct events
#[test]
#[available_gas(5000000000)]
fn test_exercise_options_events() {
    let (mut vault, _) = setup_facade();
    let mut option_bidders = option_bidders_get(3).span();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);

    // Place bids and start the auction, bidders split the options at the reserve price
    let reserve_price = current_round.get_reserve_price();
    let bid_count = options_available / option_bidders.len().into();
    let bid_amounts = create_array_linear(bid_count, 3).span();
    let bid_prices = create_array_linear(reserve_price, option_bidders.len()).span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);
    accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    clear_event_logs(array![current_round.contract_address()]);

    // OB1 mints all options before exercising, emitting 0 for mintable options exercised
    match option_bidders.pop_front() {
        Option::Some(ob) => {
            current_round.mint_options(*ob);
            clear_event_logs(array![current_round.contract_address()]);
            let payout_amount = current_round.exercise_options(*ob);
            assert_event_options_exercised(
                current_round.contract_address(), *ob, bid_count, 0_u256, payout_amount,
            );
        },
        Option::None => {},
    }
    // The rest of the OBs exercise all of their options which are mintable
    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                clear_event_logs(array![current_round.contract_address()]);
                let payout_amount = current_round.exercise_options(*ob);
                assert_event_options_exercised(
                    current_round.contract_address(), *ob, bid_count, bid_count, payout_amount,
                );
            },
            Option::None => { break (); },
        }
    };
}


/// State Tests ///

#[test]
#[available_gas(500000000)]
fn test_exercise_options_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);

    // Place bids and start the auction, bidders split the options at the reserve price
    let mut option_bidders = option_bidders_get(4).span();
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bid_count = options_available / option_bidders.len().into();
    let bid_prices = create_array_linear(reserve_price, option_bidders.len()).span();
    let bid_amounts = create_array_linear(bid_count, 4).span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);
    let total_payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());

    // Eth balance before
    let round_balance_before = get_erc20_balance(
        eth.contract_address, current_round.contract_address(),
    );
    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                let lp_balance_before = get_erc20_balance(eth.contract_address, *ob);
                let payout_amount = current_round.exercise_options(*ob);

                let lp_balance_after = get_erc20_balance(eth.contract_address, *ob);
                assert_eq!(lp_balance_after, lp_balance_before + payout_amount);
            },
            Option::None => { break (); },
        }
    }
    let round_balance_after = get_erc20_balance(
        eth.contract_address, current_round.contract_address(),
    );
    assert(round_balance_after == round_balance_before - total_payout, 'round balance after wrong');
}
// @note Add tests for get_payout_balance_for becoming 0 after exercise
// @note Add test that options are burned when exercised
// @note Add test that OB can send options to another account then exercise (original owner shd not
// have access to payout afterwards)
// @note Add test that OB1 can exercise options, then receive more from OB2, the exerice again


