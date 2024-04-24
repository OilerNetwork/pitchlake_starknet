use pitch_lake_starknet::tests::vault_facade::VaultFacadeTrait;
use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
};
use pitch_lake_starknet::option_round::{
    OptionRoundParams, OptionRoundState, OptionRound, IOptionRoundDispatcher,
    IOptionRoundDispatcherTrait
};
use pitch_lake_starknet::market_aggregator::{
    IMarketAggregator, IMarketAggregatorDispatcher, IMarketAggregatorDispatcherTrait,
    IMarketAggregatorSafeDispatcher, IMarketAggregatorSafeDispatcherTrait
};
use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall, SyscallResult,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;
use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, setup_return_mkt_agg, setup_return_mkt_agg_facade, decimals,
    option_round_test_owner, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner, mock_option_params,
    assert_event_auction_start, assert_event_auction_settle, assert_event_option_settle
};

use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};


/// These tests deal with the lifecycle of an option round, from deployment to settlement ///

/// @dev left off here - matt

/// Auction End Tests /// 

// @note move to vault/auction_end_tests

// @note move to vault/auction_end_tests

/// Round Settle Tests ///

// @note move to vault/option_settle_tests
// Test that the round settles 

// @note move to vault/option_settle_tests
// Test that an option round cannot be settled twice
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('option has already settled', 'ENTRYPOINT_FAILED',))]
fn test_option_round_settle_twice_failure() {
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
    vault_facade.end_auction();
    // Settle option round
    set_block_timestamp(option_round_params.option_expiry_time + 1);
    vault_facade.settle_option_round(liquidity_provider_1());
    // Try to settle the option round again
    vault_facade.settle_option_round(liquidity_provider_1());
}


// @note move to option_round/exercising_options_tests
// Test that OB cannot exercise options pre option settlement
// Move to auction/bidding tests
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot exercise before round settles ', 'ENTRYPOINT_FAILED',))]
fn test_exercise_options_too_early_failure() {
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
    vault_facade.end_auction();
    // Should fail as option has not settled
    current_round_facade.exercise_options(option_bidder_buyer_1());
}
// Tests
// @note test collect premiums & unlocked liq before roll over, should fail if Settled 
// @note test LP can deposit into next always 
// @note test LP can withdraw from next (storage position) when current < Settled (only updates storage position if they already have one in the next round)
// @note test LP can withdraw from next (dynamic) when current == Settled (calculate position value at end of current and update next position/checkpoint)
// @note test that liquidity moves from current -> next when current settles 
// @note test premiums & unlocked liq roll over 
// @note test roll over if LP collects first
// @note test that LP can withdraw from next position ONLY during round transition period
// @note test place bid when current.state == Auctioning. Running & Settled should both should fail
// @note test refund bid when current.state >= Running. Auctioning should fail since bid is locked
// @note test that LP can tokenize current position when current.state >= Running. Auctioning should fail since no premiums yet 
// @note test positionizing rlp tokens while into next round (at any current round state and during round transition period)


