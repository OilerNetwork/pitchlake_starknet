use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{VaultTransfer};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    assert_event_transfer, timestamp_start_month, timestamp_end_month, liquidity_provider_1,
    liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
    option_bidder_buyer_4, zero_address, vault_manager, weth_owner, option_round_contract_address,
    mock_option_params, pop_log, assert_no_events_left
};
use pitch_lake_starknet::tests::vault::utils::{accelerate_to_running};

// Test withdraw > lp unallocated fails

// Test withdraw 0 fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot withdraw 0', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_0_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity (in the next round, unallocated)
    vault_facade.deposit(100 * decimals(), liquidity_provider_1());
    // Withdraw from deposits
    vault_facade.withdraw(0, liquidity_provider_1());
}

#[test]
#[available_gas(10000000)]
fn test_withdraw_is_always_from_next_round() {
    let (mut vault, _) = setup_facade();
    let mut next_round = vault.get_next_round();

    // Deposit liquidity while current round is settled
    let deposit_amount = 50 * decimals();
    vault.deposit(deposit_amount, liquidity_provider_1());
    // Deposit liquidity while current round is auctioning
    vault.start_auction();
    let mut current_round = vault.get_current_round();
    next_round = vault.get_next_round();
    vault.deposit(deposit_amount + 1, liquidity_provider_1());
    vault.withdraw(deposit_amount, liquidity_provider_1());
    assert_event_transfer(next_round.contract_address(), liquidity_provider_1(), deposit_amount);
    // Deposit liquidity while current round is running
    let mut next_round = vault.get_next_round();
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    set_block_timestamp(params.auction_end_time + 1);
    vault.deposit(deposit_amount + 2, liquidity_provider_1());
    vault.withdraw(deposit_amount + 1, liquidity_provider_1());
    vault.end_auction();
    vault.deposit(deposit_amount + 2, liquidity_provider_1());
    vault.withdraw(deposit_amount + 1, liquidity_provider_1());
    assert_event_transfer(next_round.contract_address(), liquidity_provider_1(), deposit_amount);
}

#[test]
#[available_gas(10000000)]
fn test_withdraw_updates_unallocated_balance() {
    let (mut vault, _) = setup_facade();
    let mut next_round = vault.get_next_round();

    // Deposit liquidity while current round is settled
    let deposit_amount = 50 * decimals();
    vault.deposit(deposit_amount, liquidity_provider_1());
    // Deposit liquidity while current round is auctioning
    vault.start_auction();
    let mut current_round = vault.get_current_round();
    next_round = vault.get_next_round();
    vault.deposit(deposit_amount + 1, liquidity_provider_1());
    vault.get_unallocated_balance_for(liquidity_provider_1());
    vault.withdraw(deposit_amount, liquidity_provider_1());
    assert_event_transfer(next_round.contract_address(), liquidity_provider_1(), deposit_amount);
    // Deposit liquidity while current round is running
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    set_block_timestamp(params.auction_end_time + 1);
    vault.end_auction();
    vault.deposit(deposit_amount + 2, liquidity_provider_1());
    vault.withdraw(deposit_amount + 1, liquidity_provider_1());
}
