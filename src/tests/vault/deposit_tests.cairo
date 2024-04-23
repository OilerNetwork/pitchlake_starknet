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

// Test deposit liquidity transfers eth from LP -> round
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_transfers_eth() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Get the next option round
    let mut option_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    // Initial balances
    let initial_lp_balance: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let initial_round_balance: u256 = eth_dispatcher
        .balance_of(option_round_facade.contract_address());
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Final balances
    let final_lp_balance: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let final_round_balance: u256 = eth_dispatcher
        .balance_of(option_round_facade.contract_address());
    // Assertions
    assert(
        final_lp_balance == initial_lp_balance - deposit_amount_wei, 'LP balance should decrease'
    );
    assert(
        final_round_balance == initial_round_balance + deposit_amount_wei,
        'Round balance should increase'
    );
    assert_event_transfer(
        liquidity_provider_1(), option_round_facade.contract_address(), deposit_amount_wei
    );
}

// Test deposit liquidity increments total unallocated liquidity in the round
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_increments_rounds_total_unallocated() {
    let (mut vault_facade, _) = setup_facade();
    // Get the next option round
    let mut option_round_facade: OptionRoundFacade = vault_facade.get_next_round();

    // Initial total liquidity
    let init_total_deposits: u256 = option_round_facade.total_liquidity();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    let topup_amount_wei: u256 = 100 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Topup liquidity
    let next_total_deposits: u256 = option_round_facade.total_unallocated_liquidity();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    let final_total_deposits: u256 = option_round_facade.total_unallocated_liquidity();
    // Check round total deposits incremented each time
    assert(init_total_deposits == 0, 'should with at 0');
    assert(next_total_deposits == init_total_deposits + deposit_amount_wei, 'should increment');
    assert(final_total_deposits == next_total_deposits + topup_amount_wei, 'should increment');
    assert_event_transfer(
        liquidity_provider_1(), option_round_facade.contract_address(), topup_amount_wei
    );
}

// Test deposit liquidity updates LP's unallocated balance in the vault
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_increments_LPs_unallocated_balance() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    let topup_amount_wei: u256 = 100 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    let lp_unallocated_1 = vault_facade.get_unlocked_liquidity(liquidity_provider_1());
    // Topup liquidity
    vault_facade.deposit(topup_amount_wei, liquidity_provider_1());
    let lp_unallocated_2 = vault_facade.get_unlocked_liquidity(liquidity_provider_1());
    // Check LP's unallocated incremented each time
    assert(lp_unallocated_1 == deposit_amount_wei, 'wrong unallocated 1');
    assert(lp_unallocated_2 == deposit_amount_wei + topup_amount_wei, 'wrong unallocated 2');
    assert_event_transfer(
        liquidity_provider_1(), vault_facade.contract_address(), topup_amount_wei
    );
}

// Test deposit 0 liquidity does nothing
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_zero() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    let mut option_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let deposit_amount_wei: u256 = 0;
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let locked_liquidity: u256 = vault_facade.get_locked_liquidity(liquidity_provider_1());
    let unlocked_liquidity: u256 = vault_facade.get_unlocked_liquidity(liquidity_provider_1());

    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
    assert(option_round_facade.total_unallocated_liquidity() == 0, 'total liquidity should be 0');
    assert(locked_liquidity + unlocked_liquidity == 0, 'un/locked liquidity should be 0');
}

// test LP can deposit into next always 
#[test]
#[available_gas(10000000)]
fn test_can_deposit_always() {
    let (mut vault_facade, _) = setup_facade();

    //Open state
    test_deposit_liquidity_transfers_eth();

    //Auctioning state
    vault_facade.start_auction();
    test_deposit_liquidity_transfers_eth();

    //Running state
    vault_facade.end_auction();
    test_deposit_liquidity_transfers_eth();

    //Settled state
    vault_facade.settle_option_round(liquidity_provider_1());
    test_deposit_liquidity_transfers_eth();
}
