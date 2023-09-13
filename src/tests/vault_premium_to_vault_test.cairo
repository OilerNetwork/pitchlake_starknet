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
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};

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
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address
                                        , timestamp_start_month, timestamp_end_month, liquidity_provider_1, 
                                        liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2,
                                         option_bidder_buyer_3, option_bidder_buyer_4, vault_manager, weth_owner, mock_option_params};



#[test]
#[available_gas(10000000)]
fn test_paid_premium_withdrawal() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    
    let deposit_amount_wei:u256 = 100000 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    
    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2);
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_amount_user_1, option_params.reserve_price); 
    round_dispatcher.end_auction();

    set_contract_address(liquidity_provider_1());
    round_dispatcher.transfer_premium_paid_to_vault();

    let expected_unallocated_wei:u256 = round_dispatcher.get_auction_clearing_price() * round_dispatcher.total_options_sold();
    let success: bool = vault_dispatcher.withdraw_liquidity(expected_unallocated_wei);
    assert( success == true, 'should be able withdraw premium');
}




#[test]
#[available_gas(10000000)]
fn test_premium_conversion_unallocated_pool_1 () {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    
    let deposit_amount_wei_1:u256 = 1000 * vault_dispatcher.decimals().into();
    let deposit_amount_wei_2:u256 = 10000 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei_1);  

    set_contract_address(liquidity_provider_2());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei_2);  

    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_count_user_1 :u256 =  (option_params.total_options_available) ;
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, option_params.reserve_price); 
   
    round_dispatcher.end_auction();

    //premium paid will be converted into unallocated.
    set_contract_address(liquidity_provider_1());
    round_dispatcher.transfer_premium_paid_to_vault();

    set_contract_address(liquidity_provider_2());
    round_dispatcher.transfer_premium_paid_to_vault();

    //premium paid will be converted into unallocated.
    let total_collateral :u256 = round_dispatcher.total_collateral();
    let total_premium_to_be_paid:u256 = round_dispatcher.get_auction_clearing_price() * round_dispatcher.total_options_sold();

    let ratio_of_liquidity_provider_1 : u256 = (round_dispatcher.collateral_balance_of(liquidity_provider_1()) * 100) / total_collateral;
    let ratio_of_liquidity_provider_2 : u256 = (round_dispatcher.collateral_balance_of(liquidity_provider_2()) * 100) / total_collateral;

    let premium_for_liquidity_provider_1 : u256 = (ratio_of_liquidity_provider_1 * total_premium_to_be_paid) / 100;
    let premium_for_liquidity_provider_2 : u256 = (ratio_of_liquidity_provider_2 * total_premium_to_be_paid) / 100;

    let actual_unallocated_balance_provider_1 : u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());
    let actual_unallocated_balance_provider_2 : u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_2());

    assert( actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1, 'premium paid in ratio');
    assert( actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2, 'premium paid in ratio');

}

#[test]
#[available_gas(10000000)]
fn test_premium_conversion_unallocated_pool_2 () {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    
    let deposit_amount_wei:u256 = 10000 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    
    set_contract_address(liquidity_provider_2());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  

    // start_new_option_round will also starts the auction
    let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params(timestamp_start_month(), timestamp_end_month());
    let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);

    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2) + 1;
    let bid_amount_user_2 :u256 =  (option_params.total_options_available/2) ;
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_amount_user_1, option_params.reserve_price); 

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_amount_user_2, option_params.reserve_price); 
    
    round_dispatcher.end_auction();

    set_contract_address(liquidity_provider_1());
    round_dispatcher.transfer_premium_paid_to_vault();
    set_contract_address(liquidity_provider_2());
    round_dispatcher.transfer_premium_paid_to_vault();

    //premium paid will be converted into unallocated.
    let unallocated_wei_count :u256 = vault_dispatcher.total_unallocated_liquidity();
    let expected_unallocated_wei:u256 = round_dispatcher.get_auction_clearing_price() * option_params.total_options_available;
    assert( unallocated_wei_count == expected_unallocated_wei, 'paid premiums should translate');
}
