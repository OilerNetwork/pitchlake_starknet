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
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, mock_option_params
};

// Test that LP can withdraw their liquidity during the round transition period (uncollaterized liquidity)
#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_when_unlocked_success() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Init balances
    let next_round = vault_dispatcher
        .get_option_round_address(vault_dispatcher.current_option_round_id() + 1);
    let lp_balance_before: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_before: u256 = eth_dispatcher.balance_of(next_round);

    // Deposit liquidity into next (open) round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);

    let lp_balance_after: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_after: u256 = eth_dispatcher.balance_of(next_round);

    // Check liquidity was deposited
    assert(
        lp_balance_after == lp_balance_before - deposit_amount_wei, 'LP balance should decrease'
    );
    assert(
        round_balance_after == round_balance_before + deposit_amount_wei,
        'Round balance should increase'
    );

    // Withdraw liquidity while current round is locked
    vault_dispatcher.withdraw_from_position(deposit_amount_wei);

    // Check liquidity was withdrawn
    let lp_balance_after_withdraw: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let round_balance_after_withdraw: u256 = eth_dispatcher.balance_of(next_round);
    assert(
        lp_balance_after_withdraw == lp_balance_after + deposit_amount_wei,
        'LP balance should increase'
    );
    assert(
        round_balance_after_withdraw == round_balance_after - deposit_amount_wei,
        'Round balance should decrease'
    );
}

// Test that LP cannot withdraw their liquidity while not in the round transition period
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'Cannot withdraw, liquidity locked',))]
fn test_withdraw_liquidity_when_locked_failure() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Deposit liquidity into next (open) round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);

    // Start the auction, locking the liquidity
    vault_dispatcher.start_auction();

    // Try to withdraw liquidity while current round is locked
    vault_dispatcher.withdraw_from_position(deposit_amount_wei);
}

//
#[test]
#[available_gas(10000000)]
fn test_total_collaterized_wei_1() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();
    // Add liq. to next round (1)
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 50 * decimals();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // Start the option round
    vault_dispatcher.start_auction();
    // OptionRoundDispatcher
    let current_round: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher
            .get_option_round_address(vault_dispatcher.current_option_round_id())
    };
    let params = current_round.get_params();

    // Place bid
    set_contract_address(option_bidder_buyer_1());
    let option_amount: u256 = params.total_options_available;
    let option_price: u256 = params.reserve_price;
    let bid_amount: u256 = option_amount * option_price;
    current_round.place_bid(bid_amount, option_price);
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    current_round.end_auction();
    // Settle option round
    set_block_timestamp(params.option_expiry_time + 1);
    current_round.settle_option_round();

    ///////////////

    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // start auction will move the tokens from unallocated pool to collaterized pool within the option_round
    let allocated_wei = round_dispatcher.total_collateral();
    assert(allocated_wei == deposit_amount_wei, 'all tokens shld be collaterized');
}

#[test]
#[available_gas(10000000)]
fn test_total_collaterized_wei_2() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei_1 = 10000 * decimals();
    let deposit_amount_wei_2 = 10000 * decimals();

    set_contract_address(liquidity_provider_1());
    let lp_id_1: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei_1);
    set_contract_address(liquidity_provider_2());
    let lp_id_2: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei_2);

    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // start auction will move the tokens from unallocated pool to collaterized pool within the option_round
    let collaterized_wei_count: u256 = round_dispatcher.total_collateral();
    // todo: is this still needed with new logic ? unallocated is always 0 ?
    let unallocated_wei_count: u256 = vault_dispatcher.total_unallocated_liquidity();
    assert(
        collaterized_wei_count == deposit_amount_wei_1 + deposit_amount_wei_2,
        'all tokens shld be collaterized'
    );
    assert(unallocated_wei_count == 0, 'unallocated should be 0');
}
// @note add test that only the vault can call option_round.settle_option_round() (anyone can call the wrapper)
// wrapper makes sure the liquidity rolls over and the round transition period starts


