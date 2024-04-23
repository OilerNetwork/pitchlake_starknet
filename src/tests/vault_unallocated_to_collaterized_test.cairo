use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
};
use pitch_lake_starknet::option_round::{
    OptionRoundParams, IOptionRoundDispatcher, IOptionRoundDispatcherTrait
};

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
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, mock_option_params
};
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};

// @note move to vault/auction_end tests
// Test that LP can withdraw their liquidity during the round transition period (uncollaterized liquidity)
#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_when_unlocked_success() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Init balances
    let next_round_address = vault_facade
        .get_option_round_address(vault_facade.current_option_round_id() + 1);
    let lp_balance_before: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_before: u256 = eth_dispatcher.balance_of(next_round_address);

    // Deposit liquidity into next (open) round
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    let lp_balance_after: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_after: u256 = eth_dispatcher.balance_of(next_round_address);

    // Check liquidity was deposited
    assert(
        lp_balance_after == lp_balance_before - deposit_amount_wei, 'LP balance should decrease'
    );
    assert(
        round_balance_after == round_balance_before + deposit_amount_wei,
        'Round balance should increase'
    );

    // Withdraw liquidity while current round is locked
    vault_facade.withdraw(deposit_amount_wei, liquidity_provider_1());

    // Check liquidity was withdrawn
    let lp_balance_after_withdraw: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_after_withdraw: u256 = eth_dispatcher.balance_of(next_round_address);
    assert(
        lp_balance_after_withdraw == lp_balance_after + deposit_amount_wei,
        'LP balance should increase'
    );
    assert(
        round_balance_after_withdraw == round_balance_after - deposit_amount_wei,
        'Round balance should decrease'
    );
}

// @note change/remove this, test needs to test deposit locks (unallocated->collateral) when auction start (vault/auction_start_tests)
// Test that LP cannot withdraw their liquidity while not in the round transition period
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Cannot withdraw, liquidity locked',))]
fn test_withdraw_liquidity_when_locked_failure() {
    let (mut vault_facade, _) = setup_facade();

    // Deposit liquidity into next (open) round
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());

    // Start the auction, locking the liquidity
    vault_facade.start_auction();

    // Try to withdraw liquidity while current round is locked
    vault_facade.withdraw(deposit_amount_wei, liquidity_provider_1());
}

// @note move to vault/auction_start tests
// Test that round's unallocated liquidity becomes collateral when auction start (multiple LPs)
#[test]
#[available_gas(10000000)]
fn test_round_unallocated_becomes_collateral_when_auction_starts() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round: OptionRoundFacade = vault_facade.get_current_round();
    // Add liq. to next round (1)
    let deposit_amount_wei_1 = 1000 * decimals();
    let deposit_amount_wei_2 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());
    let total_unallocated = current_round.total_unallocated_liquidity();
    assert(
        total_unallocated == deposit_amount_wei_1 + deposit_amount_wei_2,
        'all tokens shd be unallocated'
    );
    // Start the option round
    vault_facade.start_auction();
    // Check that unallocated amount is now collaterized
    let total_collateral = current_round.total_collateral();
    assert(total_collateral == total_unallocated, 'all tokens shld be collaterized');
}

// @note move to vault/auction_start tests
// Test that LP's unallocated becomes collateral when auction start (multiple LPs)
#[test]
#[available_gas(10000000)]
fn test_LP_unallocated_becomes_collateral_when_auction_starts() {
    let (mut vault_facade, eth_dispatcher) = setup_facade();
    // Add liq. to next round (1)
    let deposit_amount_wei_1 = 10000 * decimals();
    let deposit_amount_wei_2 = 11000 * decimals();
    vault_facade.deposit(deposit_amount_wei_1, liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei_2, liquidity_provider_2());
    let total_unallocated_1 = vault_facade.get_unallocated_balance_for(liquidity_provider_1());
    let total_unallocated_2 = vault_facade.get_unallocated_balance_for(liquidity_provider_2());
    assert(total_unallocated_1 == deposit_amount_wei_1, 'all tokens1 shd be unallocated');
    assert(total_unallocated_2 == deposit_amount_wei_2, 'all tokens2 shd be unallocated');
    // Start the option round
    vault_facade.start_auction();
    // Check that unallocated amount is now collaterized
    let total_collateral_1 = vault_facade.get_collateral_balance_for(liquidity_provider_1());
    let total_collateral_2 = vault_facade.get_collateral_balance_for(liquidity_provider_2());
    assert(total_collateral_1 == total_unallocated_1, 'all tokens1 shd be collateral');
    assert(total_collateral_2 == total_unallocated_2, 'all tokens2 shd be collateral');
}
// @note add test that only the vault can call option_round.settle_option_round() (anyone can call the wrapper)
// - wrapper makes sure the liquidity rolls over and the round transition period starts


