use core::traits::Into;
use pitch_lake::{
    option_round::contract::OptionRound::Errors,
    tests::{
        utils::{
            helpers::{
                setup::{setup_facade},
                accelerators::{accelerate_to_auctioning, timeskip_and_end_auction},
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
fn test_update_bids_price_increase_cannot_be_0() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid to lower price
    current_round.update_bid_expect_error(bid.bid_id, 0, bidder, Errors::BidMustBeIncreased);
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
    let bid = current_round.place_bid(bid_amount, bid_price, option_buyer);
    clear_event_logs(array![current_round.contract_address()]);

    let updated_bid = current_round.update_bid(bid.bid_id, 5);
    assert_event_auction_bid_updated(
        current_round.contract_address(),
        option_buyer,
        bid.bid_id,
        5, //Updated amount
        current_round.get_bid_tree_nonce(),
    );
    assert(updated_bid.amount == bid_amount, 'Amount shd not change');
    assert(updated_bid.price == bid_price + 5, 'Updated price incorrect');
}

#[test]
#[available_gas(80000000)]
fn test_update_bid_nonces() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round = vault_facade.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let option_buyer = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available / 2;
    let bid1 = current_round.place_bid(bid_amount, bid_price, option_buyer);
    current_round.place_bid(bid_amount, bid_price, option_buyer);
    current_round.place_bid(bid_amount, bid_price, option_buyer);
    clear_event_logs(array![current_round.contract_address()]);

    let bidder_nonce_before = current_round.get_bidding_nonce_for(option_buyer);
    let tree_nonce_before = current_round.get_bid_tree_nonce();
    current_round.update_bid(bid1.bid_id, 10000000000000);
    let bidder_nonce_after = current_round.get_bidding_nonce_for(option_buyer);
    let tree_nonce_after = current_round.get_bid_tree_nonce();
    assert(bidder_nonce_before == bidder_nonce_after, 'Bidder nonce should not change');
    assert(tree_nonce_before + 1 == tree_nonce_after, 'Tree nonce should change');

    assert_eq!(bidder_nonce_after, 3);
    assert_eq!(tree_nonce_after, 4);
}
// Test that bid cannot be updated by a non owner
#[test]
#[available_gas(50000000)]
fn test_update_bids_must_be_called_by_bid_owner() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round = vault_facade.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let non_bidder = option_bidder_buyer_2();
    let bid_price = reserve_price;
    let bid_amount = options_available;
    let bid = current_round.place_bid(bid_amount, bid_price, bidder);

    // Update bid as non bidder
    current_round.update_bid_expect_error(bid.bid_id, 1, non_bidder, Errors::CallerNotBidOwner);
}

// Test that updating bids keeps get_bids_for working as expected
#[test]
#[available_gas(100000000)]
fn test_updating_bids_and_get_bids_for() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let bid_amount = options_available;
    let bid1 = current_round.place_bid(bid_amount, bid_price, bidder);
    let bid2 = current_round.place_bid(bid_amount + 1, bid_price + 1, bidder);
    let bid3 = current_round.place_bid(bid_amount + 2, bid_price + 2, bidder);

    // Edit bid 3, should not change order or amount of bids
    let bid4 = current_round.update_bid(bid3.bid_id, 3);

    let expected_bids = array![bid1, bid2, bid4];
    let actual_bids = current_round.get_bids_for(bidder);

    assert(actual_bids == expected_bids, 'bids do not match');
}


// Test later bid higher price wins
// Test later bid same price higher amount loses

#[test]
#[available_gas(70000000)]
fn test_updating_bids_higher_price_wins() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bidder2 = option_bidder_buyer_2();

    let bid_price = 2 * reserve_price;
    let bid_amount = (3 * options_available) / 4;

    // Bid 1 == Bid 2
    let _bid1 = current_round.place_bid(bid_amount, bid_price - 1, bidder);
    let bid2 = current_round.place_bid(bid_amount, bid_price - 2, bidder2);

    // Update Bid 2 to be > than Bid 1
    let _bid2 = current_round.update_bid(bid2.bid_id, 4);

    timeskip_and_end_auction(ref vault);

    let options_for1 = current_round.get_mintable_options_for(bidder);
    let options_for2 = current_round.get_mintable_options_for(bidder2);

    let expected_2 = (3 * options_available) / 4;
    let expected_1 = options_available - expected_2;

    assert_eq!(options_for1, expected_1, "Bidder 1 options wrong");
    assert_eq!(options_for2, expected_2, "Bidder 2 options wrong");
}

#[test]
#[available_gas(70000000)]
fn test_updating_bids_lower_tree_index_loses() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault);
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let bidder = option_bidder_buyer_1();
    let bidder2 = option_bidder_buyer_2();
    let amount = (3 * options_available) / 4;

    // Bid 1 amount > Bid 2 amount, Bid 1 price < Bid 2 price, Bid 2 is ranked higher because of
    // price
    let bid1 = current_round.place_bid(amount, reserve_price, bidder);
    let _bid2 = current_round.place_bid(amount / 2, reserve_price + 1, bidder2);

    // Update Bid 1 to be same price as Bid 2. Bid 2 ranked higher because of tree nonce still
    current_round.update_bid(bid1.bid_id, 1);

    timeskip_and_end_auction(ref vault);

    let options_for1 = current_round.get_mintable_options_for(bidder);
    let options_for2 = current_round.get_mintable_options_for(bidder2);

    assert_eq!(options_for1, options_available - (amount / 2), "Bidder 1 options wrong");
    assert_eq!(options_for2, amount / 2, "Bidder 2 options wrong");
}
