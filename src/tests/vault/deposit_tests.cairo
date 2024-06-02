use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
use pitch_lake_starknet::{
    eth::Eth, vault::{Vault},
    option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundState},
    tests::{
        utils::{
            utils::{sum_u256_array, get_erc20_balance, get_erc20_balances, split_spreads,},
            event_helpers::{
                assert_event_transfer, pop_log, assert_no_events_left, assert_event_option_settle,
                assert_event_option_round_deployed, assert_event_vault_deposit,
                assert_event_auction_start, assert_event_auction_bid_accepted,
                assert_event_auction_bid_rejected, assert_event_auction_end,
                assert_event_vault_withdrawal, assert_event_unused_bids_refunded,
                assert_event_options_exercised,
            },
            accelerators::{
                accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
                clear_event_logs,
            },
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
                liquidity_providers_get
            },
            variables::{decimals}, setup::{setup_facade},
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};
use debug::PrintTrait;

// Test that LP cannot deposit zero
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot deposit 0', 'ENTRYPOINT_FAILED'))]
fn test_deposit_0_fails() {
    let (mut vault, _) = setup_facade();
    vault.deposit(0, liquidity_provider_1());
}


// Test when LPs deposit, eth transfers from LP to vault
#[test]
#[available_gas(10000000)]
fn test_deposit_eth_transfer() {
    let (mut vault, eth) = setup_facade();
    let lps = liquidity_providers_get(2);
    let mut amounts = array![50 * decimals(), 50 * decimals()];

    // Initital eth balances for vault and LP
    let addresses = array![vault.contract_address(), *lps[0], *lps[1]].span();
    let mut init_eth_balances = get_erc20_balances(eth.contract_address, addresses);
    // Deposit into vault
    vault.deposit_multiple(amounts.span(), lps.span());
    // Final eth balances for vault and LP
    let mut final_eth_balances = get_erc20_balances(eth.contract_address, addresses);

    // Check eth balances
    let total_deposits = sum_u256_array(amounts.span());
    // Vault
    assert(
        *final_eth_balances[0] == *init_eth_balances[0] + total_deposits,
        'Vault did not receive eth'
    );
    // Lp1
    assert(*final_eth_balances[1] == *init_eth_balances[1] - *amounts[0], 'LP1 did not send eth');
    // Lp2
    assert(*final_eth_balances[2] == *init_eth_balances[2] - *amounts[1], 'LP2 did not send eth');
}

// Test when LPs deposit, the correct events fire
#[test]
#[available_gas(10000000)]
fn test_deposit_events() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3);
    let deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()];

    // Initial unlocked balances
    let spreads_init = vault.get_lp_balance_spreads(liquidity_providers.span());
    // Deposit into the vault
    let spreads_final = vault.deposit_multiple(deposit_amounts.span(), liquidity_providers.span());

    // Check event emission
    let (_, mut lp_unlocked_balances_init) = split_spreads(spreads_init.span());
    let (_, mut lp_unlocked_balances_final) = split_spreads(spreads_final.span());
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(lp) => {
                let unlocked_bal_before = lp_unlocked_balances_init.pop_front().unwrap();
                let unlocked_bal_after = lp_unlocked_balances_final.pop_front().unwrap();
                assert_event_vault_deposit(
                    vault.contract_address(), lp, unlocked_bal_before, unlocked_bal_after
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test when LPs deposit, tokens are stored in the vault's unlocked pool
#[test]
#[available_gas(10000000)]
fn test_deposits_go_to_unlocked_pool() {
    let (mut vault, _) = setup_facade();
    let mut liquidity_providers = liquidity_providers_get(3);
    let mut deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()];

    // Get the initial spread of the vault and LPs
    let mut spreads_init = vault.get_lp_balance_spreads(liquidity_providers.span());
    let (vault_locked_init, vault_unlocked_init) = vault.get_balance_spread();
    // Deposit some amount in the vault
    let spreads_final = vault.deposit_multiple(deposit_amounts.span(), liquidity_providers.span());
    // Get the final spread of the vault and LPs
    let (vault_locked_final, vault_unlocked_final) = vault.get_balance_spread();
    let amounts_total = sum_u256_array(deposit_amounts.span());

    // Locked should not change, and unlocked should increase by deposit amount
    assert(vault_locked_final == vault_locked_init, 'vault locked shd not change');
    assert(vault_unlocked_final == vault_unlocked_init + amounts_total, 'vault unlocked wrong');

    let (mut lp_locked_balances_init, mut lp_unlocked_balances_init) = split_spreads(
        spreads_init.span()
    );
    let (mut lp_locked_balances_final, mut lp_unlocked_balances_final) = split_spreads(
        spreads_final.span()
    );
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(_) => {
                let lp_locked_init = lp_locked_balances_init.pop_front().unwrap();
                let lp_locked_final = lp_locked_balances_final.pop_front().unwrap();
                assert(lp_locked_final == lp_locked_init, 'lp locked shd not change');

                let lp_unlocked_init = lp_unlocked_balances_init.pop_front().unwrap();
                let lp_unlocked_final = lp_unlocked_balances_final.pop_front().unwrap();
                let deposit_amount = deposit_amounts.pop_front().unwrap();
                assert(lp_unlocked_final == lp_unlocked_init + deposit_amount, 'lp unlocked wrong');
            },
            Option::None => { break (); }
        }
    }
}

// Test deposits always go to the vault's unlocked pool, regardless of the state of the current round
#[test]
#[available_gas(10000000)]
fn test_deposits_always_go_to_unlocked_pool() {
    let (mut vault, _) = setup_facade();
    accelerate_to_auctioning(ref vault);

    // Vault and lp's initial spread
    let lp2 = liquidity_provider_1();
    let (lp_locked0, lp_unlocked0) = vault.get_lp_balance_spread(lp2); //(dep, 0)
    let (vault_locked0, vault_unlocked0) = vault.get_balance_spread();
    // Deposit while current is auctioning
    let deposit_amount = 100 * decimals();
    let (lp_locked1, lp_unlocked1) = vault.deposit(deposit_amount, lp2); //(dep, dep)
    let (vault_locked1, vault_unlocked1) = vault.get_balance_spread();
    // Deposit while current is running
    let (clearing_price, options_sold) = accelerate_to_running(ref vault);
    let premiums = clearing_price * options_sold;
    let (lp_locked2, lp_unlocked2) = vault
        .deposit(deposit_amount + 1, lp2); //(dep, 2 * dep + 1 + all_prem)
    let (vault_locked2, vault_unlocked2) = vault.get_balance_spread();
    // Deposit while current is settled
    let mut current_round = vault.get_current_round();
    let payout = accelerate_to_settled(ref vault, 2 * current_round.get_strike_price());
    let (lp_locked3, lp_unlocked3) = vault
        .deposit(
            deposit_amount + 2, liquidity_provider_2()
        ); //(0, 3 * dep + 3 + prem + dep - payout)
    let (vault_locked3, vault_unlocked3) = vault.get_balance_spread();

    // Locked balances should not change (until round settles, then locked - payout move to unlocked)
    assert(lp_locked0 == deposit_amount, 'lp locked wrong0');
    assert(lp_locked1 == deposit_amount, 'lp locked shd not change1');
    assert(lp_locked2 == deposit_amount, 'lp locked shd not change2');
    assert(lp_locked3 == 0, 'lp locked wrong3');
    assert(vault_locked0 == deposit_amount, 'vault locked wrong0');
    assert(vault_locked1 == deposit_amount, 'vault locked shd not change1');
    assert(vault_locked2 == deposit_amount, 'vault locked shd not change2');
    assert(vault_locked3 == 0, 'vault locked wrong3');
    // Unlocked balances should increment by the deposit amounts (and then by the locked amount upon settlement)
    assert(lp_unlocked0 == 0, 'lp unlocked wrong0');
    assert(vault_unlocked0 == 0, 'vault unlocked wrong0');
    assert(lp_unlocked1 == deposit_amount, 'lp unlocked wrong1');
    assert(vault_unlocked1 == deposit_amount, 'lp unlocked wrong1');
    assert(lp_unlocked2 == lp_unlocked1 + deposit_amount + 1 + premiums, 'lp unlocked wrong2');
    assert(
        vault_unlocked2 == vault_unlocked1 + deposit_amount + 1 + premiums, 'lp unlocked wrong2'
    );
    let original_unlocked_amount = lp_unlocked2 + deposit_amount + 2;
    let rolled_over_amount_from_locked = deposit_amount - payout;
    let expected = original_unlocked_amount + rolled_over_amount_from_locked;
    assert(lp_unlocked3 == expected, 'lp unlocked wrong3');
    assert(vault_unlocked3 == expected, 'vault unlocked wrong3');
}

