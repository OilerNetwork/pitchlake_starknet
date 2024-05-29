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
            setup_facade, decimals, deploy_vault, timestamp_start_month, timestamp_end_month,
            zero_address, vault_manager, weth_owner, mock_option_params,
        },
        utils_new::{
            event_helpers::{pop_log, assert_no_events_left, assert_event_transfer},
            accelerators::{accelerate_to_running},
            test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4
            },
        },
        option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
        vault_facade::{VaultFacade, VaultFacadeTrait},
    },
};
use debug::PrintTrait;

// @note Add event tests once we agree on if we are using 1 or 2 withdraw functions.
// Either one withdraw that takes from current premiums/unsold then from next round unallocated,
// or one for current premiums/unsold and one for next round unallocated (withdraw vs withdraw & collect) ?

// Test withdraw 0 fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot withdraw 0', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_0_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Deposit liquidity (in the next round, unallocated)
    vault_facade.deposit(100 * decimals(), liquidity_provider_1());
    // Withdraw from deposits
    vault_facade.withdraw(0, liquidity_provider_1());
}

#[test]
#[available_gas(10000000)]
fn test_withdraw_is_always_from_unlocked() {
    let (mut vault, eth_dispatcher) = setup_facade();

    // Deposit liquidity while current round is settled
    let deposit_amount = 50 * decimals();
    vault.deposit(deposit_amount, liquidity_provider_1());
    // Deposit liquidity while current round is auctioning

    vault.start_auction();

    vault.deposit(deposit_amount + 1, liquidity_provider_1());

    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let (init_locked, init_unlocked) = vault.get_lp_balance_spread(liquidity_provider_1());
    vault.withdraw(deposit_amount, liquidity_provider_1());

    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let (final_locked, final_unlocked) = vault.get_lp_balance_spread(liquidity_provider_1());

    assert(init_locked == final_locked, 'Locked position mismatch');
    assert(init_lp_balance == final_lp_balance - deposit_amount, 'LP balance mistmatch');
    assert(init_unlocked == final_unlocked + deposit_amount, 'Vault balance mistmatch');
    // Deposit liquidity while current round is running
    accelerate_to_running(ref vault);
    vault.deposit(deposit_amount + 2, liquidity_provider_1());

    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let (init_locked, init_unlocked) = vault.get_lp_balance_spread(liquidity_provider_1());
    vault.withdraw(deposit_amount + 1, liquidity_provider_1());

    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let (final_locked, final_unlocked) = vault.get_lp_balance_spread(liquidity_provider_1());

    assert(init_locked == final_locked, 'Locked position mismatch');
    assert(init_lp_balance == final_lp_balance - deposit_amount, 'LP balance mistmatch');
    assert(init_unlocked == final_unlocked + deposit_amount, 'Vault balance mistmatch');

    vault.end_auction();
    vault.deposit(deposit_amount + 2, liquidity_provider_1());

    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let (init_locked, init_unlocked) = vault.get_lp_balance_spread(liquidity_provider_1());
    vault.withdraw(deposit_amount + 1, liquidity_provider_1());

    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let (final_locked, final_unlocked) = vault.get_lp_balance_spread(liquidity_provider_1());

    assert(init_locked == final_locked, 'Locked position mismatch');
    assert(init_lp_balance == final_lp_balance - deposit_amount, 'LP balance mistmatch');
    assert(init_unlocked == final_unlocked + deposit_amount, 'Vault balance mistmatch');
// @note Check eth transfer without event
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot withdraw more than unallocated balance', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_more_than_unlocked_balance_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Accelerate to round 1 running
    vault_facade.start_auction();
    // Current round (running), next round (open)
    // Make deposit into next round
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Amount of premiums earned from the auction (plus unsold liq) for LP
    // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // LP unallocated is premiums earned + next round deposits
    let lp_unlocked = vault_facade.get_lp_unlocked_balance(liquidity_provider_1());
    // Withdraw from rewards
    let collect_amount = lp_unlocked + 1;
    vault_facade.withdraw(collect_amount, liquidity_provider_1());
}
