use core::traits::TryInto;
use starknet::{ContractAddress, testing::{set_block_timestamp, set_contract_address}};
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait,};
use pitch_lake_starknet::tests::{
    utils::{
        helpers::{
            event_helpers::{assert_event_unused_bids_refunded, clear_event_logs},
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running_custom, accelerate_to_running,
                accelerate_to_settled, timeskip_and_end_auction, accelerate_to_auctioning_custom,
                timeskip_past_auction_end_date,
            },
            setup::{setup_facade},
            general_helpers::{
                scale_array, get_erc20_balance, get_erc20_balances, create_array_gradient,
                create_array_linear
            },
        },
        lib::{
            test_accounts::{
                liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
                option_bidder_buyer_3, option_bidders_get, option_bidder_buyer_4,
            },
            variables::{decimals},
        },
        facades::{
            vault_facade::{VaultFacade, VaultFacadeTrait},
            option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
        },
    },
};


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
    let options_available = current_round.get_total_options_available();
    let option_reserve_price = current_round.get_reserve_price();

    // @dev Bids start at reserve price and increment by reserve price
    let bid_prices = create_array_gradient(
        option_reserve_price, option_reserve_price, number_of_option_bidders
    );

    // @dev Bid amounts are each bid price * the number of options available
    let mut bid_amounts = create_array_linear(options_available, bid_prices.len());

    // Place bids
    current_round.place_bids(bid_amounts.span(), bid_prices.span(), option_bidders);
    (bid_amounts.span(), bid_prices.span(), current_round)
}

/// Pending/Refundable Bids Tests ///

// Test after auction ends, pending bid balance is 0
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


/// Refundable Bids Tests ///
// Pending bids become either premiums or refundable

// Test refundable bid balance before auction ends
#[test]
#[available_gas(10000000)]
fn test_refundable_bids_before_auction_end() {
    let number_of_option_bidders: u256 = 3;
    let (mut vault, _, mut option_bidders) = setup_test(number_of_option_bidders);

    // Each option buyer out bids the next
    let (_, _, mut current_round) = place_incremental_bids_internal(ref vault, option_bidders);

    // Check refunded bid balance is 0 for each bidder
    loop {
        match option_bidders.pop_front() {
            Option::Some(bidder) => {
                let refundable_amount = current_round.get_refundable_bids_for(*bidder);
                assert(refundable_amount == 0, 'refunded bid shd be 0');
            },
            Option::None => { break; }
        }
    }
}

// Test refundable bid balance after auction ends
#[test]
#[available_gas(10000000)]
fn test_refundable_bids_after_auction_end() {
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

// Test refundable bids sums partial and fully refundable bids
#[test]
#[available_gas(10000000)]
fn test_refundable_bids_includes_partial_and_fully_refunded_bids() {
    let (mut vault, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    // Same bidder places 4 bids, first 2 are fully used, 3rd is partially used, and 4th is fully unused
    let bidder = option_bidder_buyer_1();
    let bidders = create_array_linear(bidder, 4).span();
    let bid_amount = 2 * total_options_available / 5;
    let bid_price = current_round.get_reserve_price();
    let bid_amounts = create_array_linear(bid_amount, 4).span();
    let bid_prices = create_array_linear(bid_price, 4).span();
    accelerate_to_running_custom(ref vault, bidders, bid_amounts, bid_prices);

    // Check that the refundable amount is the unsued bids from bid 3 and all of bid 4
    let bid_3_amount_used = total_options_available - (2 * bid_amount);
    let bid_3_amount_unused = bid_amount - bid_3_amount_used;
    let bid_3_refundable_amount = bid_3_amount_unused * bid_price;
    let bid_4_refundable_amount = bid_amount * bid_price;
    let total_refundable_amount = bid_3_refundable_amount + bid_4_refundable_amount;

    assert(
        current_round.get_refundable_bids_for(bidder) == total_refundable_amount,
        'refunable amount wrong'
    );
}

// Test over bids are refundable
#[test]
#[available_gas(10000000)]
fn test_over_bids_are_refundable() {
    let (mut vault, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    // 2 bidders bid for combined all options, the winning bidder should get a refund for their over bid
    let mut bidders = option_bidders_get(2).span();
    let reserve_price = current_round.get_reserve_price();
    let bid_amounts = create_array_linear(total_options_available / 2, 2).span();
    let bid_prices = create_array_gradient(reserve_price, reserve_price, 2).span();
    accelerate_to_running_custom(ref vault, bidders, bid_amounts, bid_prices);

    // Check that the first bidder gets no refund, and the second bidder gets a partial refund
    assert(current_round.get_refundable_bids_for(*bidders[0]) == 0, 'ob1 shd get no refunds');
    assert(
        current_round.get_refundable_bids_for(*bidders[1]) == reserve_price
            * total_options_available
            / 2,
        'ob2 shd have a partial refund'
    );
}
