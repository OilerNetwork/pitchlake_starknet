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

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait, VaultTransfer, OptionRoundCreated};
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
use pitch_lake_starknet::tests::utils;
use pitch_lake_starknet::tests::utils::{setup, deploy_vault, allocated_pool_address, unallocated_pool_address
                                        , timestamp_start_month, timestamp_end_month, liquidity_provider_1, 
                                        liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2,
                                         option_bidder_buyer_3, option_bidder_buyer_4, zero_address, vault_manager, weth_owner,
                                         option_round_contract_address, mock_option_params, pop_log, assert_no_events_left};
///helpers

fn assert_event_transfer(from: ContractAddress, to: ContractAddress, amount: u256) {
    let event = pop_log::<VaultTransfer>(zero_address()).unwrap();
    assert(event.from == from, 'Invalid `from`');
    assert(event.to == to, 'Invalid `to`');
    assert(event.amount == amount, 'Invalid `amount`');
    assert_no_events_left(zero_address());
}

///tests

#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_zero() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 0 ;
    set_contract_address(liquidity_provider_1());

    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());

    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
}

#[test]
#[available_gas(10000000)]
fn test_deposit_withdraw_liquidity_zero() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10 * vault_dispatcher.decimals().into() ;
    set_contract_address(liquidity_provider_1());

    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());

    set_contract_address(liquidity_provider_1());
    vault_dispatcher.withdraw_liquidity(lp_id, 0);
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());

    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
    assert_event_transfer(vault_dispatcher.contract_address, liquidity_provider_1() , deposit_amount_wei);

}

#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    assert(success == true, 'cannot deposit');
    assert_event_transfer(liquidity_provider_1(), vault_dispatcher.contract_address, deposit_amount_wei);

}

#[test]
#[available_gas(10000000)]
fn test_deposit_liquidity_count_increase() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let wei_balance_before_deposit:u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let wei_after_before_deposit:u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());

    assert(wei_after_before_deposit == wei_balance_before_deposit + deposit_amount_wei, 'deposit should add up');
    assert_event_transfer(liquidity_provider_1(), vault_dispatcher.contract_address, deposit_amount_wei);

}

#[test]
#[available_gas(10000000)]
fn test_eth_has_decreased_after_deposit() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into() ;
    let wei_amount_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let wei_amount_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    
    assert(wei_amount_after_transfer == wei_amount_before_transfer - deposit_amount_wei  , 'deposit is not decremented');
    assert_event_transfer(liquidity_provider_1(), vault_dispatcher.contract_address, deposit_amount_wei);

}

#[test]
#[available_gas(10000000)]
fn test_eth_has_increased_after_withdrawal() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let wei_amount_before_withdrawal: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    vault_dispatcher.withdraw_liquidity(lp_id, deposit_amount_wei);
    let wei_amount_after_withdrawal: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let unallocated_wei:u256 = vault_dispatcher.total_unallocated_liquidity();    
    assert(wei_amount_before_withdrawal == wei_amount_after_withdrawal + deposit_amount_wei, 'withdrawal is not incremented');
    assert(unallocated_wei == 0, 'unalloc after withdrawal,0');

    assert_event_transfer(liquidity_provider_1(), vault_dispatcher.contract_address, deposit_amount_wei);
    assert_event_transfer(vault_dispatcher.contract_address, liquidity_provider_1(), deposit_amount_wei);

}

#[test]
#[available_gas(10000000)]
fn test_unallocated_wei_count_1() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let tokens:u256 = vault_dispatcher.total_unallocated_liquidity();    
    assert(tokens == deposit_amount_wei, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_unallocated_wei_count_user_1() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    let user_balance:u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());
    assert(user_balance == deposit_amount_wei, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_unallocated_wei_count_user_2() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    set_contract_address(liquidity_provider_2());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_2(), liquidity_provider_1());

    let user_balance:u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());
    assert(user_balance == deposit_amount_wei * 2, 'should equal to deposited'); // since both users deposited for liquidity_provider_1()

}

#[test]
#[available_gas(10000000)]
fn test_unallocated_wei_count_2() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    set_contract_address(liquidity_provider_2());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_2(), liquidity_provider_2());

    let tokens:u256 = vault_dispatcher.total_unallocated_liquidity();    
    assert(tokens == deposit_amount_wei * 2, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_to() {
 
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_1());
    let success:bool  = vault_dispatcher.withdraw_liquidity_to(deposit_amount_wei, liquidity_provider_1());
    assert(success == true, 'should be able to withdraw');

}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'not enough balance',))]
fn test_withdraw_liquidity_to_invalid_user_1() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_1());
    set_contract_address(liquidity_provider_2());
    vault_dispatcher.withdraw_liquidity_to(deposit_amount_wei, liquidity_provider_2());
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'not enough balance',))]
fn test_withdraw_liquidity_to_invalid_user_2() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_1(), liquidity_provider_2());
    vault_dispatcher.withdraw_liquidity_to(deposit_amount_wei, liquidity_provider_1()); // liquidity_provider_1() doesnt owns the liquidity anymore.
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'invalid user',))]
fn test_withdraw_liquidity_to_invalid_user_3() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei, liquidity_provider_2(), liquidity_provider_1());
}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_for_registered_user() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(option_round_contract_address());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei, option_round_contract_address(), liquidity_provider_2());
    let success:bool  = vault_dispatcher.withdraw_liquidity_to(deposit_amount_wei, liquidity_provider_2());
    assert(success == true, 'should be able to withdraw'); // liquidity_provider_2 should be able to withdraw since depositer registered it for another user
}


// #[test]
// #[available_gas(10000000)]
// fn test_transfer_bidder_to_option_round() {
//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

//     let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
//     set_contract_address(liquidity_provider_1());
//     let lp_id:u256  = vault_dispatcher.open_liquidity_position(deposit_amount_wei);  
//     // start_new_option_round will also starts the auction
//     let option_params : OptionRoundParams =  vault_dispatcher.generate_option_round_params( timestamp_end_month());
 //       let round_dispatcher : IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(option_params);
//     let bid_amount_user_1 :u256 =  (option_params.total_options_available) ;
    
//     set_contract_address(option_bidder_buyer_1());
//     round_dispatcher.auction_place_bid(bid_amount_user_1, option_params.reserve_price);

//     let options_created_count = round_dispatcher.total_options_sold();
//     assert( options_created_count == bid_amount_user_1, 'options shd match');
// }



