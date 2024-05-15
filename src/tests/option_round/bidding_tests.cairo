use debug::PrintTrait;
use openzeppelin::{
    token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
        IERC20SafeDispatcherTrait,
    },
    utils::serde::SerializedAppend,
};
use pitch_lake_starknet::{
    eth::Eth,
    vault::{
        IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault,
        IVaultSafeDispatcherTrait, OptionRoundCreated
    },
    option_round::{OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    tests::{
        vault_facade::{VaultFacade, VaultFacadeTrait},
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
        mocks::mock_market_aggregator::{
            MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
            IMarketAggregatorSetterDispatcherTrait
        },
        utils::{
            setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
            timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
            option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
            option_bidder_buyer_4, zero_address, vault_manager, weth_owner,
            option_round_contract_address, mock_option_params, pop_log, assert_no_events_left,
            month_duration, assert_event_auction_bid, assert_event_transfer, clear_event_logs,
            accelerate_to_auctioning, option_bidders_get,
        },
    },
};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};


// @note should just assert x = next_round.place_bid(...) == false
// Test OB cannot bid before the auction starts
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot bid before auction starts', 'ENTRYPOINT_FAILED'))]
fn test_bid_before_auction_starts_failure() {
    let (mut vault_facade, _) = setup_facade();
    // OptionRoundDispatcher
    let mut next_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = next_round.get_params();
    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Clear event logs for bids
    clear_event_logs(array![next_round.contract_address()]);

    // Try to place bid before auction starts
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    next_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid(
        next_round.contract_address(), option_bidder_buyer_1(), bid_amount, option_price
    );
}

// Test OB cannot bid after the auction ends
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Auction over, cannot place bid', 'ENTRYPOINT_FAILED',))]
fn test_bid_after_auction_ends_failure() {
    // Add liq. to next round
    let (mut vault_facade, _) = setup_facade();
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start the next round's auction
    vault_facade.start_auction();
    // Get current round (auctioning)
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();
    // End the auction
    vault_facade.timeskip_and_end_auction();
    // Clear event logs for bids
    clear_event_logs(array![current_round.contract_address()]);

    // Place bid after auction end
    set_block_timestamp(params.auction_end_time + 1);
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid(
        current_round.contract_address(), option_bidder_buyer_1(), bid_amount, option_price
    );
}

// Test OB cannot bid after the auction end date (if .end_auction() not called first)
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Auction over, cannot place bid', 'ENTRYPOINT_FAILED',))]
fn test_bid_after_auction_end_failure_2() {
    // Add liq. to next round
    let (mut vault_facade, _) = setup_facade();
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start the next round's auction
    vault_facade.start_auction();
    // Get current round (auctioning)
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();
    // Jump to after auction end time, but beat the call that ends the round's auction
    set_block_timestamp(params.auction_end_time + 1);
    // Clear event logs for bids
    clear_event_logs(array![current_round.contract_address()]);

    // Place bid after auction end date
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid(
        current_round.contract_address(), option_bidder_buyer_1(), bid_amount, option_price
    );
}

// @note This test should change.
//  - Testing if bids are locked is already in test_option_round_refund_unused_bids_too_early_failure()
//  - The name should change to something like test_bid_eth_transfer
//  - Testing bid accepted events is in separate test (below, test_bid_accepted_events)
#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Clear event logs for eth transfers and bids
    clear_event_logs(array![eth_dispatcher.contract_address]);

    // Eth balances before bid
    let ob_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_before_bid: u256 = eth_dispatcher.balance_of(round_facade.contract_address());

    // Make bid
    let bid_count: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_count * bid_count;
    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());

    // Eth balances after bid
    let ob_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_after_bid: u256 = eth_dispatcher.balance_of(round_facade.contract_address());

    // Check bids went from OB to round
    // @note Maybe just use assert_event_transfer(eth...) to test eth transfer ?
    assert(
        ob_balance_after_bid == ob_balance_before_bid - bid_amount, 'bid did not leave obs account'
    );
    assert(
        round_balance_after_bid == round_balance_after_bid + bid_amount, 'bid did not reach round'
    );

    // Check eth transfer event
    assert_event_transfer(
        eth_dispatcher.contract_address,
        option_bidder_buyer_1(),
        round_facade.contract_address(),
        bid_amount
    );
}

#[test]
#[available_gas(10000000)]
fn test_bid_accepted_events() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // Deposit liquidity, start auction, and place bid
    accelerate_to_auctioning(ref vault_facade);
    // Current round
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Clear event logs for eth transfers and bids
    clear_event_logs(array![eth_dispatcher.contract_address, round_facade.contract_address()]);

    let mut obs = option_bidders_get(5);
    let mut step = 1;
    loop {
        match obs.pop_front() {
            Option::Some(ob) => {
                // Place bid
                let bid_count = step;
                let bid_price = params.reserve_price + step;
                let bid_amount = bid_count * bid_price;
                round_facade.place_bid(bid_amount, bid_price, ob);

                // Check bid accepted event
                assert_event_auction_bid(
                    round_facade.contract_address(), option_bidder_buyer_1(), bid_amount, bid_price
                );

                step += 1;
            },
            Option::None => { break (); }
        };
    };
}

// Test bidding 0 is rejected
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid price must be >= reserve price', 'ENTRYPOINT_FAILED',))]
fn test_bid_zero_amount_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Clear event logs for bids
    clear_event_logs(array![round_facade.contract_address()]);

    // Try to bid 0 amount
    round_facade.place_bid(0, params.reserve_price, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid(
        round_facade.contract_address(), option_bidder_buyer_1(), 0, params.reserve_price
    );
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid price must be >= reserve price', 'ENTRYPOINT_FAILED',))]
fn test_bid_price_below_reserve_price_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Clear event logs for bids
    clear_event_logs(array![round_facade.contract_address()]);

    // Try to bid below reserve price
    round_facade.place_bid(2, params.reserve_price - 1, option_bidder_buyer_1());

    // Check bid rejected event
    assert_event_auction_bid(
        round_facade.contract_address(), option_bidder_buyer_1(), 2, params.reserve_price - 1
    );
}

// @note This test was moved to unused_bids_tests.cairo
// Test that OB cannot refund bids before auction settles
// @dev move to Dhruv's file next resync option_round/unused_bids_tests.cairo
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction is still on-going', 'ENTRYPOINT_FAILED',))]
fn test_option_round_refund_unused_bids_too_early_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    // Get the current (auctioning) round
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();

    // Make bid
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Try to refund bid before auction settles
    current_round_facade.refund_bid(option_bidder_buyer_1());
}
// @note Add test for eth: ob -> round when bidding


