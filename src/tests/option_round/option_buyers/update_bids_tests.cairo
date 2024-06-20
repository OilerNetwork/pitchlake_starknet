use core::traits::Into;
use pitch_lake_starknet::{
    contracts::{option_round::{OptionRound::OptionRoundError}},
    tests::{
        utils::{
            test_accounts::{option_bidder_buyer_1}, accelerators::{accelerate_to_auctioning,},
            test_accounts::{option_bidders_get}, variables::{decimals}, setup::{setup_facade},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
            },
        },
    }
};
#[test]
#[available_gas(10000000)]
fn test_update_bids_amount_cannot_be_decreased() {
    let (mut vault_facade, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let option_buyer = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, option_buyer);

    // Update bid to lower price
    let expected_error: felt252 = OptionRoundError::BidCannotBeDecreased('amount').into();
    let res = current_round.update_bid_raw(bid_id, bid_amount - 1, bid_price);
    match res {
        Result::Ok(_) => panic!("Error expected"),
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}


#[test]
#[available_gas(10000000)]
fn test_update_bids_price_cannot_be_decreased() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let option_buyer = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, option_buyer);

    // Update bid to lower price
    let expected_error: felt252 = OptionRoundError::BidCannotBeDecreased('price').into();
    let res = current_round.update_bid_raw(bid_id, bid_amount, bid_price - 1);
    match res {
        Result::Ok(_) => panic!("Error expected"),
        Result::Err(err) => { assert(err.into() == expected_error, 'Error Mismatch') }
    }
}

#[test]
#[available_gas(10000000)]
fn test_update_bids_price_amount() {
    let (mut vault_facade, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let option_buyer = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let mut bid_amount = options_available / 2;
    let bid_id = current_round.place_bid(bid_amount, bid_price, option_buyer);

    // Update bid
    current_round.update_bid(bid_id, bid_amount + 1, bid_price + 5 * decimals());
    let updated_bid = current_round.get_bid_details(bid_id);
    assert(updated_bid.amount == bid_amount + 1, 'Updated amount incorrect');
    assert(updated_bid.price == bid_price + 5 * decimals(), 'Updated price incorrect');
}

