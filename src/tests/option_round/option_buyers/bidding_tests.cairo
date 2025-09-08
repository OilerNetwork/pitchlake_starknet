use core::array::ArrayTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;
use pitch_lake::{
    library::eth::Eth,
    vault::{
        contract::Vault,
        interface::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcherTrait
        }
    },
    option_round::{
        contract::OptionRound::Errors,
        interface::{OptionRoundState, IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    },
    tests::{
        utils::{
            helpers::{
                general_helpers::{
                    multiply_arrays, scale_array, sum_u256_array, get_erc20_balance,
                    get_erc20_balances, get_total_bids_amount, create_array_linear,
                    create_array_gradient, to_wei
                },
                setup::{setup_facade, decimals, deploy_vault, clear_event_logs,},
                accelerators::{
                    accelerate_to_auctioning, timeskip_and_end_auction, accelerate_to_running,
                    accelerate_to_settled, timeskip_past_auction_end_date,
                    accelerate_to_auctioning_custom,
                },
                event_helpers::{
                    assert_event_transfer, assert_event_auction_bid_placed, pop_log,
                    assert_no_events_left,
                }
            },
            lib::test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                option_bidders_get, liquidity_providers_get,
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    },
};
use debug::PrintTrait;

/// Failues ///

// Test bidding 0 amount is rejected
#[test]
#[available_gas(30000000)]
fn test_bid_amount_0_gets_rejected() {
    let (mut vault, _) = setup_facade();
    let _options_available = accelerate_to_auctioning(ref vault);

    // Bid 0 amount
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bidder = option_bidder_buyer_1();
    let bid_price = 2 * reserve_price;
    let bid_amount = 0;

    vault.place_bid_expect_error(bid_amount, bid_price, bidder, Errors::BidAmountZero);
}

// Test bidding price < reserve fails (covers 0 amount as well since 0 is always < reserve price)
#[test]
#[available_gas(50000000)]
fn test_bid_price_below_reserve_fails() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);

    // Bid below reserve price
    let mut current_round = vault_facade.get_current_round();
    let bidder = option_bidder_buyer_1();
    let bid_price = current_round.get_reserve_price() - 1;
    let bid_amount = options_available;
    clear_event_logs(array![current_round.contract_address()]);

    // Check txn revert reason
    vault_facade
        .place_bid_expect_error(bid_amount, bid_price, bidder, Errors::BidBelowReservePrice);
}

// Test bidding before auction starts fails
#[test]
#[available_gas(500000000)]
fn test_bid_before_auction_starts_failure() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 1);

    // Try to place bid before auction starts
    let mut round2 = vault.get_current_round();
    let bidder = option_bidder_buyer_1();
    let bid_price = round2.get_reserve_price();
    let bid_amount = round2.get_total_options_available();
    clear_event_logs(array![round2.contract_address()]);

    // Check txn revert reason
    vault.place_bid_expect_error(bid_amount, bid_price, bidder, Errors::BiddingWhileNotAuctioning);
}

// Test bidding after auction ends fails
#[test]
#[available_gas(5000000000)]
fn test_bid_after_auction_ends_failure() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, current_round.get_strike_price());
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    // Try to place bid after auction ends
    let mut round2 = vault.get_current_round();
    let bidder = option_bidder_buyer_1();
    let bid_price = round2.get_reserve_price();
    let bid_amount = round2.get_total_options_available();

    clear_event_logs(array![round2.contract_address()]);

    // Check txn revert reason
    vault.place_bid_expect_error(bid_amount, bid_price, bidder, Errors::BiddingWhileNotAuctioning);
}

// Test bidding after auction end date fail (if end_auction() is not called first)
#[test]
#[available_gas(500000000)]
fn test_bid_after_auction_end_failure_2() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 1);
    accelerate_to_auctioning(ref vault);
    timeskip_past_auction_end_date(ref vault);
    let mut round2 = vault.get_current_round();

    // Try to place bid after auction end date (before entry point called)
    let bidder = option_bidder_buyer_1();
    let bid_price = round2.get_reserve_price();
    let bid_amount = round2.get_total_options_available();
    clear_event_logs(array![round2.contract_address()]);

    vault.place_bid_expect_error(bid_amount, bid_price, bidder, Errors::BiddingWhileNotAuctioning);
}

// Test bidding fails if no options available
#[test]
#[available_gas(500000000)]
fn test_bidding_no_options_fail() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning_custom(
        ref vault, liquidity_providers_get(2).span(), array![0, 0].span()
    );

    vault
        .place_bid_expect_error(
            1234,
            current_round.get_reserve_price(),
            liquidity_provider_1(),
            Errors::NoOptionsToBidFor
        );
}

/// Event Tests ///
// @dev bid rejected events are covered in the failure tests
// @dev i don't think events fire when a txn reverts, are bid rejected events needed due to this ?
//   - our facade throws a panic if the entry point returns a Vault/OptionRoundError

// Test bid accepted events
#[test]
#[available_gas(500000000)]
fn test_bid_accepted_events() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let mut option_bidders = option_bidders_get(3).span();
    let mut bid_amounts = create_array_linear(options_available, 3).span();
    let mut bid_prices = create_array_gradient(reserve_price, reserve_price, 3).span();
    clear_event_logs(array![vault_facade.contract_address()]);
    let mut bids = vault_facade.place_bids(bid_amounts, bid_prices, option_bidders);

    // Check bid accepted events
    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                let bid = bids.pop_front().unwrap();
                let bid_id = bid.bid_id;
                let tree_nonce = bid.tree_nonce;
                let bid_amount = bid_amounts.pop_front().unwrap();
                let bid_price = bid_prices.pop_front().unwrap();
                assert_event_auction_bid_placed(
                    vault_facade.contract_address(),
                    *ob,
                    bid_id,
                    *bid_amount,
                    *bid_price,
                    tree_nonce + 1,
                    current_round.get_round_id(),
                    current_round.contract_address()
                );
            },
            Option::None => { break; }
        };
    }
}

// Test get_bids_for returns the correct array of bids
// @note circle back once we change array to returning [A, B, C] (current is C, B, A)
#[test]
#[available_gas(500000000)]
fn test_get_bids_for() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round = vault_facade.get_current_round();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let reserve_price = current_round.get_reserve_price();

    // Place bids (bidder 1 places 2 bids)
    let mut option_bidders = option_bidders_get(3);
    option_bidders.append(option_bidder_buyer_1());
    let mut option_bidders = option_bidders.span();

    let mut bid_amounts = create_array_gradient(options_available, 123, 4).span();
    let mut bid_prices = create_array_gradient(reserve_price, reserve_price, 4).span();
    let bids = vault_facade.place_bids(bid_amounts, bid_prices, option_bidders);

    // Check bid arrays
    let bids1 = current_round.get_bids_for(*option_bidders[0]);
    let bids2 = current_round.get_bids_for(*option_bidders[1]);
    let bids3 = current_round.get_bids_for(*option_bidders[2]);

    assert(bids1 == array![*bids[0], *bids[3]], 'Bids 1 mismatch');
    assert(bids2 == array![*bids[1]], 'Bids 2 mismatch');
    assert(bids3 == array![*bids[2]], 'Bids 3 mismatch');
}

/// Liquidity Tests ///

// Test bidding transfers eth from bidder to round
#[test]
#[available_gas(500000000)]
fn test_bid_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Eth balances before bid
    let mut option_bidders = option_bidders_get(3).span();
    let mut ob_balances_before = get_erc20_balances(eth.contract_address, option_bidders).span();
    let round_balance_before = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    // Place bids
    let mut bid_prices = create_array_gradient(reserve_price, reserve_price, 3).span();
    let mut bid_amounts = create_array_linear(options_available, 3).span();
    let bids_total = get_total_bids_amount(bid_prices, bid_amounts);
    let bids = vault_facade.place_bids(bid_amounts, bid_prices, option_bidders);
    // Eth balances after bid
    let mut ob_balances_after = get_erc20_balances(eth.contract_address, option_bidders).span();
    let round_balance_after = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );

    assert(round_balance_after == round_balance_before + bids_total, 'round balance after wrong');
    // Check ob balances
    loop {
        match ob_balances_before.pop_front() {
            Option::Some(ob_balance_before) => {
                let ob_bid_price = bid_prices.pop_front().unwrap();
                let ob_balance_after = ob_balances_after.pop_front().unwrap();
                let ob_amount = bid_amounts.pop_front().unwrap();
                assert(
                    *ob_balance_after == *ob_balance_before - (*ob_bid_price * *ob_amount),
                    'ob balance after wrong'
                );
            },
            Option::None => { break; }
        };
    }
}

///// Test bidding transfers eth from bidder to round
//#[test]
//#[available_gas(500000000)]
///fn test_bid_0_reserve_price() {
//    let (mut vault, eth) = setup_facade();
//    let mut current_round = vault.get_current_round();
//
//    // Mock auction params
//    let options_available = to_wei(1, current_round.decimals());
//    let reserve_price = 1234567;
//    current_round.setup_mock_auction(ref vault, options_available, reserve_price);
//
//    // Eth balances before bid
//    let mut option_bidders = option_bidders_get(3).span();
//    let mut ob_balances_before = get_erc20_balances(eth.contract_address, option_bidders).span();
//    let round_balance_before = get_erc20_balance(
//        eth.contract_address, current_round.contract_address()
//    );
//
//    // Place bids
//    let mut bid_prices = create_array_gradient(reserve_price, reserve_price, 3).span();
//    let mut bid_amounts = create_array_linear(options_available, 3).span();
//    let bids_total = get_total_bids_amount(bid_prices, bid_amounts);
//    current_round.place_bids(bid_amounts, bid_prices, option_bidders);
//
//    // Eth balances after bid
//    let mut ob_balances_after = get_erc20_balances(eth.contract_address, option_bidders).span();
//    let round_balance_after = get_erc20_balance(
//        eth.contract_address, current_round.contract_address()
//    );
//
//    //println!(
//    //    "options_available:{}\nreserve_price:{}",
//    //    current_round.get_total_options_available(),
//    //    current_round.get_reserve_price()
//    //);
//    //println!("bid amounts: {:?}", bid_amounts);
//    //println!("bid prices: {:?}", bid_prices);
//
//    assert(round_balance_after == round_balance_before + bids_total, 'round balance after wrong');
//    // Check ob balances
//    loop {
//        match ob_balances_before.pop_front() {
//            Option::Some(ob_balance_before) => {
//                //let ob_bid_price = bid_prices.pop_front().unwrap();
//                let ob_balance_after = ob_balances_after.pop_front().unwrap();
//                //let ob_amount = bid_amounts.pop_front().unwrap();
//                assert(*ob_balance_after == *ob_balance_before, 'ob balance after wrong');
//            },
//            Option::None => { break; }
//        };
//    }
//}

/// Nonce Tests ///

// Test bidding updates bid nonce
#[test]
#[available_gas(500000000)]
fn test_bidding_updates_bid_nonce() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();

    // Bid parameters
    let bidder = option_bidder_buyer_1();
    let mut bid_amount = options_available;
    let bid_price = current_round.get_reserve_price();

    let mut i: u256 = 0;
    while i < 3 {
        let nonce_before = current_round.get_bidding_nonce_for(bidder);
        vault_facade.place_bid(bid_amount, bid_price, bidder);
        let nonce_after = current_round.get_bidding_nonce_for(bidder);
        assert(nonce_before + 1 == nonce_after, 'Nonce Mismatch');
        i += 1;
    };
}

// Test failed bids do not update bid nonce
#[test]
#[available_gas(500000000)]
fn test_failed_bid_nonce_unchanged() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Bid parameters
    let bidder = *option_bidders_get(1)[0];

    let bid_price = reserve_price;
    let mut bid_amount = options_available;

    let mut i: u256 = 0;
    while i < 10 {
        let nonce_before = current_round.get_bidding_nonce_for(bidder);
        if (i % 2 == 1) {
            //Failed bid in alternate rounds and check nonce update
            let _ = vault_facade
                .place_bid_expect_error(
                    bid_amount, bid_price - 1, bidder, Errors::BidBelowReservePrice
                );
            let nonce_after = current_round.get_bidding_nonce_for(bidder);
            assert(nonce_before == nonce_after, 'Nonce Mismatch');
        } else {
            vault_facade.place_bid(bid_amount, bid_price, bidder);
        }

        i += 1;
    };
}

// Test bid hashes match expected hash
#[test]
#[available_gas(500000000)]
fn test_place_bid_id() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();

    // Bid parameters
    let bidder = option_bidder_buyer_1();

    let bid_amount = options_available;
    let bid_price = current_round.get_reserve_price();

    // Place bids and check bid hashes
    let mut i = 3_u32;
    while i > 0 {
        let bid_nonce = current_round.get_bidding_nonce_for(bidder);
        let expected_hash = poseidon::poseidon_hash_span(
            array![bidder.into(), bid_nonce.into()].span()
        );
        let bid = vault_facade.place_bid(bid_amount, bid_price, bidder);
        assert(bid.bid_id == expected_hash, 'Bid Id Incorrect');
        i -= 1;
    };
}
// @note Test bids are placed in pending bids
// - Might need to revist pending bids entry point, shd return array of bid ids/hashes now


