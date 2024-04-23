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
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address, assert_event_transfer,

    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left
};




/// Withdraw Tests ///
// @dev Withdraw is used to collect from unallocated liquidity
// While current round is Auctioning, any next round position is unlocked
// While current round is Running, premiums/unsold options in current is unlocked, along with any in next round position
// While current round is Settled (in rtp), all current round (net collected amounts) liquidity is rolled over into next, and is unlocked

// Test that withdraw sends eth from round -> LP
#[test]
#[available_gas(10000000)]
fn test_withdraw_transfers_eth() {
    let( mut vault_facade,eth_dispatcher) = setup_facade();
    // Get the next option round
    let mut option_round_facade = vault_facade.get_next_round();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Withdraw liquidity
    let lp_balance_before: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_before: u256 = eth_dispatcher
        .balance_of(option_round_facade.contract_address());
    vault_facade.withdraw(1 * decimals(), liquidity_provider_1());
    let lp_balance_after: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_after: u256 = eth_dispatcher

        .balance_of(option_round_facade.contract_address());
    // Check liquidity changes
    assert(lp_balance_after == lp_balance_before + (1 * decimals()), 'lp transfer incorrect');
    assert(
        round_balance_after == round_balance_before - (1 * decimals()), 'round transfer incorrect'
    );
    assert_event_transfer(
        option_round_facade.contract_address(), liquidity_provider_1(), 1 * decimals()
    );
}

// Test that withdraw decrements the round's total unallocated liquidity
#[test]
#[available_gas(10000000)]
fn test_withdraw_decrements_rounds_total_unallocated() {
    let (mut vault_facade,_) = setup_facade();
    // Get the next option round
    let mut option_round_facade = vault_facade.get_next_round();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Withdraw liquidity
    vault_facade.withdraw(1 * decimals(), liquidity_provider_1());
    let round_liquidity = option_round_facade.total_unallocated_liquidity();
    // Check total liquidity updates correctly
    assert(round_liquidity == deposit_amount_wei - (1 * decimals()), 'unlocked liquidity wrong');
    // Withdraw liquidity again
    vault_facade.withdraw(9 * decimals(), liquidity_provider_1());
    let round_liquidity = option_round_facade.total_unallocated_liquidity();
    // Check total liquidity updates correctly
    assert(round_liquidity == deposit_amount_wei - (10 * decimals()), 'unlocked liquidity wrong');
}


// Test that withdraw updates LP's unallocated liquidity
#[test]
#[available_gas(10000000)]
fn test_withdraw_decrements_lps_unallocated_liquidity() {
    let (mut vault_facade, _) = setup_facade();

    // Get the next option round
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Withdraw liquidity
    vault_facade.withdraw(1 * decimals(), liquidity_provider_1());
    let locked_liquidity: u256 = vault_facade.get_locked_liquidity(liquidity_provider_1());
    let unlocked_liquidity: u256 = vault_facade.get_unlocked_liquidity(liquidity_provider_1());
    // Check un/locked liquidity updates correctly
    assert(unlocked_liquidity == deposit_amount_wei - (1 * decimals()), 'unlocked liquidity wrong');
    assert(locked_liquidity == 0, 'locked liquidity wrong');
}
// @Note add test like above where collateral is !=0 (while round is running collect premiums/unsold liq. and check unallocated goes down, and collateral remains the same)

// Test that withdrawing 0 liquidity does nothing 
#[test]
#[available_gas(10000000)]
fn test_deposit_withdraw_liquidity_zero() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    let mut option_round_facade: OptionRoundFacade = vault_facade.get_next_round();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Withdraw 0 liquidity
    let balance_before_transfer: u256 =eth_dispatcher
        .balance_of(liquidity_provider_1());
    vault_facade.withdraw(0, liquidity_provider_1());
    // Check no liquidity changes
    let balance_after_transfer: u256 = eth_dispatcher
        .balance_of(liquidity_provider_1());
    let round_liquidity = option_round_facade.total_unallocated_liquidity();
    let locked_liquidity: u256 = vault_facade.get_locked_liquidity(liquidity_provider_1());
    let unlocked_liquidity: u256 = vault_facade.get_unlocked_liquidity(liquidity_provider_1());
    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
    assert(round_liquidity == deposit_amount_wei, 'total liquidity shouldnt change');
    assert(locked_liquidity == 0, 'locked liq shouldnt change');
    assert(unlocked_liquidity == deposit_amount_wei, 'unlocked liq shouldnt change');
    assert_event_transfer(
        vault_facade.contract_address(), liquidity_provider_1(), deposit_amount_wei
    );
}
// @note add test that LP cannot withdraw more than unallocated balance
// @note add test that and unallocated liquidity collected is marked in the contract


