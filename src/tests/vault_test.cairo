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
use pitch_lake_starknet::tests::utils::{allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner};


const NAME: felt252 = 'WETH';
const SYMBOL: felt252 = 'WETH';
const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 99999999999999999999999999999; 

fn deployEth() ->  IERC20Dispatcher {
    let mut calldata = array![];

    calldata.append_serde(NAME);
    calldata.append_serde(SYMBOL);
    calldata.append_serde(SUPPLY);
    calldata.append_serde(weth_owner());

    let (address, _) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IERC20Dispatcher{contract_address: address};
}

fn deployVault() ->  IVaultDispatcher {
    let mut calldata = array![];

    calldata.append_serde(allocated_pool_address());
    calldata.append_serde(unallocated_pool_address());

    let (address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IVaultDispatcher{contract_address: address};
}

fn setup() -> (IVaultDispatcher, IERC20Dispatcher){

    let eth_dispatcher : IERC20Dispatcher = deployEth();
    let vault_dispatcher : IVaultDispatcher = deployVault();
    set_contract_address(weth_owner());
    let deposit_amount_ether : u256 = 1000000;
    let deposit_amount_wei: u256 = deposit_amount_ether  * eth_dispatcher.decimals().into();

    eth_dispatcher.transfer(liquidity_provider_1(),deposit_amount_wei);
    eth_dispatcher.transfer(liquidity_provider_2(),deposit_amount_wei);

    let deposit_amount_ether : u256 = 100000;
    let deposit_amount_wei: u256 = deposit_amount_ether  * eth_dispatcher.decimals().into();

    eth_dispatcher.transfer(option_bidder_buyer_1(),deposit_amount_wei);
    eth_dispatcher.transfer(option_bidder_buyer_2(),deposit_amount_wei);

    return (vault_dispatcher, eth_dispatcher);
}

//////////////////////////////
/// liquidity/token count tests
/////////////////////////////

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
    let wei_balance_before_deposit:u256 = vault_dispatcher.unallocated_balance_of(liquidity_provider_1());
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let wei_after_before_deposit:u256 = vault_dispatcher.unallocated_balance_of(liquidity_provider_1());
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
    let unallocated_tokens:u256 = vault_dispatcher.get_unallocated_token_count();    
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
    let tokens:u256 = vault_dispatcher.get_unallocated_token_count();    
    assert(tokens == deposit_amount_wei, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity() {
 
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
    assert(success == true, 'should be able to withdraw');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_valid_user() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    set_contract_address(liquidity_provider_2());
    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
    // TODO may be a panic is more appropriate here
    assert(success == false, 'should not be able to withdraw');

}

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


#[test]
#[available_gas(10000000)]
fn test_bid_after_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(option_params.expiry_time );
    vault_dispatcher.end_auction();
    let success = vault_dispatcher.bid(option_amount, option_price);

    assert(success == false, 'no bid after expiry');
}



#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_allocation() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);

    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(option_amount, option_price); 

    vault_dispatcher.end_auction();

    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_amount_wei);
    //should not be able to withdraw because the liquidity has been moves to the allocated/collaterized pool
    assert(success == false, 'should not be able to withdraw'); 
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
    
    let unallocated_token_before_premium = vault_dispatcher.get_unallocated_token_count();
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(option_amount, option_params.reserve_price); 
    vault_dispatcher.settle(option_params.strike_price - 100 ); // means there is no payout.
    vault_dispatcher.end_auction();
    let unallocated_token_after_premium = vault_dispatcher.get_unallocated_token_count();
    assert(unallocated_token_before_premium < unallocated_token_after_premium, 'premium should have paid out');
}

#[test]
#[available_gas(10000000)]
fn test_bid_below_reserve_price() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);

    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    vault_dispatcher.start_auction(option_params);
    // bid below reserve price
    let bid_below_reserve :u256 =  option_params.reserve_price - 1;

    set_contract_address(option_bidder_buyer_1());
    let success = vault_dispatcher.bid(2, bid_below_reserve );
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
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(option_bidder_buyer_1());
    let success = vault_dispatcher.bid(option_amount, option_price);
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(10000000)]
fn test_total_allocated_tokens_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());

    let deposit_amount_wei = 10000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    // start auction will move the tokens from unallocated pool to allocated pool
    let allocated_tokens = vault_dispatcher.get_allocated_token_count();
    assert( allocated_tokens == deposit_amount_wei, 'all tokens should be allocated');
}

#[test]
#[available_gas(10000000)]
fn test_total_allocated_tokens_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei_1 = 1000000 * vault_dispatcher.decimals().into();
    let deposit_amount_wei_2 = 1000000 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei_1);  
    set_contract_address(liquidity_provider_2());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei_2);  

    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params); // auction also moves the tokens

    // start auction will move the tokens from unallocated pool to allocated pool
    let allocated_token_count :u256 = vault_dispatcher.get_allocated_token_count();
    let unallocated_token_count :u256 = vault_dispatcher.get_unallocated_token_count();
    assert( allocated_token_count == deposit_amount_wei_1 + deposit_amount_wei_2, 'all tokens should be allocated');
    assert( unallocated_token_count == 0,'unallocated should be 0');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_allocation_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 1000000 * vault_dispatcher.decimals().into();
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    vault_dispatcher.start_auction(option_params);
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(option_params.total_options_available/2 + 1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(option_params.total_options_available/2, option_params.reserve_price); 
    vault_dispatcher.end_auction();

    let options_created_count = vault_dispatcher.get_options_token_count();
    assert( options_created_count == option_params.total_options_available, 'all tokens should be allocated');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_allocation_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2) + 1;
    let bid_amount_user_2 :u256 =  (option_params.total_options_available/2) ;
    vault_dispatcher.start_auction(option_params);
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_amount_user_1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(bid_amount_user_2, option_params.reserve_price - 10); 
    vault_dispatcher.end_auction();

    let options_created_count = vault_dispatcher.get_options_token_count();
    assert( options_created_count == bid_amount_user_1, 'all tokens should be allocated');
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

    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count_user_1 :u256 =  (option_params.total_options_available) ;
    
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count_user_1, option_params.reserve_price); 
   
    vault_dispatcher.end_auction();

    //premium paid will be converted into unallocated.
    let unallocated_token_count :u256 = vault_dispatcher.get_allocated_token_count();
    let total_premium_to_be_paid:u256 = vault_dispatcher.get_auction_clearing_price() * vault_dispatcher.get_options_token_count();

    let ratio_of_liquidity_provider_1 : u256 = (vault_dispatcher.allocated_balance_of(liquidity_provider_1()) * 100) / unallocated_token_count;
    let ratio_of_liquidity_provider_2 : u256 = (vault_dispatcher.allocated_balance_of(liquidity_provider_2()) * 100) / unallocated_token_count;

    let premium_for_liquidity_provider_1 : u256 = (ratio_of_liquidity_provider_1 * total_premium_to_be_paid) / 100;
    let premium_for_liquidity_provider_2 : u256 = (ratio_of_liquidity_provider_2 * total_premium_to_be_paid) / 100;

    let actual_unallocated_balance_provider_1 : u256 = vault_dispatcher.unallocated_balance_of(liquidity_provider_1());
    let actual_unallocated_balance_provider_2 : u256 = vault_dispatcher.unallocated_balance_of(liquidity_provider_2());

    assert( actual_unallocated_balance_provider_1 == premium_for_liquidity_provider_1, 'premium paid in ratio');
    assert( actual_unallocated_balance_provider_2 == premium_for_liquidity_provider_2, 'premium paid in ratio');

}


#[test]
#[available_gas(10000000)]
fn test_premium_conversion_unallocated_pool_2 () {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    
    let deposit_amount_wei:u256 = 100000;
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    
    set_contract_address(liquidity_provider_2());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  

    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2) + 1;
    let bid_amount_user_2 :u256 =  (option_params.total_options_available/2) ;
    
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_amount_user_1, option_params.reserve_price); 

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(bid_amount_user_2, option_params.reserve_price); 
    
    vault_dispatcher.end_auction();

    //premium paid will be converted into unallocated.
    let unallocated_token_count :u256 = vault_dispatcher.get_unallocated_token_count();
    let expected_unallocated_token:u256 = vault_dispatcher.get_auction_clearing_price() * option_params.total_options_available;
    assert( unallocated_token_count == expected_unallocated_token, 'paid premiums should translate');
}

#[test]
#[available_gas(10000000)]
fn test_paid_premium_withdrawal() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    
    let deposit_amount_wei:u256 = 100000 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);  
    
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_amount_user_1 :u256 =  (option_params.total_options_available/2);
    
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_amount_user_1, option_params.reserve_price); 
    vault_dispatcher.end_auction();

    let expected_unallocated_token:u256 = vault_dispatcher.get_auction_clearing_price() * vault_dispatcher.get_options_token_count();
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
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();
 
    let options_created = vault_dispatcher.get_options_token_count();
    assert(options_created == bid_count, 'options equal successful bids');
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();
 
    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price();
    assert(clearing_price == option_params.reserve_price, 'clear price equal reserve price');
}


#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1 : u256 = option_params.reserve_price;
    let bid_price_user_2 : u256 = option_params.reserve_price + 10;

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, bid_price_user_1 );
    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(bid_count,  bid_price_user_2);

    vault_dispatcher.end_auction();
 
    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count_user_1: u256 = option_params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;

    let bid_price_user_1 : u256 = option_params.reserve_price + 100;
    let bid_price_user_2 : u256 = option_params.reserve_price ;

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count_user_1, bid_price_user_1 );

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(bid_count_user_2,  bid_price_user_2);

    vault_dispatcher.end_auction();
 
    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   


#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());

    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
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
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());

    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price - 100);
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
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = option_params.total_options_available + 10;
    set_contract_address(option_bidder_buyer_1());
    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);

    vault_dispatcher.end_auction();
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
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();
 
    let options_created = vault_dispatcher.get_options_token_count();
    assert(options_created == bid_count, 'options equal successful bids');
}

//////////////////////////////////////
/////////Pay out realted//////////////
//////////////////////////////////////

#[test]
#[available_gas(10000000)]
fn test_option_payout_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    vault_dispatcher.settle(settlement_price);

    let payout_balance = vault_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let payout_balance_expected = vault_dispatcher.option_balance_of(option_bidder_buyer_1()) * (settlement_price - option_params.strike_price);
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price - 10;
    set_block_timestamp(option_params.expiry_time);
    vault_dispatcher.settle(settlement_price);

    let payout_balance = vault_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let payout_balance_expected = 0; // payout is zero because the settlement price is below the strike price
    assert(payout_balance == payout_balance_expected, 'expected payout doesnt match');
}


#[test]
#[available_gas(10000000)]
fn test_option_payout_claim_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    vault_dispatcher.settle(settlement_price);

    let payout_balance : u256= vault_dispatcher.payout_balance_of(option_bidder_buyer_1());
    let balance_before_claim:u256 = eth_dispatcher.balance_of(option_bidder_buyer_1()); 
    vault_dispatcher.claim_payout(option_bidder_buyer_1());
    let balance_after_claim:u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(balance_after_claim == payout_balance + balance_before_claim, 'expected payout doesnt match');
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_allocated_count() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    vault_dispatcher.settle(settlement_price);

    let total_allocated_count_after_settle : u256= vault_dispatcher.get_allocated_token_count();
    assert(total_allocated_count_after_settle == 0, 'allocated should be zero')
}

#[test]
#[available_gas(10000000)]
fn test_option_payout_unallocated_count_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    let total_allocated_count_before_auction : u256= vault_dispatcher.get_unallocated_token_count();

    vault_dispatcher.start_auction(option_params);

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count, option_params.reserve_price);
    vault_dispatcher.end_auction();

    let settlement_price :u256 =  option_params.strike_price + 10;
    set_block_timestamp(option_params.expiry_time);
    vault_dispatcher.settle(settlement_price);

    let premium_paid = (bid_count*  option_params.reserve_price);
    let total_allocated_count_after_settle : u256= vault_dispatcher.get_unallocated_token_count();
    let claim_payout_amount:u256 = vault_dispatcher.payout_balance_of(option_bidder_buyer_1()); 
    vault_dispatcher.claim_payout(option_bidder_buyer_1());
    let total_allocated_count_after_claim : u256= vault_dispatcher.get_allocated_token_count();

    assert(total_allocated_count_after_settle == total_allocated_count_before_auction - claim_payout_amount + premium_paid, 'expec allocated doesnt match');
}
