use core::traits::TryInto;
use openzeppelin_token::erc20::interface::{ERC20ABI, ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use pitch_lake::option_round::contract::OptionRound::Errors;
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
    accelerate_to_running_custom, accelerate_to_settled, timeskip_and_end_auction,
    timeskip_past_auction_end_date,
};
use pitch_lake::tests::utils::helpers::event_helpers::{
    assert_event_unused_bids_refunded, clear_event_logs,
};
use pitch_lake::tests::utils::helpers::general_helpers::{
    create_array_gradient, create_array_linear, get_erc20_balance, get_erc20_balances, scale_array,
};
use pitch_lake::tests::utils::helpers::setup::setup_facade;
use pitch_lake::tests::utils::lib::test_accounts::{
    liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
    option_bidder_buyer_4, option_bidders_get,
};
use pitch_lake::tests::utils::lib::variables::decimals;
use starknet::ContractAddress;
use starknet::testing::{set_block_timestamp, set_contract_address};

// @note Break up into separate files
// - pending/refundable bids tests can be in the same file, needs to move to
// option_round/state_transition/auction_end/, - refunding bids should be in a new file
// (option_round/option_buyers/refunding_bids_tests.cairo)

/// Test Setup ///

// @note Look for patterns in other tests to simplify using similar thinking of below technique
// - Maybe each file could use something like these to further simplify test readability

// Deploy vault and start auction
// @return The vault facade, eth dispatcher, and span of option bidders
fn setup_test(
    number_of_option_buyers: u32,
) -> (VaultFacade, ERC20ABIDispatcher, Span<ContractAddress>) {
    let (mut vault, eth) = setup_facade();

    // Auction participants
    let option_bidders = option_bidders_get(number_of_option_buyers);

    // Start auction
    accelerate_to_auctioning(ref vault);

    return (vault, eth, option_bidders.span());
}

// Place incremental bids
// @note Move to utils
fn place_incremental_bids_internal(
    ref vault: VaultFacade, option_bidders: Span<ContractAddress>,
) -> (Span<u256>, Span<u256>, OptionRoundFacade) {
    let mut current_round = vault.get_current_round();
    let number_of_option_bidders = option_bidders.len();
    let options_available = current_round.get_total_options_available();
    let option_reserve_price = current_round.get_reserve_price();

    // @dev Bids start at reserve price and increment by reserve price
    let bid_prices = create_array_gradient(
        option_reserve_price, option_reserve_price, number_of_option_bidders,
    );

    // @dev Bid amounts are the number of options available
    let mut bid_amounts = create_array_linear(options_available, bid_prices.len());

    // Place bids
    current_round.place_bids(bid_amounts.span(), bid_prices.span(), option_bidders);

    (bid_amounts.span(), bid_prices.span(), current_round)
}


/// Refunding Bids Tests ///

/// Failures

// Test refunding bids before the auction ends fails
#[test]
#[available_gas(500000000)]
fn test_refunding_bids_before_auction_end_fails() {
    let number_of_option_bidders: u32 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each option buyer out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // Try to refund bids before auction ends
    current_round.refund_bid_expect_error(*option_bidders[0], Errors::AuctionNotEnded);
}


// Test refunding bids emits event correctly
#[test]
#[available_gas(5000000000)]
fn test_refunding_bids_events() {
    let number_of_option_bidders: u32 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each bidder out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // End auction
    timeskip_and_end_auction(ref vault);

    clear_event_logs(array![current_round.contract_address()]);
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
                            current_round.contract_address(), *bidder, refund_amount,
                        );
                    },
                    Option::None => { break; },
                }
            }
        },
        Option::None => { panic!("this should not panic") },
    }
}

/// State tests

// Test refunding bids sets refunded balance to 0
#[test]
#[available_gas(5000000000)]
fn test_refund_bids_sets_refunded_balance_to_0() {
    let number_of_option_bidders: u32 = 3;
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
            assert(0 == current_round.get_refundable_balance_for(*bidder), 'refunded bid shd be 0');
        },
        Option::None => { panic!("this should not panic") },
    }
}

// Test refunding bids transfers eth from round to option bidder
#[test]
#[available_gas(5000000000)]
fn test_refund_bids_eth_transfer() {
    let number_of_option_bidders: u32 = 3;
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
                        let refunded_amount = current_round.refund_bid(*bidder);
                        let eth_balance_after = eth_dispatcher.balance_of(*bidder);
                        assert(
                            eth_balance_after == eth_balance_before + refunded_amount,
                            'lp did not receive eth',
                        );
                    },
                    Option::None => { break; },
                }
            }
        },
        Option::None => { panic!("this should not panic") },
    }
}
// @note Add test for bidder having a portion of their bid refundable


