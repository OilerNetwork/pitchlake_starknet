use core::option::OptionTrait;
use core::array::SpanTrait;
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    types::Errors, library::eth::Eth, vault::{contract::Vault},
    tests::{
        utils::{
            helpers::{
                general_helpers::{get_erc20_balances, sum_u256_array},
                event_helpers::{
                    pop_log, assert_no_events_left, assert_event_transfer,
                    assert_event_vault_withdrawal, clear_event_logs,
                },
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_auctioning_custom,
                    accelerate_to_running, accelerate_to_settled, timeskip_and_start_auction,
                },
                setup::{setup_facade},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get,
                },
                variables::{decimals},
            },
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
            }
        },
    },
};
use debug::PrintTrait;


/// Failures ///

// @note instead of testing withdrawing 0 fails or returns 0, we should just include in
// in the the withdraw amounts in each test
// @note can use the same array of withdraw amounts/lps for each test (0, ...)

// Test withdraw 0 does not fail, but balances are unchanged.
//@note confirm if gas changes will also affect the balance, should we only check for vault balance or
//calculate gas amount to correct the balance.
// Test withdrawing > unlocked balance fails
#[test]
#[available_gas(50000000)]
fn test_withdrawing_more_than_unlocked_balance_fails() {
    let (mut vault, _) = setup_facade();
    let liquidity_provider = liquidity_provider_1();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);

    // Try to withdraw more than unlocked balance
    let unlocked_balance = vault.get_lp_unlocked_balance(liquidity_provider);
    vault
        .withdraw_expect_error(
            unlocked_balance + 1, liquidity_provider, Errors::InsufficientBalance
        );
}


/// Event Tests ///

// Test withdrawing from the vault emits the correct event
#[test]
#[available_gas(50000000)]
fn test_withdrawal_events() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3).span();
    let mut deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()].span();

    // Unlocked balance before withdrawals
    vault.deposit_multiple(deposit_amounts, liquidity_providers);

    // Clear deposit events from log
    clear_event_logs(array![vault.contract_address()]);

    // Withdraw from the vault
    let mut vault_unlocked_balance_before = vault.get_total_unlocked_balance();
    let mut lp_unlocked_balances_after = vault
        .withdraw_multiple(deposit_amounts, liquidity_providers);

    // Check event emissions
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(liquidity_provider) => {
                let withdraw_amount = *deposit_amounts.pop_front().unwrap();
                let unlocked_amount_after = lp_unlocked_balances_after.pop_front().unwrap();
                vault_unlocked_balance_before -= withdraw_amount;
                assert_event_vault_withdrawal(
                    vault.contract_address(),
                    *liquidity_provider,
                    withdraw_amount,
                    unlocked_amount_after, // account unlocked balance before the withdraw
                    vault_unlocked_balance_before, // vault unlocked balance after the withdraw
                );
            },
            Option::None => { break (); }
        }
    }
}

/// State Tests ///

// Test withdrawing transfers eth from vault to liquidity provider
// Also tests for 0 withdraw behaviour
#[test]
#[available_gas(50000000)]
fn test_withdrawing_from_vault_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3).span();
    let mut deposit_amounts = array![50 * decimals(), 50 * decimals(), 0].span();
    vault.deposit_multiple(deposit_amounts, liquidity_providers);

    // Liquidity provider and vault eth balances before withdrawal
    let mut lp_balances_before = get_erc20_balances(eth.contract_address, liquidity_providers);
    let vault_balance_before = eth.balance_of(vault.contract_address());

    // Withdraw from vault
    vault.withdraw_multiple(deposit_amounts, liquidity_providers);
    let total_withdrawals = sum_u256_array(deposit_amounts);

    // Liquidity provider and vault eth balances after withdrawal
    let mut lp_balances_after = get_erc20_balances(eth.contract_address, liquidity_providers);
    let vault_balance_after = eth.balance_of(vault.contract_address());

    // Check vault eth balance
    assert_eq!(vault_balance_after, vault_balance_before - total_withdrawals);

    // Check liquidity provider eth balances
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(_) => {
                let lp_balance_before = lp_balances_before.pop_front().unwrap();
                let lp_balance_after = lp_balances_after.pop_front().unwrap();
                let withdraw_amount = *deposit_amounts.pop_front().unwrap();

                // Check eth transfers to liquidity provider
                assert(
                    lp_balance_after == lp_balance_before + withdraw_amount, 'lp eth balance wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test withdrawal always come from the vault's unlocked pool, regardless of the state of the current round
#[test]
#[available_gas(90000000)]
fn test_withdrawing_always_come_from_unlocked_pool() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let deposit_amount = 100 * decimals();
    let withdraw_amount = 1 * decimals();
    let liquidity_provider = liquidity_provider_1();

    // Withdraw while current round is auctioning
    accelerate_to_auctioning(ref vault);
    let unlocked_amount_before = vault.deposit(deposit_amount, liquidity_provider);
    let unlocked_amount_after = vault.withdraw(withdraw_amount, liquidity_provider);

    assert(
        unlocked_amount_after == unlocked_amount_before - withdraw_amount, 'unlocked amount 1 wrong'
    );

    // Withdraw while current round is running
    accelerate_to_running(ref vault);
    let unlocked_amount_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_amount_after = vault.withdraw(withdraw_amount, liquidity_provider);
    assert(
        unlocked_amount_after == unlocked_amount_before - withdraw_amount, 'unlocked amount 2 wrong'
    );

    // Withdraw while the current round is settled
    accelerate_to_settled(ref vault, current_round.get_strike_price());
    let unlocked_amount_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_amount_after = vault.withdraw(withdraw_amount, liquidity_provider);
    assert(
        unlocked_amount_after == unlocked_amount_before - withdraw_amount, 'unlocked amount 3 wrong'
    );
}
