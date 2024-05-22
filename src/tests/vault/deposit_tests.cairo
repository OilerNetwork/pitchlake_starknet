use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{Vault};

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

use pitch_lake_starknet::option_round::{
    IOptionRoundDispatcher, IOptionRoundDispatcherTrait, OptionRoundParams, OptionRoundState
};
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    assert_event_transfer, timestamp_start_month, timestamp_end_month, liquidity_provider_1,
    liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
    option_bidder_buyer_4, zero_address, vault_manager, weth_owner, option_round_contract_address,
    mock_option_params, pop_log, assert_no_events_left, create_array_gradient,
    liquidity_providers_get, clear_event_logs, assert_event_auction_start, assert_event_auction_bid,
    assert_event_auction_end, assert_event_option_settle, assert_event_option_round_deployed,
    assert_event_vault_deposit, assert_event_option_deposit_liquidity,
    assert_event_option_withdraw_premium, assert_event_option_withdraw_payout,
    assert_event_option_withdraw_liquidity, assert_event_option_withdraw_unused_bids,
    assert_event_vault_withdrawal,
};
use pitch_lake_starknet::tests::vault::utils::{accelerate_to_auctioning, accelerate_to_running};

// Test eth transfer when LP deposits
#[test]
#[available_gas(10000000)]
fn test_deposit_eth_transfer() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Current round (settled) and next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    // Initital eth balances for lp, current round, next round
    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let init_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let init_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Deposit into next round
    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Final eth balances for lp, current round, next round
    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let final_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let final_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Check liquidity changes
    assert(final_lp_balance == init_lp_balance - deposit_amount, 'lp shd send eth');
    assert(final_current_round_balance == init_current_round_balance, 'current eth shd be locked');
    assert(
        final_next_round_balance == init_next_round_balance + deposit_amount, 'next shd receive eth'
    );
    assert_event_transfer(
        eth_dispatcher.contract_address,
        liquidity_provider_1(),
        next_round.contract_address(),
        deposit_amount
    );
}

// Test deposit event emission
#[test]
#[available_gas(10000000)]
fn test_deposit_events() {
    let (mut vault_facade, _) = setup_facade();
    let mut next_round = vault_facade.get_next_round();
    // Deposit into next round
    let deposit_amount = 50 * decimals();
    // Initial balances
    let (lp1_init_collateral, lp1_init_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (lp2_init_collateral, lp2_init_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_2());
    let lp1_total_before = lp1_init_collateral + lp1_init_unallocated;
    let lp2_total_before = lp2_init_collateral + lp2_init_unallocated;

    // Make deposits
    // @note replace with accelerators, or no because of event log?
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    vault_facade.deposit(2 * deposit_amount, liquidity_provider_2());

    // Check vault events emit correctly
    assert_event_vault_deposit(
        vault_facade.contract_address(),
        liquidity_provider_1(),
        lp1_total_before,
        lp1_total_before + deposit_amount,
    );
    assert_event_vault_deposit(
        vault_facade.contract_address(),
        liquidity_provider_2(),
        lp2_total_before,
        lp2_total_before + deposit_amount,
    );
    // Check option round events emit correctly
    assert_event_option_deposit_liquidity(
        next_round.contract_address(), liquidity_provider_1(), deposit_amount
    );
    assert_event_option_deposit_liquidity(
        next_round.contract_address(), liquidity_provider_2(), 2 * deposit_amount
    );
}

// Test collateral/unallocated amounts when LP deposits
// @note add assertion that vault::round_positions[lp, next_id] increments (need to add vault entry point for get_lp_deposit_in_round)
#[test]
#[available_gas(10000000)]
fn test_deposit_collateral_and_unallocated_round() {
    let (mut vault_facade, _) = setup_facade();
    // Current round (settled), next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    // Initial collateral/unallocated
    let (init_current_round_collateral, init_current_round_unallocated) = current_round
        .get_all_round_liquidity();
    let (init_next_round_collateral, init_next_round_unallocated) = next_round
        .get_all_round_liquidity();
    // Deposit liquidity (into next round)
    let lps = liquidity_providers_get(5);
    let amounts = create_array_gradient(50 * decimals(), 10 * decimals(), 5);

    let deposit_total = vault_facade.deposit_mutltiple(lps.span(), amounts.span());
    // Final collateral/unallocated
    let (final_current_round_collateral, final_current_round_unallocated) = current_round
        .get_all_round_liquidity();
    let (final_next_round_collateral, final_next_round_unallocated) = next_round
        .get_all_round_liquidity();
    // Check collateral is untouched
    assert(
        final_current_round_collateral == init_current_round_collateral,
        'current round collateral wrong'
    );
    assert(
        final_next_round_collateral == init_next_round_collateral, 'next round collateral wrong'
    );
    // Check unallocated is updated
    assert(
        final_current_round_unallocated == init_current_round_unallocated,
        'current round unallocated wrong'
    );
    assert(
        final_next_round_unallocated == init_next_round_unallocated + deposit_total,
        'next round unallocated wrong'
    );
}


// Test that LP cannot deposit zero
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Cannot deposit 0', 'ENTRYPOINT_FAILED'))]
fn test_deposit_zero_liquidity_failure() {
    let (mut vault_facade, _) = setup_facade();
    vault_facade.deposit(0, liquidity_provider_1());
}

// Move to different file
// Test to make sure the event testers are working as expected
#[test]
#[available_gas(100000000)]
fn test_event_testers() {
    let (mut v, e) = setup_facade();
    set_contract_address(liquidity_provider_1());
    /// new test, make emission come from entry point on vault,
    let mut r = v.get_current_round();
    e.transfer(liquidity_provider_1(), 100);
    assert_event_transfer(e.contract_address, liquidity_provider_1(), liquidity_provider_1(), 100);
    r.option_round_dispatcher.rm_me(100);
    assert_event_auction_start(r.contract_address(), 100);
    assert_event_auction_bid(r.contract_address(), r.contract_address(), 100, 100, true);
    assert_event_auction_bid(r.contract_address(), r.contract_address(), 100, 100, false);
    assert_event_auction_end(r.contract_address(), 100);
    assert_event_option_settle(r.contract_address(), 100);
    assert_event_option_round_deployed(v.contract_address(), 1, v.contract_address());

    assert_event_vault_deposit(v.contract_address(), v.contract_address(), 100, 100);
    assert_event_vault_withdrawal(v.contract_address(), v.contract_address(), 100, 100);
    assert_event_option_deposit_liquidity(r.contract_address(), r.contract_address(), 100);
    assert_event_option_withdraw_premium(r.contract_address(), r.contract_address(), 100);
    assert_event_option_withdraw_payout(r.contract_address(), r.contract_address(), 100);
    assert_event_option_withdraw_liquidity(r.contract_address(), r.contract_address(), 100);
    assert_event_option_withdraw_unused_bids(r.contract_address(), r.contract_address(), 100);
}


// Test that deposits always go into the next round
#[test]
#[available_gas(10000000)]
fn test_deposit_is_always_into_next_round() {
    let (mut vault, eth) = setup_facade();
    let mut next_round = vault.get_next_round();

    // Deposit liquidity while current round is settled
    let deposit_amount = 50 * decimals();
    vault.deposit(deposit_amount, liquidity_provider_1());
    assert_event_transfer(
        eth.contract_address, liquidity_provider_1(), next_round.contract_address(), deposit_amount
    );
    // Deposit liquidity while current round is auctioning
    vault.start_auction();
    let mut current_round = vault.get_current_round();
    next_round = vault.get_next_round();
    vault.deposit(deposit_amount + 1, liquidity_provider_1());
    assert_event_transfer(
        eth.contract_address,
        liquidity_provider_1(),
        next_round.contract_address(),
        deposit_amount + 1
    );
    // Deposit liquidity while current round is running
    let params = current_round.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    current_round.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    set_block_timestamp(params.auction_end_time + 1);
    vault.end_auction();
    vault.deposit(deposit_amount + 2, liquidity_provider_1());
    assert_event_transfer(
        eth.contract_address,
        liquidity_provider_1(),
        next_round.contract_address(),
        deposit_amount + 2
    );
}


#[test]
#[available_gas(10000000)]
fn test_deposit_is_always_into_unallocated() {
    let (mut vault_facade, _) = setup_facade();
    // Initial collateral/unallocated
    let (init_collateral, init_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());

    let deposit_amount = 50 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    let (final_collateral, final_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    assert(init_collateral == final_collateral, 'Collteral Mismatch');
    assert(init_unallocated + deposit_amount == final_unallocated, 'Unallocated amount Mismatch');
}

