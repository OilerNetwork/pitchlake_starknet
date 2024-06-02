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

// Test when LP deposits, tokens are stored in the vault's unlocked pool
#[test]
#[available_gas(10000000)]
fn test_deposit_vault_unlocked_liquidity() {
    let (mut vault_facade, _) = setup_facade();

    // Get a liquidity provider
    let liquidity_providers = liquidity_providers_get(1);
    let deposit_amount = 100 * decimals();
    // Get the initial liquidity of the vault and the LP
    let (lp_locked_init, lp_unlocked_init) = vault_facade
        .get_lp_balance_spread(*liquidity_providers[0]);
    let (vault_locked_init, vault_unlocked_init) = vault_facade.get_balance_spread();

    // Deposit
    let (lp_locked_final, lp_unlocked_final) = vault_facade
        .deposit(deposit_amount, *liquidity_providers[0]);
    let (vault_locked_final, vault_unlocked_final) = vault_facade.get_balance_spread();

    // Locked should not change, and unlocked should increase by deposit amount
    assert(vault_locked_final == vault_locked_init, 'vault locked shd not change');
    assert(vault_unlocked_final == vault_unlocked_init + deposit_amount, 'vault unlocked wrong');

    assert(lp_locked_final == lp_locked_init, 'lp locked shd not change');
    assert(lp_unlocked_final == lp_unlocked_init + deposit_amount, 'lp unlocked wrong');
}

// Test above with multiple LPs
#[test]
#[available_gas(10000000)]
fn test_multi_deposit_vault_unlocked_liquidity() {
    let (mut vault_facade, _) = setup_facade();

    // Get multiple liquidity providers
    let mut liquidity_providers = liquidity_providers_get(3);
    let mut deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()];
    let amounts_total = sum_u256_array(deposit_amounts.span());
    // Get the initial liquidity of the vault and the LPs
    let mut spreads_init = vault_facade.get_lp_balance_spreads(liquidity_providers.span());
    let (vault_locked_init, vault_unlocked_init) = vault_facade.get_balance_spread();

    // Deposit some amount in the vault
    let spreads_final = vault_facade
        .deposit_multiple(liquidity_providers.span(), deposit_amounts.span());

    // Locked should not change, and unlocked should increase by deposit amount
    let (vault_locked_final, vault_unlocked_final) = vault_facade.get_balance_spread();
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

// Test when LP deposits, eth transfers from LP to vault
#[test]
#[available_gas(10000000)]
fn test_deposit_eth_transfer() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Initital eth balances for vault and LP
    let lp = liquidity_provider_1();
    let deposit_amount = 50 * decimals();
    let addresses = array![vault_facade.contract_address(), lp].span();
    let mut init_eth_balances = get_erc20_balances(eth_dispatcher.contract_address, addresses);
    // Deposit into vault
    vault_facade.deposit(deposit_amount, lp);
    // Final eth balances for vault and LP
    let mut final_eth_balances = get_erc20_balances(eth_dispatcher.contract_address, addresses);

    // Check eth transfer
    assert(
        final_eth_balances.pop_front().unwrap() == init_eth_balances.pop_front().unwrap()
            + deposit_amount,
        'Vault did not receive eth'
    );
    assert(
        final_eth_balances.pop_front().unwrap() == init_eth_balances.pop_front().unwrap()
            - deposit_amount,
        'LP did not send eth'
    );
}

// Test when LPs deposit, the correct events fire
#[test]
#[available_gas(10000000)]
fn test_multi_deposit_to_vault_event() {
    let (mut vault_facade, _) = setup_facade();
    let mut _next_round = vault_facade.get_next_round();

    // LPs
    let mut liquidity_providers = liquidity_providers_get(3);
    // Initial unlocked balances
    let spreads_init = vault_facade.get_lp_balance_spreads(liquidity_providers.span());
    // Deposit into the vault
    let deposit_amounts = array![25 * decimals(), 50 * decimals(), 100 * decimals()];
    let spreads_final = vault_facade
        .deposit_multiple(liquidity_providers.span(), deposit_amounts.span());

    // Check event emission
    let (_, mut lp_unlocked_balances_init) = split_spreads(spreads_init.span());
    let (_, mut lp_unlocked_balances_final) = split_spreads(spreads_final.span());
    loop {
        match liquidity_providers.pop_front() {
            Option::Some(lp) => {
                assert_event_vault_deposit(
                    vault_facade.contract_address(),
                    lp,
                    lp_unlocked_balances_init.pop_front().unwrap(),
                    lp_unlocked_balances_final.pop_front().unwrap(),
                );
            },
            Option::None => { break (); }
        }
    }
}

// Test that LP cannot deposit zero
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot deposit 0', 'ENTRYPOINT_FAILED'))]
fn test_deposit_zero_liquidity_failure() {
    let (mut vault_facade, _) = setup_facade();
    vault_facade.deposit(0, liquidity_provider_1());
}

// Test deposits always go to the vault's unlocked pool
#[test]
#[available_gas(10000000)]
fn test_deposit_is_always_into_unlocked() {
    let (mut vault_facade, _) = setup_facade();
    let deposit_amount = 100 * decimals();

    accelerate_to_auctioning(ref vault_facade);
    let (lp_locked0, lp_unlocked0) = vault_facade.get_lp_balance_spread(liquidity_provider_2());

    // Deposit while current is auctioning
    // @dev Using LP2 to allows us to ignore premiums earned from the auction (since they did not supply liquidity in the initial round)
    let (lp_locked1, lp_unlocked1) = vault_facade.deposit(deposit_amount, liquidity_provider_2());

    // Deposit while current is running
    accelerate_to_running(ref vault_facade);
    let (lp_locked2, lp_unlocked2) = vault_facade.deposit(deposit_amount, liquidity_provider_2());

    // Deposit while current is settled
    accelerate_to_settled(ref vault_facade, 0);
    let (lp_locked3, lp_unlocked3) = vault_facade.deposit(deposit_amount, liquidity_provider_2());

    assert(lp_locked1 == lp_locked0, 'locked shd not change1');
    assert(lp_locked2 == lp_locked1, 'locked shd not change2');
    assert(lp_locked3 == lp_locked2, 'locked shd not change3');
    assert(lp_unlocked1 == lp_unlocked0 + deposit_amount, 'unlocked wrong1');
    assert(lp_unlocked2 == lp_unlocked1 + deposit_amount, 'unlocked wrong2');
    assert(lp_unlocked3 == lp_unlocked2 + deposit_amount, 'unlocked wrong3');
}

