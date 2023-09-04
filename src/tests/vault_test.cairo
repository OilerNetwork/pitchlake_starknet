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
use pitch_lake_starknet::tests::utils::{allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquiduty_provider_1, liquiduty_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner};


const NAME: felt252 = 'WETH';
const SYMBOL: felt252 = 'WETH';
const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 9999999999999999;

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
    
    eth_dispatcher.transfer(liquiduty_provider_1(),1000000);
    eth_dispatcher.transfer(liquiduty_provider_2(),1000000);

    eth_dispatcher.transfer(option_bidder_buyer_1(),100000);
    eth_dispatcher.transfer(option_bidder_buyer_2(),100000);

    return (vault_dispatcher, eth_dispatcher);
}

//////////////////////////////
/// liquidity/token count tests
/////////////////////////////

#[test]
#[available_gas(10000000)]
fn test_deploy_liquidity() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

}


#[test]
#[available_gas(10000000)]
fn test_eth_has_descreased_after_deposit() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let eth_value_before_transfer: u256 = eth_dispatcher.balance_of(liquiduty_provider_1());
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    let eth_value_after_transfer: u256 = eth_dispatcher.balance_of(liquiduty_provider_1());
    assert(eth_value_after_transfer == eth_value_before_transfer - deposit_value  , 'deposit is not decremented');
}

#[test]
#[available_gas(10000000)]
fn test_eth_has_increased_after_withdrawal() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    let eth_value_before_withdrawal: u256 = eth_dispatcher.balance_of(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_value);
    let eth_value_after_withdrawal: u256 = eth_dispatcher.balance_of(liquiduty_provider_1());
    let unallocated_tokens:u256 = vault_dispatcher.get_unallocated_token_count();    
    assert(eth_value_before_withdrawal == eth_value_after_withdrawal + deposit_value, 'withdrawal is not incremented');
    assert(unallocated_tokens == 0, 'unalloc after withdrawal,0');
}

#[test]
#[available_gas(10000000)]
fn test_unallocated_token_count() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    let tokens:u256 = vault_dispatcher.get_unallocated_token_count();    
    assert(tokens == deposit_value, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity() {
 
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_value);
    assert(success == true, 'should be able to withdraw');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_valid_user() {
    // only valid user should be able to withdraw liquidity
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    set_contract_address(liquiduty_provider_2());
    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_value);
    // TODO may be a panic is more appropriate here
    assert(success == false, 'should not be able to withdraw');

}


#[test]
#[available_gas(10000000)]
fn test_settle_before_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;
    
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);
    
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(unit_amount, unit_price);

    set_contract_address(vault_manager());
    vault_dispatcher.end_auction();

    set_block_timestamp(option_params.expiry_time - 10000);
    let success = vault_dispatcher.settle(option_params.strike_price + 10);
    assert(success == false, 'no settle before expiry');
}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_allocation() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;

    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);

    set_contract_address(vault_manager());
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());

    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(unit_amount, unit_price); // lets assume this bid is successfull

    set_contract_address(vault_manager());
    vault_dispatcher.end_auction();

    let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_value);
    assert(success == false, 'should not be able to withdraw');
}

#[test]
#[available_gas(10000000)]
fn test_withdrawal_after_premium() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;

    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);

    set_contract_address(vault_manager());
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vault_dispatcher.start_auction(option_params);

    let unallocated_token_before_premium = vault_dispatcher.get_unallocated_token_count();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(unit_amount, option_params.reserve_price.into()); // lets assume this bid is successfull
    
    set_contract_address(vault_manager());
    vault_dispatcher.end_auction();

    let unallocated_token_after_premium = vault_dispatcher.get_unallocated_token_count();
    assert(unallocated_token_before_premium < unallocated_token_after_premium, 'premium should have paid out');
}

#[test]
#[available_gas(10000000)]
fn test_bid_below_reserve_price() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);

    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);
    // bid below reserve price
    let bid_below_reserve :u128 =  option_params.reserve_price - 1;

    set_contract_address(option_bidder_buyer_1());
    let success = vault_dispatcher.bid(2, bid_below_reserve.into() );
    assert(success == false, 'should not be able to bid');
}

#[test]
#[available_gas(10000000)]
fn test_bid_before_auction_start() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;

    set_contract_address(liquiduty_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(option_bidder_buyer_1());
    let success = vault_dispatcher.bid(unit_amount, unit_price);
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(10000000)]
fn test_total_allocated_tokens() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquiduty_provider_1());

    let deposit_amount = 1000000;
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount);  
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);

    // start auction will move the tokens from unallocated pool to allocated pool

    let allocated_tokens = vault_dispatcher.get_allocated_token_count();
    assert( allocated_tokens == deposit_amount, 'all tokens should be allocated');
}


#[test]
#[available_gas(10000000)]
fn test_total_options_after_allocation() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquiduty_provider_1());
    let deposit_amount = 1000000;
    let success:bool = vault_dispatcher.deposit_liquidity(deposit_amount);  
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);
    
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(option_params.total_options_available.into()/2 + 1, option_params.reserve_price.into()); // lets assume the reserve price is one

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(option_params.total_options_available.into()/2, option_params.reserve_price.into()); // lets assume the reserve price is one

   
    set_contract_address(vault_manager());
    vault_dispatcher.end_auction();

    let options_created_count = vault_dispatcher.get_options_token_count();
    assert( options_created_count == option_params.total_options_available.into(), 'all tokens should be allocated');
}

#[test]
#[available_gas(10000000)]
fn test_premium_conversion_unallocated_pool() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquiduty_provider_1());
    let success:bool = vault_dispatcher.deposit_liquidity(1000000);  
    let success:bool = vault_dispatcher.withdraw_liquidity(100);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);
    
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(option_params.total_options_available.into()/2 + 1, option_params.reserve_price.into()); // lets assume the reserve price is one

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.bid(option_params.total_options_available.into()/2, option_params.reserve_price.into()); // lets assume the reserve price is one
    
    set_contract_address(vault_manager());
    vault_dispatcher.end_auction();

    //premium paid will be converted into unallocated.

    let unallocated_token :u256= vault_dispatcher.get_unallocated_token_count();
    let expected_unallocated_token:u256 = vault_dispatcher.get_auction_clearing_price().into() * vault_dispatcher.get_options_token_count();
  
    assert( unallocated_token == expected_unallocated_token, 'paid premiums should translate');
}


#[test]
#[available_gas(10000000)]
fn test_option_count() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquiduty_provider_1());
    let success:bool = vault_dispatcher.deposit_liquidity(1000000);
    let option_params: OptionParams = vault_dispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vault_dispatcher.start_auction(option_params);

    let bid_count: u128 = 2;
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.bid(bid_count.into(), option_params.reserve_price.into());

    set_contract_address(vault_manager());
    vault_dispatcher.end_auction();
 
    let options_created = vault_dispatcher.get_options_token_count();
    assert(options_created == bid_count.into(), 'options equal successful bids');
}


// #[test]
// #[available_gas(10000000)]
// fn test_withdraw_liquidity_after_snapshot() {

//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_value:u256 = 50;
//     let success:bool  = vault_dispatcher.deposit_liquidity(deposit_value);
//     assert(success == true, 'cannot deposit');

//     vault_dispatcher.generate_option_params();
//     vault_dispatcher.start_auction();
//     vault_dispatcher.bid(2,50);
//     vault_dispatcher.end_auction();

//     let success:bool  = vault_dispatcher.withdraw_liquidity(deposit_value);
//     assert(success == false, 'should not be able to withdraw');
// }


