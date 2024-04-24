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
use pitch_lake_starknet::tests::vault::utils::{accelerate_to_running};

// Test withdraw > lp unallocated fails
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Withdraw > unallocated balance', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_more_than_unallocated_balance_failure() {
    let (mut vault_facade, _) = setup_facade();
    // Accelerate to round 1 running
    accelerate_to_running(ref vault_facade);
    // Current round (running), next round (open)
    let mut current_round = vault_facade.get_current_round();
    let current_params = current_round.get_params();
    // Make deposit into next round
    let deposit_amount = 100 * decimals();
    vault_facade.deposit(deposit_amount, liquidity_provider_1());
    // Amount of premiums earned from the auction (plus unsold liq) for LP 
    let premiums_earned = current_round.total_options_sold()
        * current_params
            .reserve_price; // @dev lp owns 100% of the pool, so 100% of the prmeium is theirs
    // LP unallocated is premiums earned + next round deposits
    let (_, lp_unallocated) = vault_facade.get_all_lp_liquidity(liquidity_provider_1());
    // Withdraw from rewards
    let withdraw_amount = lp_unallocated + 1;
    assert(lp_unallocated == premiums_earned + deposit_amount, 'LP unallocated wrong');
    vault_facade.withdraw(withdraw_amount, liquidity_provider_1());
}

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
