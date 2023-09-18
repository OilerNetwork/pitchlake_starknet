use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait, Transfer, VaultType};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};
use pitch_lake_starknet::pitch_lake::{IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake, IPitchLakeSafeDispatcherTrait};

use result::ResultTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{setup, deploy_vault, allocated_pool_address, unallocated_pool_address
                                        , timestamp_start_month, timestamp_end_month, liquidity_provider_1, 
                                        liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2,
                                         option_bidder_buyer_3, option_bidder_buyer_4, vault_manager, weth_owner,
                                         option_round_contract_address, mock_option_params, pop_log, assert_no_events_left, deploy_pitch_lake};



#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'cannot generate params for zero liquidity'))]
fn test_start_option_zero_liquidity() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let params : OptionRoundParams = vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month() );
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'end date must be greater than start date'))]
fn test_option_dates_valid() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 100 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_1());
    let params : OptionRoundParams = vault_dispatcher.generate_option_round_params(timestamp_end_month(), timestamp_start_month() );
}


#[test]
#[available_gas(10000000)]
fn test_strike_price_based_on_vault_types() {

    let pitch_lake_dispatcher: IPitchLakeDispatcher = deploy_pitch_lake();
    let vault_dispatcher_at_the_money: IVaultDispatcher = pitch_lake_dispatcher.at_the_money_vault();
    let vault_dispatcher_in_the_money: IVaultDispatcher = pitch_lake_dispatcher.in_the_money_vault();
    let vault_dispatcher_out_the_money: IVaultDispatcher = pitch_lake_dispatcher.out_the_money_vault();

    let deposit_amount_wei:u256 = 100 * vault_dispatcher_at_the_money.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher_at_the_money.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_1());
    vault_dispatcher_in_the_money.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_1());
    vault_dispatcher_out_the_money.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_1());

    let params : OptionRoundParams = vault_dispatcher_in_the_money.generate_option_round_params(timestamp_start_month(), timestamp_end_month() );
    assert(params.strike_price >  params.current_average_basefee, ' ITM strike > average basefee');

    let params : OptionRoundParams = vault_dispatcher_at_the_money.generate_option_round_params(timestamp_start_month(), timestamp_end_month() );
    assert(params.strike_price ==  params.current_average_basefee, ' ITM strike == average basefee');

    let params : OptionRoundParams = vault_dispatcher_out_the_money.generate_option_round_params(timestamp_start_month(), timestamp_end_month() );
    assert(params.strike_price <  params.current_average_basefee, ' ITM strike < average basefee');

}




