use core::traits::Into;
use starknet::testing::{set_block_timestamp, set_contract_address};
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,};
use pitch_lake_starknet::{
    contracts::option_round::OptionRound::{OptionRoundError, OptionRoundErrorIntoFelt252},
    tests::{
        utils::{
            helpers::{
                general_helpers::{create_array_linear, get_erc20_balance, get_erc20_balances},
                event_helpers::{
                    assert_event_transfer, assert_event_vault_withdrawal,
                    assert_event_options_exercised, clear_event_logs,
                },
                setup::{setup_facade},
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                    accelerate_to_running_custom,
                },
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
                    option_bidder_buyer_3, option_bidders_get
                },
                variables::decimals,
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
        },
    }
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
    let mut expected_error: felt252 = OptionRoundError::AuctionEndDateNotReached.into();
    match current_round.exercise_options_raw(option_bidder_buyer_1()) {
        Result::Ok(_) => { panic!("Error expected") },
        Result::Err(err) => { assert(err.into() == expected_error, 'Error misMatch'); },
    }
}

/// Event Tests ///

// Test exercising emits correct events
#[test]
#[available_gas(50000000)]
fn test_exercise_options_events() {
    let (mut vault, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);

    // Place bids and start the auction, bidders split the options at the reserve price
    let mut option_bidders = option_bidders_get(3).span();
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bid_count = options_available / option_bidders.len().into();
    let bid_amounts = create_array_linear(bid_count, 3).span();
    let bid_prices = create_array_linear(reserve_price, option_bidders.len()).span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);
    accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());

    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                let payout_amount = current_round.exercise_options(*ob);

                assert_event_options_exercised(
                    current_round.contract_address(), *ob, bid_count, payout_amount
                );
            },
            Option::None => { break (); }
        }
    };
}


/// State Tests ///

#[test]
#[available_gas(50000000)]
fn test_exercise_options_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);

    // Place bids and start the auction, bidders split the options at the reserve price
    let mut option_bidders = option_bidders_get(3).span();
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bid_count = options_available / option_bidders.len().into();
    let bid_prices = create_array_linear(reserve_price, option_bidders.len()).span();
    let bid_amounts = create_array_linear(bid_count, 3).span();
    accelerate_to_running_custom(ref vault, option_bidders, bid_amounts, bid_prices);
    let total_payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());

    // Eth balance before
    let round_balance_before = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                let lp_balance_before = get_erc20_balance(eth.contract_address, *ob);
                let payout_amount = current_round.exercise_options(*ob);
                let lp_balance_after = get_erc20_balance(eth.contract_address, *ob);

                assert(
                    lp_balance_after == lp_balance_before + payout_amount, 'lp balance after wrong'
                );
            },
            Option::None => { break (); }
        }
    };
    let round_balance_after = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    assert(round_balance_after == round_balance_before - total_payout, 'round balance after wrong');
}
// @note Add tests for get_payout_balance_for becoming 0 after exercise
// @note Add test that options are burned when exercised
// @note Add test that OB can send options to another account then exercise (original owner shd not have access to payout afterwards)
// @note Add test that OB1 can exercise options, then receive more from OB2, the exerice again


