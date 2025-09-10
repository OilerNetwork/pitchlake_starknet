use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running_custom, timeskip_and_end_auction,
};
use pitch_lake::tests::utils::helpers::general_helpers::{
    create_array_gradient, create_array_linear,
};
use pitch_lake::tests::utils::helpers::setup::{setup_facade, setup_test_auctioning_bidders};
use pitch_lake::tests::utils::lib::test_accounts::{option_bidder_buyer_1, option_bidders_get};
use pitch_lake::types::Bid;
use starknet::ContractAddress;


// Deploy vault, start auction, and place incremental bids
fn place_incremental_bids_internal(
    ref vault: VaultFacade, option_bidders: Span<ContractAddress>,
) -> (Span<u256>, Span<u256>, OptionRoundFacade, Span<Bid>) {
    let mut current_round = vault.get_current_round();
    let number_of_option_bidders = option_bidders.len();
    let options_available = current_round.get_total_options_available();
    let option_reserve_price = current_round.get_reserve_price();

    // @dev Bids start at reserve price and increment by reserve price
    let bid_prices = create_array_gradient(
        option_reserve_price, option_reserve_price, number_of_option_bidders,
    );

    // @dev Bid amounts are each bid price * the number of options available
    let mut bid_amounts = create_array_linear(options_available, bid_prices.len());

    // Place bids
    let bids = current_round.place_bids(bid_amounts.span(), bid_prices.span(), option_bidders);
    (bid_amounts.span(), bid_prices.span(), current_round, bids.span())
}


/// Refundable Bids Tests ///

// Test refundable bid balance before auction ends
#[test]
#[available_gas(500000000)]
fn test_refundable_bids_before_auction_end() {
    let number_of_option_bidders = 3;
    let (mut vault, _, mut option_bidders, _) = setup_test_auctioning_bidders(
        number_of_option_bidders,
    );

    // Each option buyer out bids the next
    let (_, _, mut current_round, _) = place_incremental_bids_internal(ref vault, option_bidders);

    // Check refunded bid balance is 0 for each bidder
    for ob in option_bidders {
        let refundable_amount = current_round.get_refundable_balance_for(*ob);
        assert(refundable_amount == 0, 'refunded bid shd be 0');
    }
    //    loop {
//        match option_bidders.pop_front() {
//            Option::Some(bidder) => {
//                let refundable_amount = current_round.get_refundable_balance_for(*bidder);
//                assert(refundable_amount == 0, 'refunded bid shd be 0');
//            },
//            Option::None => { break; },
//        }
//    }
}

// Test refundable bid balance after auction ends
#[test]
#[available_gas(500000000)]
fn test_refundable_bids_after_auction_end() {
    let number_of_option_bidders = 3;
    let (mut vault, _, mut option_bidders, _) = setup_test_auctioning_bidders(
        number_of_option_bidders,
    );

    // Each option buyer out bids the next
    let (mut bid_amounts, mut bid_prices, mut current_round, _) = place_incremental_bids_internal(
        ref vault, option_bidders,
    );

    // End auction
    timeskip_and_end_auction(ref vault);

    // Pop last bidder from array because their bids are not refundable
    match option_bidders.pop_back() {
        Option::Some(_) => {
            // Check refunded bid balance for each losing bidder
            for i in 0..option_bidders.len() {
                let ob = option_bidders[i];
                let refunded_amount = current_round.get_refundable_balance_for(*ob);
                let bid_amount: u256 = *bid_amounts[i];
                let bid_price = *bid_prices[i];
                assert(refunded_amount == bid_amount * bid_price, 'refunded bid balance wrong');
            }
            //loop {
        //     match option_bidders.pop_front() {
        //         Option::Some(bidder) => {
        //             let refunded_amount = current_round.get_refundable_balance_for(*bidder);
        //             let bid_amount = bid_amounts.pop_front().unwrap();
        //             let bid_price = bid_prices.pop_front().unwrap();
        //             assert(
        //                 refunded_amount == (*bid_amount) * (*bid_price),
        //                 'refunded bid balance wrong',
        //             );
        //         },
        //         Option::None => { break; },
        //     }
        // }
        },
        Option::None => { panic!("this should not panic") },
    }
}

// Test refundable bids sums partial and fully refundable bids
#[test]
#[available_gas(100000000)]
fn test_refundable_bids_includes_partial_and_fully_refunded_bids() {
    let (mut vault, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    // Same bidder places 4 bids, first 2 are fully used, 3rd is partially used, and 4th is fully
    // unused
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
        current_round.get_refundable_balance_for(bidder) == total_refundable_amount,
        'refunable amount wrong',
    );
}

// Test over bids are refundable
#[test]
#[available_gas(500000000)]
fn test_over_bids_are_refundable() {
    let (mut vault, _) = setup_facade();
    // Deposit liquidity and start the auction
    let total_options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();

    // 2 bidders bid for combined all options, the bidder with the higher price should get a refund
    let mut bidders = option_bidders_get(2).span();
    let reserve_price = current_round.get_reserve_price();
    let bid_amount = total_options_available / 2;
    let bid_amounts = create_array_linear(bid_amount, 2).span();
    let bid_prices = create_array_gradient(reserve_price, reserve_price, 2).span();
    accelerate_to_running_custom(ref vault, bidders, bid_amounts, bid_prices);

    // Check that the first bidder gets no refund, and the second bidder gets a partial refund
    assert(current_round.get_refundable_balance_for(*bidders[0]) == 0, 'ob1 shd get no refunds');
    assert(
        current_round.get_refundable_balance_for(*bidders[1]) == reserve_price * bid_amount,
        'ob2 shd have a partial refund',
    );
}
