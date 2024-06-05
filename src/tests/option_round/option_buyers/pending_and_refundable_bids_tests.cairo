use core::traits::TryInto;
use starknet::{ContractAddress, testing::{set_block_timestamp, set_contract_address}};
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,};
use pitch_lake_starknet::tests::{
    utils::{
        event_helpers::{assert_event_unused_bids_refunded, clear_event_logs},
        accelerators::{
            accelerate_to_auctioning, accelerate_to_running_custom, accelerate_to_running,
            accelerate_to_settled, timeskip_and_end_auction, accelerate_to_auctioning_custom,
            timeskip_past_auction_end_date,
        },
        test_accounts::{
            liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
            option_bidder_buyer_3, option_bidders_get, option_bidder_buyer_4,
        },
        variables::{decimals}, setup::{setup_facade},
        facades::{
            vault_facade::{VaultFacade, VaultFacadeTrait},
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
        },
        utils::{scale_array, get_erc20_balance, get_erc20_balances, create_array_gradient},
    },
};


/// Test Setup ///

// Deploy vault and start auction
// @return The vault facade, eth dispatcher, and span of option bidders
fn setup_test(
    number_of_option_buyers: u256
) -> (VaultFacade, IERC20Dispatcher, Span<ContractAddress>) {
    let (mut vault, eth) = setup_facade();

    // Auction participants
    let option_bidders = option_bidders_get(3);

    // Start auction
    accelerate_to_auctioning(ref vault);

    return (vault, eth, option_bidders.span());
}

// Place incremental bids
fn place_incremental_bids_internal(
    ref vault: VaultFacade, option_bidders: Span<ContractAddress>,
) -> (Span<u256>, Span<u256>, OptionRoundFacade) {
    let mut current_round = vault.get_current_round();
    let number_of_option_bidders = option_bidders.len();
    let number_of_options_available = current_round.get_total_options_available();
    let option_reserve_price = current_round.get_reserve_price();

    // @dev Bids start at reserve price and increment by reserve price
    let bid_prices = create_array_gradient(
        option_reserve_price, option_reserve_price, number_of_option_bidders
    );

    // @dev Bid amounts are each bid price * the number of options available
    let mut bid_amounts = scale_array(bid_prices.span(), number_of_options_available);

    // Place bids
    current_round.place_bids(bid_amounts.span(), bid_prices.span(), option_bidders);
    (bid_amounts.span(), bid_prices.span(), current_round)
}


// @note Break up into separate files
// - pending and refunded bids can be in their own files (if it
// makes sense to) in (.src/tests/state_transition/auction_start|end_tests),
// but refunding bids should be in a new file (.src/tests/option_round/option_buyers/{})
/// Pending Bids Tests ///

// Test before auction ends, pending bid balance is bid amount
#[test]
#[available_gas(10000000)]
fn test_pending_bids_before_auction_end() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Start auction
    accelerate_to_auctioning(ref vault);

    // Each option buyer out bids the next
    let (mut bid_amounts, _, mut current_round) = place_incremental_bids_internal(
        ref vault, option_bidders
    );

    // Check pending bid balance is bid amount for each option bidder
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                let pending_bid = current_round.get_pending_bids_for(*bidder);
                let bid_amount = bid_amounts.pop_front().unwrap();
                assert(pending_bid == *bid_amount, 'pending bid shd be bid amount');
            },
            Option::None => { break; }
        }
    }
}

// Test after auction ends, pending bid balance ends is 0
#[test]
#[available_gas(10000000)]
fn test_pending_bids_after_auction_end() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Start auction
    accelerate_to_auctioning(ref vault);

    // Each option buyer out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // End auction
    timeskip_and_end_auction(ref vault);

    // Check pending bid balance is 0 for each bidder
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                let pending_bid = current_round.get_pending_bids_for(*bidder);
                assert(pending_bid == 0, 'pending bid shd be 0');
            },
            Option::None => { break; }
        }
    }
}


/// Refunded Bids Tests ///

// Test refunded bid balance before auction ends
#[test]
#[available_gas(10000000)]
fn test_refunded_bids_before_auction_end() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each option buyer out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // Check refunded bid balance is 0 for each bidder
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                let refunded_amount = current_round.get_refundable_bids_for(*bidder);
                assert(refunded_amount == 0, 'refunded bid shd be 0');
            },
            Option::None => { break; }
        }
    }
}

// Test refunded bid balance after auction ends
#[test]
#[available_gas(10000000)]
fn test_refunded_bids_after_auction_end() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each option buyer out bids the next
    let (mut bid_amounts, _, mut current_round) = place_incremental_bids_internal(
        ref vault, option_bidders
    );

    // End auction
    timeskip_and_end_auction(ref vault);

    // Pop last bidder from array because their bids are not refundable
    match option_bidders.pop_back() {
        Option::Some(_) => {
            // Check refunded bid balance for each losing bidder
            loop {
                match option_bidders.pop_front() {
                    Option::Some(bidder) => {
                        let refunded_amount = current_round.get_refundable_bids_for(*bidder);
                        let bid_amount = bid_amounts.pop_front().unwrap();
                        assert(refunded_amount == *bid_amount, 'refunded bid balance wrong');
                    },
                    Option::None => { break; }
                }
            }
        },
        Option::None => { panic!("this should not panic") }
    }
}


/// Refunding Bids Tests ///

/// Failures

// Test refunding bids before the auction ends fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction is still on-going', 'ENTRYPOINT_FAILED',))]
fn test_refunding_bids_before_auction_end_fails() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each option buyer out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // Try to refund bids before auction ends
    current_round.refund_bid(*option_bidders[0]);
}

// Test refunding 0 bids fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('No bids to refund', 'ENTRYPOINT_FAILED',))]
fn test_refunding_0_bids_fails() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each bidder out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // End auction
    timeskip_and_end_auction(ref vault);

    // Pop first bidder from array because their bids are refundable
    match option_bidders.pop_front() {
        Option::Some(bidder) => {
            // Refund bids
            current_round.refund_bid(*bidder);
            // Refund again fails since their are 0 refundable now
            current_round.refund_bid(*bidder);
        },
        Option::None => { panic!("this should not panic") }
    }
}

/// Event Tests

// Test refunding bids emits event correctly
#[test]
#[available_gas(10000000)]
fn test_refunding_bids_events() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each bidder out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // End auction
    timeskip_and_end_auction(ref vault);

    // Pop last bidder from array because their bids are not refundable
    match option_bidders.pop_back() {
        Option::Some(_) => {
            // Collect unused bids
            loop {
                match option_bidders.pop_front() {
                    Option::Some(bidder) => {
                        // Check refunding bids emits the correct event
                        let refund_amount = current_round.refund_bid(*bidder);
                        assert_event_unused_bids_refunded(
                            current_round.contract_address(), *bidder, refund_amount
                        );
                    },
                    Option::None => { break; }
                }
            }
        },
        Option::None => { panic!("this should not panic") }
    }
}

/// State tests

// Test refunding bids sets refunded balance to 0
#[test]
#[available_gas(10000000)]
fn test_refund_bids_sets_refunded_balance_to_0() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each bidder out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // End auction
    timeskip_and_end_auction(ref vault);

    // Pop first bidder from array because their bid is refundable
    match option_bidders.pop_front() {
        Option::Some(bidder) => {
            current_round.refund_bid(*bidder);
            // Check refunded bid balance is 0 for bidder
            assert(0 == current_round.get_refundable_bids_for(*bidder), 'refunded bid shd be 0');
        },
        Option::None => { panic!("this should not panic") }
    }
}

// Test refunding bids transfers eth from round to option bidder
#[test]
#[available_gas(10000000)]
fn test_refund_bids_eth_transfer() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, eth_dispatcher, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each option bidder out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // End auction
    timeskip_and_end_auction(ref vault);

    // Pop last bidder from array because their bids are not refundable
    match option_bidders.pop_back() {
        Option::Some(_) => {
            // Collect unused bids
            loop {
                match option_bidders.pop_front() {
                    Option::Some(bidder) => {
                        let eth_balance_before = eth_dispatcher.balance_of(*bidder);
                        let refunded_amount = current_round.get_refundable_bids_for(*bidder);
                        let eth_balance_after = eth_dispatcher.balance_of(*bidder);
                        assert(
                            eth_balance_after == eth_balance_before + refunded_amount,
                            'lp did not receive eth'
                        );
                    },
                    Option::None => { break; }
                }
            }
        },
        Option::None => { panic!("this should not panic") }
    }
}