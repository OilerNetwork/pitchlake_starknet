use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultTransfer, OptionRoundCreated
};
use pitch_lake_starknet::option_round::{
    OptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundParams
};

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
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left
};
///helpers

// Assert `amount` tokens transfer from `from` to `to`
fn assert_event_transfer(from: ContractAddress, to: ContractAddress, amount: u256) {
    let event = pop_log::<VaultTransfer>(zero_address()).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.amount == amount, 'Invalid `amount`');
    assert_no_events_left(zero_address());
}

// Test deposit liquidity transfers eth from LP -> round
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_transfers_eth() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Get the next option round
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id() + 1)
    };
    // Initial balances
    let initial_lp_balance: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let initial_round_balance: u256 = eth_dispatcher.balance_of(option_round.contract_address);
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Final balances
    let final_lp_balance: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let final_round_balance: u256 = eth_dispatcher.balance_of(option_round.contract_address);
    // Assertions
    assert(
        final_lp_balance == initial_lp_balance - deposit_amount_wei, 'LP balance should decrease'
    );
    assert(
        final_round_balance == initial_round_balance + deposit_amount_wei,
        'Round balance should increase'
    );
    assert_event_transfer(
        liquidity_provider_1(), option_round.contract_address, deposit_amount_wei
    );
}

// Test deposit liquidity increments total unallocated liquidity in the round
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_increments_rounds_total_unallocated() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Get the next option round
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id() + 1)
    };

    // Initial total liquidity
    let init_total_deposits: u256 = option_round.total_liquidity();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    let topup_amount_wei: u256 = 100 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Topup liquidity
    let next_total_deposits: u256 = option_round.total_unallocated_liquidity();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let final_total_deposits: u256 = option_round.total_unallocated_liquidity();
    // Check round total deposits incremented each time
    assert(init_total_deposits == 0, 'should with at 0');
    assert(next_total_deposits == init_total_deposits + deposit_amount_wei, 'should increment');
    assert(final_total_deposits == next_total_deposits + topup_amount_wei, 'should increment');
    assert_event_transfer(
        liquidity_provider_1(), vault_dispatcher.contract_address, topup_amount_wei
    );
}

// Test deposit liquidity updates LP's unallocated balance in the vault
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_increments_LPs_unallocated_balance() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Deposit liquidity
    let deposit_amount_wei: u256 = 50 * decimals();
    let topup_amount_wei: u256 = 100 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let lp_unallocated_1 = vault_dispatcher.get_unallocated_balance_for(liquidity_provider_1());
    // Topup liquidity
    vault_dispatcher.deposit_liquidity(topup_amount_wei);
    let lp_unallocated_2 = vault_dispatcher.get_unallocated_balance_for(liquidity_provider_1());
    // Check LP's unallocated incremented each time
    assert(lp_unallocated_1 == deposit_amount_wei, 'wrong unallocated 1');
    assert(lp_unallocated_2 == deposit_amount_wei + topup_amount_wei, 'wrong unallocated 2');
    assert_event_transfer(
        liquidity_provider_1(), vault_dispatcher.contract_address, topup_amount_wei
    );
}

// Test deposit 0 liquidity does nothing
#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_zero() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id() + 1)
    };
    set_contract_address(liquidity_provider_1());
    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let deposit_amount_wei: u256 = 0;
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let locked_liquidity: u256 = vault_dispatcher
        .get_collateral_balance_for(liquidity_provider_1());
    let unlocked_liquidity: u256 = vault_dispatcher
        .get_unallocated_balance_for(liquidity_provider_1());
    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
    assert(option_round.total_unallocated_liquidity() == 0, 'total liquidity should be 0');
    assert(locked_liquidity + unlocked_liquidity == 0, 'un/locked liquidity should be 0');
}


/// Withdraw Tests ///
// @dev Withdraw is used to collect from unallocated liquidity
// While current round is Auctioning, any next round position is unlocked
// While current round is Running, premiums/unsold options in current is unlocked, along with any in next round position
// While current round is Settled (in rtp), all current round (net collected amounts) liquidity is rolled over into next, and is unlocked

// Test that withdraw sends eth from round -> LP
#[test]
#[available_gas(10000000)]
fn test_withdraw_transfers_eth() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Get the next option round
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id() + 1)
    };
    // Deposit liquidity
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Withdraw liquidity
    let lp_balance_before: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_before: u256 = eth_dispatcher.balance_of(option_round.contract_address);
    vault_dispatcher.withdraw_from_position(1 * decimals());
    let lp_balance_after: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_after: u256 = eth_dispatcher.balance_of(option_round.contract_address);
    // Check liquidity changes
    assert(lp_balance_after == lp_balance_before + (1 * decimals()), 'lp transfer incorrect');
    assert(
        round_balance_after == round_balance_before - (1 * decimals()), 'round transfer incorrect'
    );
    assert_event_transfer(option_round.contract_address, liquidity_provider_1(), 1 * decimals());
}

// Test that withdraw decrements the round's total unallocated liquidity
#[test]
#[available_gas(10000000)]
fn test_withdraw_decrements_rounds_total_unallocated() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Get the next option round
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id() + 1)
    };
    // Deposit liquidity
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Withdraw liquidity
    vault_dispatcher.withdraw_from_position(1 * decimals());
    let round_liquidity = option_round.total_unallocated_liquidity();
    // Check total liquidity updates correctly
    assert(round_liquidity == deposit_amount_wei - (1 * decimals()), 'unlocked liquidity wrong');
    // Withdraw liquidity again
    vault_dispatcher.withdraw_from_position(9 * decimals());
    let round_liquidity = option_round.total_unallocated_liquidity();
    // Check total liquidity updates correctly
    assert(round_liquidity == deposit_amount_wei - (10 * decimals()), 'unlocked liquidity wrong');
}


// Test that withdraw updates LP's unallocated liquidity
#[test]
#[available_gas(10000000)]
fn test_withdraw_decrements_lps_unallocated_liquidity() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Get the next option round
    // Deposit liquidity
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Withdraw liquidity
    vault_dispatcher.withdraw_from_position(1 * decimals());
    let locked_liquidity: u256 = vault_dispatcher
        .get_collateral_balance_for(liquidity_provider_1());
    let unlocked_liquidity: u256 = vault_dispatcher
        .get_unallocated_balance_for(liquidity_provider_1());
    // Check un/locked liquidity updates correctly
    assert(unlocked_liquidity == deposit_amount_wei - (1 * decimals()), 'unlocked liquidity wrong');
    assert(locked_liquidity == 0, 'locked liquidity wrong');
}
// @Note add test like above where collateral is !=0 (while round is running collect premiums/unsold liq. and check unallocated goes down, and collateral remains the same)

// Test that withdrawing 0 liquidity does nothing 
#[test]
#[available_gas(10000000)]
fn test_deposit_withdraw_liquidity_zero() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let option_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id() + 1)
    };
    // Deposit liquidity
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Withdraw 0 liquidity
    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    vault_dispatcher.withdraw_from_position(0);
    // Check no liquidity changes
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_liquidity = option_round.total_unallocated_liquidity();
    let locked_liquidity: u256 = vault_dispatcher
        .get_collateral_balance_for(liquidity_provider_1());
    let unlocked_liquidity: u256 = vault_dispatcher
        .get_unallocated_balance_for(liquidity_provider_1());
    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
    assert(round_liquidity == deposit_amount_wei, 'total liquidity shouldnt change');
    assert(locked_liquidity == 0, 'locked liq shouldnt change');
    assert(unlocked_liquidity == deposit_amount_wei, 'unlocked liq shouldnt change');
    assert_event_transfer(
        vault_dispatcher.contract_address, liquidity_provider_1(), deposit_amount_wei
    );
}
// @note add test that LP cannot withdraw more than unallocated balance
// @note add test that and unallocated liquidity collected is marked in the contract


