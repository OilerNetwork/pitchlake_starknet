use core::option::OptionTrait;
use core::array::SpanTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
use pitch_lake_starknet::{
    types::{OptionRoundState}, vault::contract::Vault,
    option_round::{interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait,}},
    library::eth::Eth,
    tests::{
        utils::{
            helpers::{
                general_helpers::{sum_u256_array, get_erc20_balance, get_erc20_balances,},
                event_helpers::{
                    assert_event_transfer, pop_log, assert_no_events_left,
                    assert_event_option_settle, assert_event_option_round_deployed,
                    assert_event_vault_deposit, assert_event_auction_start,
                    assert_event_auction_bid_accepted, assert_event_auction_end,
                    assert_event_vault_withdrawal, assert_event_unused_bids_refunded,
                    assert_event_options_exercised,
                },
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                    clear_event_logs,
                },
                setup::{setup_facade},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                    liquidity_providers_get
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};
use debug::PrintTrait;


/// Event Tests

// Test depositing to the vault emits the correct events
#[test]
#[available_gas(50000000)]
fn test_deposit_events() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3).span();
    let deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()].span();

    // Unlocked balances before deposit
    let mut unlocked_balances_before = vault.get_lp_unlocked_balances(liquidity_providers);

    // Deposit into the vault
    let mut unlocked_balances_after = vault.deposit_multiple(deposit_amounts, liquidity_providers);

    // Check event emission
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(liquidity_provider) => {
                let unlocked_balance_before = unlocked_balances_before.pop_front().unwrap();
                let unlocked_balance_after = unlocked_balances_after.pop_front().unwrap();
                assert_event_vault_deposit(
                    vault.contract_address(),
                    *liquidity_provider,
                    unlocked_balance_before,
                    unlocked_balance_after
                );
            },
            Option::None => { break (); }
        }
    }
}


/// State Tests ///

// Test depositing transfers eth from liquidity provider to vault
// Also contains a test for 0 deposit
#[test]
#[available_gas(50000000)]
fn test_depositing_to_vault_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3).span();
    let mut deposit_amounts = array![50 * decimals(), 50 * decimals(), 0].span();
    let total_deposits = sum_u256_array(deposit_amounts);

    // Liquidity provider and vault eth balances before deposit
    let mut lp_balances_before = get_erc20_balances(eth.contract_address, liquidity_providers);
    let vault_balance_before = eth.balance_of(vault.contract_address());

    // Deposit
    vault.deposit_multiple(deposit_amounts, liquidity_providers);

    // Liquidity provider and vault eth balances after deposit
    let mut lp_balances_after = get_erc20_balances(eth.contract_address, liquidity_providers);
    let vault_balance_after = eth.balance_of(vault.contract_address());

    // Check vault eth balance
    assert(vault_balance_after == vault_balance_before + total_deposits, 'vault eth balance wrong');

    // Check liquidity providers eth balances
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(_) => {
                let lp_balance_before = lp_balances_before.pop_front().unwrap();
                let lp_balance_after = lp_balances_after.pop_front().unwrap();
                let deposit_amount = *deposit_amounts.pop_front().unwrap();
                // Check eth transfers from liquidity provider
                assert(
                    lp_balance_after == lp_balance_before - deposit_amount, 'lp eth balance wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test deposits always go to the vault's unlocked pool, regardless of the state of the current round
#[test]
#[available_gas(50000000)]
fn test_deposits_always_go_to_unlocked_pool() {
    let (mut vault, _) = setup_facade();
    let deposit_amount = 100 * decimals();
    let liquidity_provider = liquidity_provider_1();

    // Deposit while current is auctioning
    accelerate_to_auctioning(ref vault);
    let unlocked_balance_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_balance_after = vault.deposit(deposit_amount, liquidity_provider);
    assert(
        unlocked_balance_after == unlocked_balance_before + deposit_amount, 'unlocked balance wrong'
    );

    // Deposit while current is running
    accelerate_to_running(ref vault);
    let unlocked_balance_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_balance_after = vault.deposit(deposit_amount, liquidity_provider);
    assert(
        unlocked_balance_after == unlocked_balance_before + deposit_amount, 'unlocked balance wrong'
    );

    // Deposit while current is settled
    accelerate_to_settled(ref vault, 0);
    let unlocked_balance_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_balance_after = vault.deposit(deposit_amount, liquidity_provider);
    assert(
        unlocked_balance_after == unlocked_balance_before + deposit_amount, 'unlocked balance wrong'
    );
}

