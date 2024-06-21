use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::{
    token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
        IERC20SafeDispatcherTrait,
    },
};
use pitch_lake_starknet::{
    contracts::{
        eth::Eth,
        vault::{
            IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
            IVaultSafeDispatcherTrait
        },
        option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    },
    tests::{
        utils::{
            helpers::{
                general_helpers::{
                    multiply_arrays, scale_array, sum_u256_array, get_erc20_balance,
                    get_erc20_balances
                },
                setup::{setup_facade, decimals, deploy_vault, clear_event_logs,},
                accelerators::{
                    accelerate_to_auctioning, timeskip_and_end_auction, accelerate_to_running,
                    accelerate_to_settled, timeskip_past_auction_end_date,
                },
                event_helpers::{
                    assert_event_transfer, assert_event_auction_bid_accepted,
                    assert_event_auction_bid_rejected, pop_log, assert_no_events_left,
                }
            },
            lib::test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                option_bidders_get,
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
            mocks::mock_market_aggregator::{
                MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
                IMarketAggregatorSetterDispatcherTrait
            },
            utils::{
                multiply_arrays, scale_array, sum_u256_array, get_erc20_balance, get_erc20_balances,
                get_total_bids_amount, create_array_linear
            },
        },
    },
};
use debug::PrintTrait;

/// Failues ///

// Test bidding when total options to buy is 0 is rejected
#[test]
#[available_gas(10000000)]
fn test_bid_amount_0_fails() {
    let (mut vault, _) = setup_facade();
    let _options_available = accelerate_to_auctioning(ref vault);

    // Bid 0 amount
    let mut current_round = vault.get_current_round();
    let reserve_price = current_round.get_reserve_price();
    let bidder = option_bidder_buyer_1();
    let bid_price = 2 * reserve_price;
    let bid_amount = 0;
    clear_event_logs(array![current_round.contract_address()]);
    match current_round.place_bid_raw(bid_amount, bid_price, bidder) {
        Result::Ok(_) => { panic!("Bid should have failed"); },
        Result::Err(_) => {
            // Check bid rejected event
            assert_event_auction_bid_rejected(
                current_round.contract_address(), bidder, bid_amount, bid_price
            );
        }
    }
}

// Test bidding price < reserve fails
#[test]
#[available_gas(10000000)]
fn test_bid_price_below_reserve_fails() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);

    // Bid below reserve price
    let mut current_round = vault_facade.get_current_round();
    let bidder = option_bidder_buyer_1();
    let bid_price = current_round.get_reserve_price() - 1;
    let bid_amount = options_available;
    clear_event_logs(array![current_round.contract_address()]);
    match current_round.place_bid_raw(bid_amount, bid_price, bidder) {
        Result::Ok(_) => { panic!("Bid should have failed"); },
        Result::Err(_) => {
            // Check bid rejected event
            assert_event_auction_bid_rejected(
                current_round.contract_address(), bidder, bid_amount, bid_price
            );
        }
    }
}

// Test bidding before auction starts fails
#[test]
#[available_gas(10000000)]
fn test_bid_before_auction_starts_failure() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 0);

    // Try to place bid before auction starts
    let (_round1, mut round2) = vault.get_current_and_next_rounds();
    let bidder = option_bidder_buyer_1();
    // let bid_count = round2.get_total_options_available();
    let bid_price = round2.get_reserve_price();
    let bid_amount = round2.get_total_options_available();
    clear_event_logs(array![round2.contract_address()]);
    match round2.place_bid_raw(bid_amount, bid_price, option_bidder_buyer_1()) {
        Result::Ok(_) => { panic!("Bid should have failed"); },
        Result::Err(_) => {
            // Check bid rejected event
            assert_event_auction_bid_rejected(
                round2.contract_address(), bidder, bid_amount, bid_price
            );
        }
    }
}

// Test bidding after auction ends fails
#[test]
#[available_gas(10000000)]
fn test_bid_after_auction_ends_failure() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 0);
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    // Try to place bid after auction ends
    let (mut round2, _round3) = vault.get_current_and_next_rounds();
    let bidder = option_bidder_buyer_1();
    let bid_price = round2.get_reserve_price();
    let bid_amount = round2.get_total_options_available();
    clear_event_logs(array![round2.contract_address()]);
    match round2.place_bid_raw(bid_amount, bid_price, option_bidder_buyer_1()) {
        Result::Ok(_) => { panic!("Bid should have failed"); },
        Result::Err(_) => {
            // Check bid rejected event
            assert_event_auction_bid_rejected(
                round2.contract_address(), bidder, bid_amount, bid_price
            );
        }
    }
}

// Test bidding after auction end date fail (if end_auction() is not called first)
#[test]
#[available_gas(10000000)]
fn test_bid_after_auction_end_failure_2() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 0);
    accelerate_to_auctioning(ref vault);
    timeskip_past_auction_end_date(ref vault);
    let (mut round2, _round3) = vault.get_current_and_next_rounds();

    // Try to place bid after auction end date (before entry point called)
    let bidder = option_bidder_buyer_1();
    let bid_price = round2.get_reserve_price();
    let bid_amount = round2.get_total_options_available();
    clear_event_logs(array![round2.contract_address()]);
    match round2.place_bid_raw(bid_amount, bid_price, option_bidder_buyer_1()) {
        Result::Ok(_) => { panic!("Bid should have failed"); },
        Result::Err(_) => {
            // Check bid rejected event
            assert_event_auction_bid_rejected(
                round2.contract_address(), bidder, bid_amount, bid_price
            );
        }
    }
}

/// Event Tests ///
// @dev bid rejected events happen in the failure tests
// @dev i don't think events fire when a txn reverts, are bid rejected events needed due to this ?
//   - our facade throws a panic if the entry point returns a Vault/OptionRoundError

// Test bid accepted events
#[test]
#[available_gas(10000000)]
fn test_bid_accepted_events() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Place bids
    let mut option_bidders = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let mut bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = create_array_linear(options_available, 3).span();
    clear_event_logs(array![current_round.contract_address()]);
    current_round.place_bids(bid_amounts, bid_prices, option_bidders);

    // Check bid accepted events
    loop {
        match option_bidders.pop_front() {
            Option::Some(ob) => {
                let bid_amount = bid_amounts.pop_front().unwrap();
                let bid_price = bid_prices.pop_front().unwrap();
                assert_event_auction_bid_accepted(
                    current_round.contract_address(), *ob, *bid_amount, *bid_price
                );
            },
            Option::None => { break; }
        };
    }
}

/// Liquidity Tests ///

// Test bidding transfers eth from bidder to round
#[test]
#[available_gas(10000000)]
fn test_bid_eth_transfer() {
    let (mut vault_facade, eth) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Eth balances before bid
    let mut option_bidders = option_bidders_get(3).span();
    let scale = array![1, 2, 3].span();
    let mut ob_balances_before = get_erc20_balances(eth.contract_address, option_bidders).span();
    let round_balance_before = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );
    // Place bids
    let mut bid_prices = scale_array(scale, reserve_price).span();
    let mut bid_amounts = create_array_linear(options_available, 3).span();
    let bids_total = get_total_bids_amount(bid_prices, bid_amounts);
    current_round.place_bids(bid_amounts, bid_prices, option_bidders);
    // Eth balances after bid
    let mut ob_balances_after = get_erc20_balances(eth.contract_address, option_bidders).span();
    let round_balance_after = get_erc20_balance(
        eth.contract_address, current_round.contract_address()
    );

    // Check round balance
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
// @note Test bids are placed in pending bids

// Nonce Tests //
#[test]
#[available_gas(10000000)]
fn test_bid_updates_nonce() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Bid parameters
    let bid_price = reserve_price;
    let mut bid_amount = options_available;

    let mut i: u256 = 0;
    while i < 3 {
        let nonce_before = current_round.get_nonce_for(option_bidder_buyer_1());
        current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
        let nonce_after = current_round.get_nonce_for(option_bidder_buyer_1());
        assert(nonce_before + 1 == nonce_after, 'Nonce Mismatch');
        i += 1;
    };
// Nonce after bid

}


fn test_failed_bid_nonce_unchanged() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Bid parameters
    let bid_price = reserve_price;
    let mut bid_amount = options_available;

    let mut i: u256 = 0;
    while i < 10 {
        let nonce_before = current_round.get_nonce_for(option_bidder_buyer_1());
        if (i % 2 == 1) {
            //Failed bid in alternate rounds and check nonce update
            current_round.place_bid(bid_amount, bid_price - 1, option_bidder_buyer_1());
            let nonce_after = current_round.get_nonce_for(option_bidder_buyer_1());
            assert(nonce_before == nonce_after, 'Nonce Mismatch');
        } else {
            current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
        }

        i += 1;
    };
}


#[test]
#[available_gas(10000000)]
fn test_place_bid_id() {
    let (mut vault_facade, _) = setup_facade();
    let options_available = accelerate_to_auctioning(ref vault_facade);
    let mut current_round = vault_facade.get_current_round();
    let reserve_price = current_round.get_reserve_price();

    // Nonce before bid
    let nonce: felt252 = current_round.get_nonce_for(option_bidder_buyer_1()).into();

    // Place bids
    let bid_price = reserve_price;
    let mut bid_amount = options_available;
    let bid_id = current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    let hash = poseidon::poseidon_hash_span(array![option_bidder_buyer_1().into(), nonce].span());
    assert(nonce == hash, 'Bid Id Incorrect');
}
