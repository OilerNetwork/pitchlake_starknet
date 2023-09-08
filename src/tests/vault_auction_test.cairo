

use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner};

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

use traits::Into;
use traits::TryInto;


#[test]
#[available_gas(10000000)]
fn test_bid_after_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(option_params.expiry_time );
    round_dispatcher.end_auction();
    let success = round_dispatcher.bid(option_amount, option_price);

    assert(success == false, 'no bid after expiry');
}


#[test]
#[available_gas(10000000)]
fn test_withdrawal_after_premium() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    
    let unallocated_token_before_premium = vault_dispatcher.total_liquidity_unallocated();
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(option_amount, option_params.reserve_price); 
    round_dispatcher.settle(option_params.strike_price - 100 , ArrayTrait::new()); // means there is no payout.
    round_dispatcher.end_auction();
    let unallocated_token_after_premium = vault_dispatcher.total_liquidity_unallocated();
    assert(unallocated_token_before_premium < unallocated_token_after_premium, 'premium should have paid out');
}
