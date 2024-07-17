use core::traits::Into;
use pitch_lake_starknet::{
    contracts::{option_round::types::Errors},
    tests::{
        utils::{
            helpers::{
                setup::{setup_facade}, accelerators::{accelerate_to_auctioning},
                event_helpers::{assert_event_auction_bid_updated, clear_event_logs},
            },
            lib::{
                test_accounts::{option_bidders_get, option_bidder_buyer_1, option_bidder_buyer_2},
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
            },
        },
    }
};
#[test]
#[available_gas(50000000)]
fn test_update_bids_amount_cannot_be_decreased() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid to lower price
    current_round
        .update_bid_expect_error(
            bid_id, bid_amount - 1, bid_price, bidder, Errors::BidCannotBeDecreased
        );
}


#[test]
#[available_gas(50000000)]
fn test_update_bids_price_cannot_be_decreased() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid to lower price
    current_round
        .update_bid_expect_error(
            bid_id, bid_amount, bid_price - 1, bidder, Errors::BidCannotBeDecreased
        );
}

#[test]
#[available_gas(50000000)]
fn test_update_bid_event() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let option_buyer = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available / 2;
    let bid_id = current_round.place_bid(bid_amount, bid_price, option_buyer);
    clear_event_logs(array![current_round.contract_address()]);

    let updated_bid = current_round.update_bid(bid_id, bid_amount + 1, bid_price + 5);
    assert_event_auction_bid_updated(
        current_round.contract_address(),
        option_buyer,
        bid_amount, //Old amount
        bid_price, //Old price
        bid_amount + 1, //Updated amount
        bid_price + 5, //Updated price
        bid_id
    );
    assert(updated_bid.amount == bid_amount + 1, 'Updated amount incorrect');
    assert(updated_bid.price == bid_price + 5, 'Updated price incorrect');
}

// These 2 tests deal with the case where the the bidder is editing their bid to cost them more ETH, but lower
// either their amount or price
// - @note They are purposefully using default errors so we do not forget to discuss this point

#[test]
#[available_gas(50000000)]
fn test_update_bids_amount_cannot_be_decreased_event_if_price_is_increased() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid to lower price and much higer amount (bid total $ > prev total)
    current_round
        .update_bid_expect_error(
            bid_id, bid_amount - 1, 10 * bid_price, bidder, Errors::BidCannotBeDecreased
        );
}

#[test]
#[available_gas(50000000)]
fn test_update_bids_price_cannot_be_decreased_event_if_amount_is_increased() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid to lower price and >> amount
    current_round
        .update_bid_expect_error(
            bid_id, 10 * bid_amount, bid_price - 1, bidder, Errors::BidCannotBeDecreased
        );
}

// Test that bid cannot be updated by a non owner
#[test]
#[available_gas(50000000)]
fn test_update_bids_must_be_called_by_bid_owner() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let non_bidder = option_bidder_buyer_2();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid as non bidder
    current_round
        .update_bid_expect_error(
            bid_id, 10 * bid_amount, bid_price - 1, non_bidder, Errors::CallerNotBidOwner
        );
}

