use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    VaultType
};
use pitch_lake_starknet::option_round::{OptionRoundParams};
use pitch_lake_starknet::pitch_lake::{
    IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
    IPitchLakeSafeDispatcherTrait
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
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    vault_manager, weth_owner, option_round_contract_address, mock_option_params, pop_log,
    assert_no_events_left, deploy_pitch_lake
};


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'cannot generate params for zero liquidity'))]
fn test_start_option_zero_liquidity() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Start the option round
    let (option_round_id, _): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round_new();
}


// find out why commented out
// #[test]
// #[available_gas(10000000)]
// #[should_panic(expected: ('Some error', 'end date must be greater than start date'))]
// fn test_option_dates_valid() {

//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_amount_wei:u256 = 100 * decimals();
//     set_contract_address(liquidity_provider_1());
//     let lp_id : u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
//     let params : OptionRoundParams = vault_dispatcher.generate_option_round_params(timestamp_end_month(), timestamp_start_month() );
// }

#[test]
#[available_gas(10000000)]
fn test_strike_price_based_on_vault_types() {
    let pitch_lake_dispatcher: IPitchLakeDispatcher = deploy_pitch_lake();
    // Deploy vaults
    let vault_dispatcher_at_the_money: IVaultDispatcher = pitch_lake_dispatcher
        .at_the_money_vault();
    let vault_dispatcher_in_the_money: IVaultDispatcher = pitch_lake_dispatcher
        .in_the_money_vault();
    let vault_dispatcher_out_the_money: IVaultDispatcher = pitch_lake_dispatcher
        .out_the_money_vault();
    /// Deposit liquidity
    let deposit_amount_wei: u256 = 100 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id_1: u256 = vault_dispatcher_at_the_money.open_liquidity_position(deposit_amount_wei);
    let lp_id_2: u256 = vault_dispatcher_in_the_money.open_liquidity_position(deposit_amount_wei);
    let lp_id_3: u256 = vault_dispatcher_out_the_money.open_liquidity_position(deposit_amount_wei);

    // Start the option rounds and compare the strike prices
    let (round_id, params) = vault_dispatcher_in_the_money.start_new_option_round_new();
    assert(params.strike_price > params.current_average_basefee, ' ITM strike > average basefee');

    let (round_id, params) = vault_dispatcher_at_the_money.start_new_option_round_new();
    assert(params.strike_price == params.current_average_basefee, ' ATM strike == average basefee');

    let (round_id, params) = vault_dispatcher_out_the_money.start_new_option_round_new();
    assert(params.strike_price < params.current_average_basefee, ' OTM strike < average basefee');
}
