use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{VaultTransfer};

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
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    assert_event_transfer, timestamp_start_month, timestamp_end_month, liquidity_provider_1,
    liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3,
    option_bidder_buyer_4, zero_address, vault_manager, weth_owner, option_round_contract_address,
    mock_option_params, pop_log, assert_no_events_left
};


fn accelerate_to_running(ref self: VaultFacade) {
    // Deposit liquidity so round 1's auction can start
    self.deposit(100 * decimals(), liquidity_provider_1());
    // Start round 1's auction
    self.start_auction();
    // Bid for all options at reserve price
    let mut round_1 = self.get_current_round();
    let params = round_1.get_params();
    let bid_amount = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_amount * bid_price;
    round_1.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    round_1.end_auction();
}


// @note Rewards are unallocated liquidity in the current round (premiums earned + any unsold liqudity)

// Test eth transfer when LP withdraws from their rewards
#[test]
#[available_gas(10000000)]
fn test_withdraw_from_rewards_eth_transfer() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Accelerate to current round running
    accelerate_to_running(ref vault_facade);
    // Current round (running) and next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    // Amount of premiums earned from the current round's auction
    // This is LP's unallocated balance in the current round 
    let params = current_round.get_params();
    let premiums_earned = params.total_options_available
        * params.reserve_price; // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // Initital eth balances for lp, current round, next round
    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let init_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let init_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Withdraw from rewards
    let withdraw_amount = premiums_earned - 1;
    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
    // Final eth balances for lp, current round, next round
    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let final_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let final_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Check liquidity changes
    assert(final_lp_balance == init_lp_balance + withdraw_amount, 'lp shd receive eth');
    assert(
        final_current_round_balance == init_current_round_balance - withdraw_amount,
        'current shd send eth'
    );
    assert(final_next_round_balance == init_next_round_balance, 'next shd not be touched');
    assert_event_transfer(next_round.contract_address(), liquidity_provider_1(), withdraw_amount);
}

// Test eth transfer when LP withdraws from their rewards and next round deposit 
#[test]
#[available_gas(10000000)]
fn test_withdraw_from_rewards_and_deposits_eth_transfer() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Accelerate to current round running
    accelerate_to_running(ref vault_facade);
    // Add liquidity to next round (unallocated)
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Current round (running) and next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    // Amount of premiums earned from the current round's auction
    // This is LP's unallocated balance in the current round 
    let params = current_round.get_params();
    let premiums_earned = params.total_options_available
        * params.reserve_price; // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // Initital eth balances for lp, current round, next round
    let init_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let init_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let init_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Withdraw from rewards
    let withdraw_amount = premiums_earned + 1;
    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
    // Final eth balances for lp, current round, next round
    let final_lp_balance = eth_dispatcher.balance_of(liquidity_provider_1());
    let final_current_round_balance = eth_dispatcher.balance_of(current_round.contract_address());
    let final_next_round_balance = eth_dispatcher.balance_of(next_round.contract_address());
    // Check liquidity changes
    assert(final_lp_balance == init_lp_balance + withdraw_amount, 'lp shd receive eth');
    assert(
        final_current_round_balance == init_current_round_balance - premiums_earned,
        'current shd send all eth'
    );
    assert(final_next_round_balance == init_next_round_balance - 1, 'next shd send eth');
    // @dev Check pop order is correct 
    assert_event_transfer(next_round.contract_address(), liquidity_provider_1(), 1);
    assert_event_transfer(
        current_round.contract_address(), liquidity_provider_1(), premiums_earned
    );
}

// Test collateral/unallocated amounts when LP withdraws from their rewards
// @note Add assertion tha vault::collected_amount_for(lp) updates also 
#[test]
#[available_gas(10000000)]
fn test_withdraw_from_rewards_updates_collateral_and_unallocated() {
    let (mut vault_facade, _) = setup_facade();
    // Accelerate to round 1 running
    accelerate_to_running(ref vault_facade);
    // Current round (running), next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    let current_params = current_round.get_params();
    // Amount of premiums earned from the auction (plus unsold liq) for LP 
    let premiums_earned = current_params.total_options_available
        * current_params
            .reserve_price; // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // Initial collateral/unallocated
    let (init_lp_collateral, init_lp_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (init_current_round_collateral, init_current_round_unallocated) = current_round
        .get_all_round_liquidity();
    let (init_next_round_collateral, init_next_round_unallocated) = next_round
        .get_all_round_liquidity();
    // Withdraw from rewards
    let withdraw_amount = premiums_earned - 1;
    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
    // Final collateral/unallocated
    let (final_lp_collateral, final_lp_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (final_current_round_collateral, final_current_round_unallocated) = current_round
        .get_all_round_liquidity();
    let (final_next_round_collateral, final_next_round_unallocated) = next_round
        .get_all_round_liquidity();
    // Check collateral is untouched
    assert(final_lp_collateral == init_lp_collateral, 'lp collateral wrong');
    assert(
        final_current_round_collateral == init_current_round_collateral,
        'current round collateral wrong'
    );
    assert(
        final_next_round_collateral == init_next_round_collateral, 'next round collateral wrong'
    );
    // Check unallocated is updated
    assert(final_lp_unallocated == init_lp_unallocated - withdraw_amount, 'lp unallocated wrong');
    assert(
        final_current_round_unallocated == init_current_round_unallocated - withdraw_amount,
        'current round unallocated wrong'
    );
    assert(
        final_next_round_unallocated == init_next_round_unallocated, 'next round unallocated wrong'
    );
}

// Test collateral/unallocated amounts when LP withdraws from their rewards and next round deposit
// @note add assertion that vault::round_positions[lp, next_id] updates decrements (need to add vault entry point for get_lp_deposit_in_round)
#[test]
#[available_gas(10000000)]
fn test_withdraw_from_rewards_and_deposits_updates_collateral_and_unallocated() {
    let (mut vault_facade, _) = setup_facade();
    // Accelerate to round 1 running
    accelerate_to_running(ref vault_facade);
    // Add liquidity to next round (unallocated)
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Current round (running), next round (open)
    let mut current_round = vault_facade.get_current_round();
    let mut next_round = vault_facade.get_next_round();
    let current_params = current_round.get_params();
    // Amount of premiums earned from the auction (plus unsold liq) for LP 
    let premiums_earned = current_params.total_options_available
        * current_params
            .reserve_price; // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // Initial collateral/unallocated
    let (init_lp_collateral, init_lp_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (init_current_round_collateral, init_current_round_unallocated) = current_round
        .get_all_round_liquidity();
    let (init_next_round_collateral, init_next_round_unallocated) = next_round
        .get_all_round_liquidity();
    // Withdraw from rewards
    let withdraw_amount = premiums_earned + 1;
    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
    // Final collateral/unallocated
    let (final_lp_collateral, final_lp_unallocated) = vault_facade
        .get_all_lp_liquidity(liquidity_provider_1());
    let (final_current_round_collateral, final_current_round_unallocated) = current_round
        .get_all_round_liquidity();
    let (final_next_round_collateral, final_next_round_unallocated) = next_round
        .get_all_round_liquidity();
    // Check collateral is untouched
    assert(final_lp_collateral == init_lp_collateral, 'lp collateral wrong');
    assert(
        final_current_round_collateral == init_current_round_collateral,
        'current round collateral wrong'
    );
    assert(
        final_next_round_collateral == init_next_round_collateral, 'next round collateral wrong'
    );
    // Check unallocated is updated
    assert(final_lp_unallocated == init_lp_unallocated - withdraw_amount, 'lp unallocated wrong');
    assert(
        final_current_round_unallocated == init_current_round_unallocated - premiums_earned,
        'current round unallocated wrong'
    );
    assert(
        final_next_round_unallocated == init_next_round_unallocated - 1,
        'next round unallocated wrong'
    );
}
// @note There should already be a test that any withdraw > total_unallocated_for_lp reverts
// @note Add test for checking a vault storage var for current round collections is updated to reflect how much LP collects (premiums/unsold) from the current round


