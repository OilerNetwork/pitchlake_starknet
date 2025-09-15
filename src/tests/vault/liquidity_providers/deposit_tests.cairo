use core::array::SpanTrait;
use core::option::OptionTrait;
use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;
use pitch_lake::tests::utils::facades::option_round_facade::OptionRoundFacadeTrait;
use pitch_lake::tests::utils::facades::vault_facade::VaultFacadeTrait;
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
};
use pitch_lake::tests::utils::helpers::event_helpers::assert_event_vault_deposit;
use pitch_lake::tests::utils::helpers::general_helpers::{get_erc20_balances, sum_u256_array};
use pitch_lake::tests::utils::helpers::setup::setup_facade;
use pitch_lake::tests::utils::lib::test_accounts::{liquidity_provider_1, liquidity_providers_get};
use pitch_lake::tests::utils::lib::variables::decimals;
use starknet::testing::set_contract_address;


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
    for i in 0..liquidity_providers.len() {
        let lp = *liquidity_providers[i];
        let deposit = *deposit_amounts[i];
        let unlocked_after = *unlocked_balances_after[i];
        vault_unlocked_balance_before += deposit;

        assert_event_vault_deposit(
            vault.contract_address(), lp, deposit, unlocked_after, vault_unlocked_balance_before,
        );
    }
    //    loop {
//        match liquidity_providers.pop_front() {
//            Option::Some(liquidity_provider) => {
//                let deposit_amount = *deposit_amounts.pop_front().unwrap();
//                let unlocked_balance_after = unlocked_balances_after.pop_front().unwrap();
//                vault_unlocked_balance_before += deposit_amount;
//                assert_event_vault_deposit(
//                    vault.contract_address(),
//                    *liquidity_provider,
//                    deposit_amount,
//                    unlocked_balance_after,
//                    vault_unlocked_balance_before,
//                );
//            },
//            Option::None => { break (); },
//        }
//    }
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
    for i in 0..liquidity_providers.len() {
        let lp_balance_before = *lp_balances_before[i];
        let lp_balance_after = *lp_balances_after[i];
        let deposit_amount = *deposit_amounts[i];
        assert(lp_balance_after == lp_balance_before - deposit_amount, 'lp eth balance wrong');
    }
    //    loop {
//        match liquidity_providers.pop_front() {
//            Option::Some(_) => {
//                let lp_balance_before = lp_balances_before.pop_front().unwrap();
//                let lp_balance_after = lp_balances_after.pop_front().unwrap();
//                let deposit_amount = *deposit_amounts.pop_front().unwrap();
//                // Check eth transfers from liquidity provider
//                assert(
//                    lp_balance_after == lp_balance_before - deposit_amount, 'lp eth balance
//                    wrong',
//                );
//            },
//            Option::None => { break (); },
//        }
//    }
}

#[test]
#[available_gas(50000000)]
#[should_panic(
    expected: ('ERC20: insufficient allowance', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'),
)]
fn test_depositing_to_vault_no_approval() {
    let (mut vault, eth) = setup_facade();
    let mut liquidity_provider = 'fresh user'.try_into().unwrap();
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

