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

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait};
use pitch_lake_starknet::option_round::{OptionRoundParams};

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
use pitch_lake_starknet::tests::utils::{setup, deploy_vault, allocated_pool_address, unallocated_pool_address
                                        , timestamp_start_month, timestamp_end_month, liquidity_provider_1, 
                                        liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2,
                                         option_bidder_buyer_3, option_bidder_buyer_4, vault_manager, weth_owner, mock_option_params};

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_to_after_collaterization() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount : u256 = 50;
    let option_price : u256 = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

    let success : bool = vault_dispatcher.withdraw_liquidity(lp_id, deposit_amount_wei);
    assert(success == false, 'cannot withdraw');
    //should not be able to withdraw because the liquidity has been moves to the collaterizedpool
}

#[test]
#[available_gas(10000000)]
fn test_total_collaterized_wei_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());

    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    let lp_id : u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);  
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

    // start auction will move the tokens from unallocated pool to collaterized pool within the option_round
    let allocated_wei = vault_dispatcher.total_collateral();
    assert( allocated_wei == deposit_amount_wei, 'all tokens shld be collaterized');
}

#[test]
#[available_gas(10000000)]
fn test_total_collaterized_wei_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei_1 = 10000 * vault_dispatcher.decimals().into();
    let deposit_amount_wei_2 = 10000 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let lp_id_1:u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei_1);  
    set_contract_address(liquidity_provider_2());
    let lp_id_2:u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei_2);  

    // start_new_option_round will also starts the auction
    let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

    // start auction will move the tokens from unallocated pool to collaterized pool within the option_round
    let collaterized_wei_count :u256 = vault_dispatcher.total_collateral();
    let unallocated_wei_count :u256 = vault_dispatcher.total_unallocated_liquidity();
    assert( collaterized_wei_count == deposit_amount_wei_1 + deposit_amount_wei_2, 'all tokens shld be collaterized');
    assert( unallocated_wei_count == 0,'unallocated should be 0');
}
