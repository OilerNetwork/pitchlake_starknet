use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    OptionRoundCreated
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left, month_duration
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};

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

    // Try to place bid before auction starts
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    next_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());
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
    // Place bid after auction end
    set_block_timestamp(params.auction_end_time + 1);
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());
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
    // Place bid after auction end date
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());
}


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
    // Make bid
    let bid_count: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_count * bid_count;
    let ob_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_before_bid: u256 = eth_dispatcher.balance_of(round_facade.contract_address());
    round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    let ob_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_after_bid: u256 = eth_dispatcher.balance_of(round_facade.contract_address());
    // Check bids went to the round
    assert(
        ob_balance_after_bid - bid_amount == ob_balance_before_bid, 'bid did not leave obs account'
    );
    assert(
        round_balance_before_bid + bid_amount == round_balance_after_bid, 'bid did not reach round'
    );
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid amount must be > 0', 'ENTRYPOINT_FAILED',))]
fn test_bid_zero_amount_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Try to bid 0 amount
    round_facade.place_bid(0, params.reserve_price, option_bidder_buyer_1());
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
    // Try to bid 0 price
    round_facade.place_bid(2, params.reserve_price - 1, option_bidder_buyer_1());
}

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
