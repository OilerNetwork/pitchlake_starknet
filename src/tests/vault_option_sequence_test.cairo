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
    setup, setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
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


/// helpers
fn assert_event_option_created(
    prev_round: ContractAddress,
    new_round: ContractAddress,
    collaterized_amount: u256,
    option_round_params: OptionRoundParams
) {
    let event = pop_log::<OptionRoundCreated>(zero_address()).unwrap();
    assert(event.prev_round == prev_round, 'Invalid prev_round');
    assert(event.new_round == new_round, 'Invalid new_round');
    assert(event.collaterized_amount == collaterized_amount, 'Invalid collaterized_amount');
    assert(event.option_round_params == option_round_params, 'Invalid option_round_params');
    assert_no_events_left(zero_address());
}

// Test OB cannot bid before the auction starts 
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot bid before auction starts', 'ENTRYPOINT_FAILED'))]
fn test_bid_before_auction_starts_failure() {
    let mut vault_facade: VaultFacade = setup_facade();
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

// Test OB cannot bid after the auction end date (regardless if end_auction() is called)
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Auction ended, cannot place bid', 'ENTRYPOINT_FAILED',))]
fn test_bid_after_auction_ends_failure() {
    // Add liq. to next round
    // note: Why is this option buyer and not liquidity provider?
    //set_contract_address(option_bidder_buyer_1());
    let mut vault_facade: VaultFacade = setup_facade();
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, option_bidder_buyer_1());

    // Start the option round
    vault_facade.start_auction();

    // Get current round params
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round.get_params();

    // Place bid after auction end
    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(params.auction_end_time + 1);
    let option_amount = params.total_options_available;
    let option_price = params.reserve_price;
    let bid_amount = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());
}

// Test auction cannot end if it has not started
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot end auction before it starts', 'ENTRYPOINT_FAILED'))]
fn test_auction_end_before_it_starts_failure() {
    let mut vault_facade: VaultFacade = setup_facade();
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
    let mut vault_facade: VaultFacade = setup_facade();
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

// Test options cannot settle before expiry date
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Options cannot settle before expiry',))]
fn test_options_settle_before_expiry_date_failure() {
    let mut vault_facade:VaultFacade = setup_facade();
    // Add liq. to next round
    let deposit_amount_wei = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Start the option round
    vault_facade.start_auction();

    // OptionRoundDispatcher
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    let params = current_round.get_params();

    // Place bid
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price, option_bidder_buyer_1());

    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();

    // Settle option round before expiry
    set_block_timestamp(params.option_expiry_time - 1);
    vault_facade.settle_option_round(option_bidder_buyer_1());
}
