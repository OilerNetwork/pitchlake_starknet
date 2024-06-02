use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::{
    eth::Eth,
    tests::{
        utils::{
            utils::{get_erc20_balances, sum_u256_array, split_spreads},
            event_helpers::{
                pop_log, assert_no_events_left, assert_event_transfer, assert_event_vault_withdrawal
            },
            accelerators::{
                accelerate_to_auctioning, accelerate_to_auctioning_custom, accelerate_to_running,
                accelerate_to_settled,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                liquidity_providers_get,
            },
            variables::{decimals}, setup::{setup_facade},
            facades::{
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
                vault_facade::{VaultFacade, VaultFacadeTrait},
            }
        },
    },
};
use debug::PrintTrait;

// Test withdraw 0 fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot withdraw 0', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_0_fails() {
    let (mut vault, _) = setup_facade();
    let lp = liquidity_provider_1();
    accelerate_to_auctioning(ref vault);
    // Try to withdraw 0
    vault.withdraw(0, lp);
}

// Test withdrawing > unlocked balance fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot withdraw more than unallocated balance', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_more_than_unlocked_balance_failure() {
    let (mut vault, _) = setup_facade();
    let lp = liquidity_provider_1();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let unlocked_balance = vault.get_lp_unlocked_balance(lp);
    // Try to withdraw more than unlocked balance
    vault.withdraw(unlocked_balance + 1, lp);
}

// Test when LPs withdraw, eth transfers from Vault to LP
#[test]
#[available_gas(10000000)]
fn test_deposit_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let lps = liquidity_providers_get(2);
    let mut amounts = array![50 * decimals(), 50 * decimals()];
    vault.deposit_multiple(amounts.span(), lps.span());

    // Initital eth balances for vault and LPs
    let addresses = array![vault.contract_address(), *lps[0], *lps[1]].span();
    let mut init_eth_balances = get_erc20_balances(eth.contract_address, addresses);
    // Deposit into vault
    vault.withdraw_multiple(amounts.span(), lps.span());
    // Final eth balances for vault and LP
    let mut final_eth_balances = get_erc20_balances(eth.contract_address, addresses);

    // Check eth balances
    let total_withdrawals = sum_u256_array(amounts.span());
    // Vault
    assert(
        *final_eth_balances[0] == *init_eth_balances[0] - total_withdrawals,
        'Vault did not send eth'
    );
    // Lp1
    assert(*final_eth_balances[1] == *init_eth_balances[1] - *amounts[0], 'LP1 did not send eth');
    // Lp2
    assert(*final_eth_balances[2] == *init_eth_balances[2] - *amounts[1], 'LP2 did not send eth');
}

// Test when LPs withdraw, the correct events fire
#[test]
#[available_gas(10000000)]
fn test_withdraw_events() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3);
    let deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()];

    // Initial unlocked balances
    let spreads_init = vault.get_lp_balance_spreads(liquidity_providers.span());
    // Withdraw from the vault
    let spreads_final = vault.withdraw_multiple(deposit_amounts.span(), liquidity_providers.span());

    // Check event emission
    let (_, mut lp_unlocked_balances_init) = split_spreads(spreads_init.span());
    let (_, mut lp_unlocked_balances_final) = split_spreads(spreads_final.span());
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(lp) => {
                let unlocked_bal_before = lp_unlocked_balances_init.pop_front().unwrap();
                let unlocked_bal_after = lp_unlocked_balances_final.pop_front().unwrap();
                assert_event_vault_withdrawal(
                    vault.contract_address(), lp, unlocked_bal_before, unlocked_bal_after
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test when LPs withdraw, tokens come from the vault's unlocked pool
#[test]
#[available_gas(10000000)]
fn test_withdraw_come_from_unlocked_pool() {
    let (mut vault, _) = setup_facade();
    let mut lps = liquidity_providers_get(3);
    let mut deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()];
    accelerate_to_auctioning_custom(ref vault, lps.span(), deposit_amounts.span(),);

    // Get the initial spread of the vault and LPs
    let mut spreads_init = vault.get_lp_balance_spreads(lps.span());
    let (vault_locked_init, vault_unlocked_init) = vault.get_balance_spread();
    // Withdraw some amount in the vault
    let mut withdraw_amounts = array![1 * decimals(), 2 * decimals(), 4 * decimals()];
    let spreads_final = vault.deposit_multiple(withdraw_amounts.span(), lps.span());
    // Get the final spread of the vault and LPs
    let (vault_locked_final, vault_unlocked_final) = vault.get_balance_spread();
    let amounts_total = sum_u256_array(deposit_amounts.span());

    // Locked should not change, and unlocked should decrease by withdrawal amount
    assert(vault_locked_final == vault_locked_init, 'vault locked shd not change');
    assert(vault_unlocked_final == vault_unlocked_init + amounts_total, 'vault unlocked wrong');
    let (mut lp_locked_balances_init, mut lp_unlocked_balances_init) = split_spreads(
        spreads_init.span()
    );
    let (mut lp_locked_balances_final, mut lp_unlocked_balances_final) = split_spreads(
        spreads_final.span()
    );
    loop {
        match lps.pop_front() {
            Option::Some(_) => {
                let lp_locked_init = lp_locked_balances_init.pop_front().unwrap();
                let lp_locked_final = lp_locked_balances_final.pop_front().unwrap();
                assert(lp_locked_final == lp_locked_init, 'lp locked shd not change');

                let lp_unlocked_init = lp_unlocked_balances_init.pop_front().unwrap();
                let lp_unlocked_final = lp_unlocked_balances_final.pop_front().unwrap();
                let withdraw_amount = withdraw_amounts.pop_front().unwrap();
                assert(
                    lp_unlocked_final == lp_unlocked_init - withdraw_amount, 'lp unlocked wrong'
                );
            },
            Option::None => { break (); }
        }
    }
}


// Test withdrawal always come from the vault's unlocked pool, regardless of the state of the current round
#[test]
#[available_gas(10000000)]
fn test_withdrawals_always_come_from_unlocked() {
    let (mut vault, _) = setup_facade();
    // Lp1 supplys liquidity and the next auction starts
    accelerate_to_auctioning(ref vault);
    let deposit_amount = vault.get_locked_balance(); // lp1 deposited 100 eth in the accelerator

    // Vault and lp's initial spread after a topup (without a topup the unlocked balance would be 0)
    let lp = liquidity_provider_1();
    let top_up_amount = 200 * decimals();
    let (lp_locked0, lp_unlocked0) = vault
        .deposit(top_up_amount, lp); //(locked: dep, unlocked: topup)
    let (vault_locked0, vault_unlocked0) = vault.get_balance_spread();
    // Withdraw while current round is auctioning
    let (lp_locked1, lp_unlocked1) = vault.withdraw(top_up_amount, lp); //(dep, 0)
    let (vault_locked1, vault_unlocked1) = vault.get_balance_spread();
    // Withdraw while current round is running
    let (clearing_price, total_options_sold) = accelerate_to_running(ref vault);
    let total_premiums = clearing_price * total_options_sold;
    let (lp_locked2, lp_unlocked2) = vault.withdraw(total_premiums / 2, lp);
    let (vault_locked2, vault_unlocked2) = vault.get_balance_spread(); //(dep, prems/2)
    // Withdraw while the current round is settled (no payout upon settlement)
    let mut current_round = vault.get_current_round();
    let payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    let (lp_locked3, lp_unlocked3) = vault.withdraw(total_premiums / 2, lp); //(0, dep-payout)
    let (vault_locked3, vault_unlocked3) = vault.get_balance_spread();

    // Vault and LP locked balances should not change (until the round settles, then locked - payout moves to unlocked)
    assert(lp_locked0 == deposit_amount, 'lp locked wrong0');
    assert(lp_locked1 == deposit_amount, 'lp locked wrong1');
    assert(lp_locked2 == deposit_amount, 'lp locked wrong2');
    assert(lp_locked3 == 0, 'lp locked wrong');
    assert(vault_locked0 == deposit_amount, 'vault locked wrong0');
    assert(vault_locked1 == deposit_amount, 'vault locked wrong1');
    assert(vault_locked2 == deposit_amount, 'vault locked wrong2');
    assert(vault_locked3 == 0, 'vault locked wrong');
    // Vault and LP unlocked balances should decrement by the withdraw amounts (locked adds to unlocked when round settles)
    assert(lp_unlocked0 == top_up_amount, 'lp unlocked wrong0');
    assert(vault_unlocked0 == top_up_amount, 'vault unlocked wrong0');
    assert(lp_unlocked1 == 0, 'lp unlocked wrong1');
    assert(vault_unlocked1 == 0, 'vault unlocked wrong1');
    assert(lp_unlocked2 == total_premiums / 2, 'lp unlocked wrong2');
    assert(vault_unlocked2 == total_premiums / 2, 'vault unlocked wrong2');
    // @dev The only liquidity that is unlocked is what was previously locked - payout (all premiums were withdrawn)
    assert(lp_unlocked3 == deposit_amount - payout, 'lp unlocked wrong3');
    assert(vault_unlocked3 == deposit_amount - payout, 'vault unlocked wrong3');
}

