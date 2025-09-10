use core::array::SpanTrait;
use core::option::OptionTrait;
use debug::PrintTrait;
use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;
use pitch_lake::library::eth::Eth;
use pitch_lake::option_round::interface::{
    IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState,
};
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled, clear_event_logs,
};
use pitch_lake::tests::utils::helpers::event_helpers::{
    assert_event_auction_bid_placed, assert_event_auction_end, assert_event_auction_start,
    assert_event_option_round_deployed, assert_event_option_settle, assert_event_options_exercised,
    assert_event_transfer, assert_event_unused_bids_refunded, assert_event_vault_deposit,
    assert_event_vault_withdrawal, assert_no_events_left, pop_log,
};
use pitch_lake::tests::utils::helpers::general_helpers::{
    get_erc20_balance, get_erc20_balances, sum_u256_array,
};
use pitch_lake::tests::utils::helpers::setup::setup_facade;
use pitch_lake::tests::utils::lib::test_accounts::{
    liquidity_provider_1, liquidity_provider_2, liquidity_providers_get, option_bidder_buyer_1,
    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
};
use pitch_lake::tests::utils::lib::variables::decimals;
use pitch_lake::vault::contract::Vault;
use starknet::testing::{set_block_timestamp, set_contract_address};
use starknet::{
    ClassHash, ContractAddress, Felt252TryIntoContractAddress, contract_address_const,
    deploy_syscall, get_block_timestamp, get_contract_address,
};


/// Event Tests

// Test depositing to the vault emits the correct events
#[test]
#[available_gas(50000000)]
fn test_deposit_events() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3).span();
    let mut deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()].span();

    // Unlocked balances before deposit
    let mut vault_unlocked_balance_before = vault.get_total_unlocked_balance();

    // Deposit into the vault
    let mut unlocked_balances_after = vault.deposit_multiple(deposit_amounts, liquidity_providers);

    // Check event emission
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(liquidity_provider) => {
                let deposit_amount = *deposit_amounts.pop_front().unwrap();
                let unlocked_balance_after = unlocked_balances_after.pop_front().unwrap();
                vault_unlocked_balance_before += deposit_amount;
                assert_event_vault_deposit(
                    vault.contract_address(),
                    *liquidity_provider,
                    deposit_amount,
                    unlocked_balance_after,
                    vault_unlocked_balance_before,
                );
            },
            Option::None => { break (); },
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
                    lp_balance_after == lp_balance_before - deposit_amount, 'lp eth balance wrong',
                );
            },
            Option::None => { break (); },
        }
    }
}

#[test]
#[available_gas(50000000)]
#[should_panic(
    expected: ('ERC20: insufficient allowance', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'),
)]
fn test_depositing_to_vault_no_approval() {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_provider = contract_address_const::<'fresh user'>();
    let mut deposit_amount = 50 * decimals();

    set_contract_address(liquidity_provider);
    eth.approve(vault.contract_address(), 0);

    vault.deposit(deposit_amount, liquidity_provider);
}

// Test deposits always go to the vault's unlocked pool, regardless of the state of the current
// round
#[test]
#[available_gas(90000000)]
fn test_deposits_always_go_to_unlocked_pool() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    let deposit_amount = 100 * decimals();
    let liquidity_provider = liquidity_provider_1();

    // Deposit while current is auctioning
    accelerate_to_auctioning(ref vault);
    let unlocked_balance_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_balance_after = vault.deposit(deposit_amount, liquidity_provider);
    assert(
        unlocked_balance_after == unlocked_balance_before + deposit_amount,
        'unlocked balance wrong',
    );

    // Deposit while current is running
    accelerate_to_running(ref vault);
    let unlocked_balance_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_balance_after = vault.deposit(deposit_amount, liquidity_provider);
    assert(
        unlocked_balance_after == unlocked_balance_before + deposit_amount,
        'unlocked balance wrong',
    );

    // Deposit while current is settled
    accelerate_to_settled(ref vault, current_round.get_strike_price());
    let unlocked_balance_before = vault.get_lp_unlocked_balance(liquidity_provider);
    let unlocked_balance_after = vault.deposit(deposit_amount, liquidity_provider);
    assert(
        unlocked_balance_after == unlocked_balance_before + deposit_amount,
        'unlocked balance wrong',
    );
}

