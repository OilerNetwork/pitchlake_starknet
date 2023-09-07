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

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait, OptionParams};
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
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner};




#[test]
#[available_gas(10000000)]
fn test_settle_before_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(option_amount, option_price);
    vault_dispatcher.end_auction();

    set_block_timestamp(option_params.expiry_time - 10000);
    let success = vault_dispatcher.settle(option_params.strike_price + 10);
    assert(success == false, 'no settle before expiry');
}

#[test]
#[available_gas(10000000)]
fn test_settle_before_end_auction() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount:u256 = 50;
    let option_price:u256 = 2;
    let final_settlement_price:u256 = 30;
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(option_params.expiry_time );
    let success = vault_dispatcher.settle(final_settlement_price);

    assert(success == false, 'no settle before auction end');
}
