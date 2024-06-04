use starknet::testing::{set_block_timestamp, set_contract_address};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
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
        utils::{scale_array, get_erc20_balance, get_erc20_balances,},
    },
};

/// Failures ///

// Test collecting 0 unused bids fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('No unused bids to collect', 'ENTRYPOINT_FAILED',))]
fn test_collecting_0_unused_bids_fails() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let mut current_round = vault.get_current_round();

    // Try to collect unused bids when there is none to collect (ob's entire bid converted to premium)
    current_round.refund_bid(option_bidder_buyer_1());
}

// Test collecting bids before the auction ends fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction is still on-going', 'ENTRYPOINT_FAILED',))]
fn test_option_round_refund_unused_bids_too_early_failure() {
    let (mut vault, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    // Place bid
    let ob = option_bidder_buyer_1();
    let bid_price = reserve_price;
    let bid_amount = reserve_price * options_available;
    current_round.place_bid(bid_amount, bid_price, ob);
    current_round.refund_bid(ob);
}

/// Event Tests ///

// Test collecting unused bids emits event correctly
#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_events() {
    let (mut vault, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    // Place bids
    let mut obs = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = scale_array(bid_prices, options_available).span();
    current_round.place_bids(bid_amounts, bid_prices, obs);
    // OB4 outbids all other OBs
    // @dev So that OB1, 2 & 3 have unused bids to collect
    let ob4 = option_bidder_buyer_4();
    let bid_price4 = 4 * reserve_price;
    let bid_amount4 = bid_price4 * options_available;
    current_round.place_bid(bid_amount4, bid_price4, ob4);
    timeskip_and_end_auction(ref vault);

    // Collect unused bids and check event emits correctly
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                let bid_amount = bid_amounts.pop_front().unwrap();
                current_round.refund_bid(*ob);
                assert_event_unused_bids_refunded(
                    current_round.contract_address(), *ob, *bid_amount
                );
            },
            Option::None => { break; }
        }
    }
}

/// State Tests ///

/// Unused & Used Bids

// Test unused bid balance before auction ends
#[test]
#[available_gas(10000000)]
fn test_unused_bids_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let mut obs = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = scale_array(bid_prices, options_available).span();
    current_round.place_bids(bid_amounts, bid_prices, obs);

    // Check OB unused bid balances
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                let unused_bid_balance = current_round.get_unused_bids_for(*ob);
                let bid_amount = bid_amounts.pop_front().unwrap();
                assert(unused_bid_balance == *bid_amount, 'unused bid balance wrong');
            },
            Option::None => { break; }
        }
    }
}

// Test unused bid balance after auction ends
#[test]
#[available_gas(10000000)]
fn test_unused_bids_after_auction_end() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let mut obs = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = scale_array(bid_prices, options_available).span();
    current_round.place_bids(bid_amounts, bid_prices, obs);
    // OB4 outbids all other OBs
    let ob4 = option_bidder_buyer_4();
    let bid_price4 = 4 * reserve_price;
    let bid_amount4 = bid_price4 * options_available;
    current_round.place_bid(bid_amount4, bid_price4, ob4);
    timeskip_and_end_auction(ref vault_facade);

    // Check OB 1, 2 & 3's bids are all refundable, and LP4' are not
    assert(current_round.get_unused_bids_for(ob4) == 0, 'lp4 unused bids shd be 0');
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                let unused_bid_balance = current_round.get_unused_bids_for(*ob);
                let bid_amount = bid_amounts.pop_front().unwrap();
                assert(unused_bid_balance == *bid_amount, 'unused bid balance wrong');
            },
            Option::None => { break; }
        }
    }
}

/// Collecting Unused Bids

// Test collecting unused bids sets unused bid balance to 0
#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_sets_unused_balance_to_0() {
    let (mut vault, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    // Place bids
    let mut obs = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = scale_array(bid_prices, options_available).span();
    current_round.place_bids(bid_amounts, bid_prices, obs);
    // OB4 outbids all other OBs
    // @dev So that OB1, 2 & 3 have unused bids to collect
    let ob4 = option_bidder_buyer_4();
    let bid_price4 = 4 * reserve_price;
    let bid_amount4 = bid_price4 * options_available;
    current_round.place_bid(bid_amount4, bid_price4, ob4);
    timeskip_and_end_auction(ref vault);
    // Collect unused bids
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                current_round.refund_bid(*ob);
                let unused_bid_balance = current_round.get_unused_bids_for(*ob);
                assert(unused_bid_balance == 0, 'unused bid balance should be 0');
            },
            Option::None => { break; }
        }
    }
}

// Test eth transfer when collecting unused bids
#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault);
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    // Place bids
    let mut obs = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = scale_array(bid_prices, options_available).span();
    current_round.place_bids(bid_amounts, bid_prices, obs);
    // OB4 outbids all other OBs
    // @dev So that OB1, 2 & 3 have unused bids to collect
    let ob4 = option_bidder_buyer_4();
    let bid_price4 = 4 * reserve_price;
    let bid_amount4 = bid_price4 * options_available;
    current_round.place_bid(bid_amount4, bid_price4, ob4);
    timeskip_and_end_auction(ref vault);

    // Eth balance before
    let mut total_unused_bids = 0;
    let round_balance_before = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    // Collect unused bids
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                let ob_balance_before = get_erc20_balance(eth.contract_address, *ob);
                let refund_amount = current_round.get_unused_bids_for(*ob);
                current_round.refund_bid(*ob);
                let ob_balance_after = get_erc20_balance(eth.contract_address, *ob);
                assert(ob_balance_after == ob_balance_before + refund_amount, 'ob shd receive eth');
                total_unused_bids += refund_amount;
            },
            Option::None => { break; }
        }
    };
    let round_balance_after = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    assert(round_balance_after == round_balance_before - total_unused_bids, 'round should lose eth')
}
