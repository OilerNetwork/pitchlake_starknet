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
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner};


//////////////////////////////
/// liquidity/token count tests
/////////////////////////////


#[test]
#[available_gas(10000000)]
fn test_deploy_liquidity_zero() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 0 ;
    set_contract_address(liquidity_provider_1());

    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());

    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
}

#[test]
#[available_gas(10000000)]
fn test_deploy_withdraw_liquidity_zero() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 10 * vault_dispatcher.decimals().into() ;
    set_contract_address(liquidity_provider_1());

    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let balance_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    vault_dispatcher.withdraw_liquidity(0);
    let balance_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());

    assert(balance_before_transfer == balance_after_transfer, 'zero deposit should not effect');
}



#[test]
#[available_gas(10000000)]
fn test_deploy_liquidity() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    assert(success == true, 'cannot deposit');

}


#[test]
#[available_gas(10000000)]
fn test_deploy_liquidity_count_increase() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let wei_balance_before_deposit:u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let wei_after_before_deposit:u256 = vault_dispatcher.unallocated_liquidity_balance_of(liquidity_provider_1());
    assert(wei_after_before_deposit == wei_balance_before_deposit + deposit_amount_wei, 'deposit should add up');

}

#[test]
#[available_gas(10000000)]
fn test_eth_has_descreased_after_deposit() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into() ;
    let wei_amount_before_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let wei_amount_after_transfer: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    assert(wei_amount_after_transfer == wei_amount_before_transfer - deposit_amount_wei  , 'deposit is not decremented');
}

#[test]
#[available_gas(10000000)]
fn test_eth_has_increased_after_withdrawal() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let wei_amount_before_withdrawal: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
    let wei_amount_after_withdrawal: u256 = eth_dispatcher.balance_of(liquidity_provider_1());
    let unallocated_tokens:u256 = vault_dispatcher.total_liquidity_unallocated();    
    assert(wei_amount_before_withdrawal == wei_amount_after_withdrawal + deposit_amount_wei, 'withdrawal is not incremented');
    assert(unallocated_tokens == 0, 'unalloc after withdrawal,0');
}

#[test]
#[available_gas(10000000)]
fn test_unallocated_token_count() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let tokens:u256 = vault_dispatcher.total_liquidity_unallocated();    
    assert(tokens == deposit_amount_wei, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity() {
 
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
    assert(success == true, 'should be able to withdraw');

}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'not enough balance',))]
fn test_withdraw_liquidity_valid_user() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    set_contract_address(liquidity_provider_2());
    vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'not enough balance in liquidity pool',))]
fn test_withdraw_liquidity_allocation() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
    //should not be able to withdraw because the liquidity has been moves to the collaterized/collaterized pool
}


#[test]
#[available_gas(10000000)]
fn test_bid_below_reserve_price() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);

    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
    // bid below reserve price
    let bid_below_reserve :u256 =  option_params.reserve_price - 1;

    set_contract_address(option_bidder_buyer_1());
    let success = round_dispatcher.bid(2, bid_below_reserve );
    assert(success == false, 'should not be able to bid');
}

#[test]
#[available_gas(10000000)]
fn test_bid_before_auction_start() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
    set_contract_address(option_bidder_buyer_1());
    let success = round_dispatcher.bid(option_amount, option_price);
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(10000000)]
fn test_total_collaterized_tokens_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());

    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    // start auction will move the tokens from unallocated pool to collaterized pool
    let allocated_tokens = round_dispatcher.total_collateral();
    assert( allocated_tokens == deposit_amount_wei, 'all tokens shld be collaterized');
}

#[test]
#[available_gas(10000000)]
fn test_total_collaterized_tokens_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei_1 = 1000000 * vault_dispatcher.decimals().into();
    let deposit_amount_wei_2 = 1000000 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei_1);  
    set_contract_address(liquidity_provider_2());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei_2);  

    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
     // auction also moves the tokens

    // start auction will move the tokens from unallocated pool to collaterized pool
    let allocated_token_count :u256 = round_dispatcher.total_collateral();
    let unallocated_token_count :u256 = vault_dispatcher.total_liquidity_unallocated();
    assert( allocated_token_count == deposit_amount_wei_1 + deposit_amount_wei_2, 'all tokens shld be collaterized');
    assert( unallocated_token_count == 0,'unallocated should be 0');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_allocation_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 1000000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(option_params.total_options_available/2 + 1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(option_params.total_options_available/2, option_params.reserve_price); 
    round_dispatcher.end_auction();

    let options_created_count = round_dispatcher.total_options_sold();
    assert( options_created_count == option_params.total_options_available, 'all tokens shld be collaterized');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_allocation_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2) + 1;
    let bid_amount_user_2 :u256 =  (option_params.total_options_available/2) ;
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_amount_user_1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_amount_user_2, option_params.reserve_price - 10); 
    round_dispatcher.end_auction();

    let options_created_count = round_dispatcher.total_options_sold();
    assert( options_created_count == bid_amount_user_1, 'options shd match');
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

    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count_user_1 :u256 =  (option_params.total_options_available) ;
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, option_params.reserve_price); 
   
    round_dispatcher.end_auction();

    //premium paid will be converted into unallocated.
    let unallocated_token_count :u256 = round_dispatcher.total_collateral();
    let total_premium_to_be_paid:u256 = round_dispatcher.get_auction_clearing_price() * round_dispatcher.total_options_sold();

    let ratio_of_liquidity_provider_1 : u256 = (round_dispatcher.collateral_balance_of(liquidity_provider_1()) * 100) / unallocated_token_count;
    let ratio_of_liquidity_provider_2 : u256 = (round_dispatcher.collateral_balance_of(liquidity_provider_2()) * 100) / unallocated_token_count;

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

    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2) + 1;
    let bid_amount_user_2 :u256 =  (option_params.total_options_available/2) ;
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_amount_user_1, option_params.reserve_price); 

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_amount_user_2, option_params.reserve_price); 
    
    round_dispatcher.end_auction();

    //premium paid will be converted into unallocated.
    let unallocated_token_count :u256 = vault_dispatcher.total_liquidity_unallocated();
    let expected_unallocated_token:u256 = round_dispatcher.get_auction_clearing_price() * option_params.total_options_available;
    assert( unallocated_token_count == expected_unallocated_token, 'paid premiums should translate');
}

#[test]
#[available_gas(10000000)]
fn test_paid_premium_withdrawal() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    
    let deposit_amount_wei:u256 = 100000 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2);
    
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_amount_user_1, option_params.reserve_price); 
    round_dispatcher.end_auction();

    let expected_unallocated_token:u256 = round_dispatcher.get_auction_clearing_price() * round_dispatcher.total_options_sold();
    let success: bool = vault_dispatcher.withdraw_liquidity(expected_unallocated_token);
    assert( success == true, 'should be able withdraw premium');
}


#[test]
#[available_gas(10000000)]
fn test_option_count() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let options_created = round_dispatcher.total_options_sold();
    assert(options_created == bid_count, 'options equal successful bids');
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == option_params.reserve_price, 'clear price equal reserve price');
}


#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1 : u256 = option_params.reserve_price;
    let bid_price_user_2 : u256 = option_params.reserve_price + 10;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, bid_price_user_1 );
    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count,  bid_price_user_2);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count_user_1: u256 = option_params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;

    let bid_price_user_1 : u256 = option_params.reserve_price + 100;
    let bid_price_user_2 : u256 = option_params.reserve_price ;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, bid_price_user_1 );

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count_user_2,  bid_price_user_2);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   


#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());

    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    let eth_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(eth_balance_before_bid == eth_balance_after_bid + (bid_count * option_params.reserve_price), 'bid amounts should be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_eth_unused_for_rejected_bids() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());

    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price - 100);
    let eth_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(eth_balance_before_bid == eth_balance_after_bid, 'bid should not be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_eth_refund_for_unused_bids() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = option_params.total_options_available + 10;
    set_contract_address(option_bidder_buyer_1());
    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);

    round_dispatcher.end_auction();
    let eth_balance_after_auction :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(eth_balance_before_bid == eth_balance_after_auction + ((bid_count - option_params.total_options_available) * option_params.reserve_price), 'bid amounts should be locked up');
} 

#[test]
#[available_gas(10000000)]
fn test_option_count_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let options_created = round_dispatcher.total_options_sold();
    assert(options_created == bid_count, 'options equal successful bids');
}
