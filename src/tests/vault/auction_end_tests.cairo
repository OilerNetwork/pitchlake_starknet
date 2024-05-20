use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
};
use pitch_lake_starknet::option_round::{OptionRoundParams, OptionRoundState};

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
    pop_log, assert_no_events_left, month_duration, assert_event_auction_end,
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::tests::mocks::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};


// Test auction cannot end if it has not started
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot end auction before it starts', 'ENTRYPOINT_FAILED'))]
fn test_auction_end_before_start_failure() {
    let (mut vault_facade, _) = setup_facade();
    // OptionRoundDispatcher
    let mut next_round: OptionRoundFacade = vault_facade.get_next_round();
    let params = next_round.get_params();

    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Try to end auction before it starts
    set_block_timestamp(params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
}

// Test auction cannot end before the auction end date
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Auction cannot settle before due time',))]
fn test_auction_end_before_end_date_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Add liq. to current round
    // note Why some deposits are by option_bidder
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, option_bidder_buyer_1());

    // Start the auction
    vault_facade.start_auction();

    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round.get_params();

    // Try to end auction before the end time
    set_block_timestamp(params.auction_end_time - 1);
    current_round.end_auction();
}

// Test that the auction clearing price is set post auction end, and state updates to Running
#[test]
#[available_gas(10000000)]
fn test_vault_end_auction_success() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
    assert(clearing_price == bid_price, 'should be reserve_price');
    // Check that state is Running now, and auction clearing price is set
    let state: OptionRoundState = current_round_facade.get_state();
    let expectedState: OptionRoundState = OptionRoundState::Running;
    assert(expectedState == state, 'round should be Running');
    // Check auction clearing price event
    assert_event_auction_end(
        current_round_facade.contract_address(), current_round_facade.get_auction_clearing_price()
    );
}

// Test that the auction end event emits correctly
#[test]
#[available_gas(10000000)]
fn test_vault_end_auction_event() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let option_round_params: OptionRoundParams = current_round_facade.get_params();
    set_block_timestamp(option_round_params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();

    // Assert event emitted correctly
    assert_event_auction_end(
      current_round_facade.contract_address(), clearing_price
    );
}

// Test that the auction cannot be ended twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('The auction has already been settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_end_auction_twice_failure() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    set_contract_address(vault_manager());
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_facade.end_auction();
    // Try to settle auction a second time
    vault_facade.end_auction();
}
// @note Add tests that unallocated/collatera (lp and round) update at auction end
//    - test unallocate in current round goes from 0 -> premiums + unsold liq.


