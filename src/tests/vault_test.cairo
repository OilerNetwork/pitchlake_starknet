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

    let ethDispatcher : IERC20Dispatcher = deployEth();
    let vaultdispatcher : IVaultDispatcher = deployVault();
    set_contract_address(weth_owner());
    
    ethDispatcher.transfer(liquiduty_provider_1(),1000000);
    ethDispatcher.transfer(liquiduty_provider_2(),1000000);

    ethDispatcher.transfer(option_bidder_buyer_1(),100000);
    ethDispatcher.transfer(option_bidder_buyer_2(),100000);

    return (vaultdispatcher, ethDispatcher);
}

#[test]
#[available_gas(10000000)]
fn test_deploy_liquidity() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

}


#[test]
#[available_gas(10000000)]
fn test_eth_has_descreased_after_deposit() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let eth_value_before_transfer: u256 = ethDispatcher.balance_of(liquiduty_provider_1());
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    let eth_value_after_transfer: u256 = ethDispatcher.balance_of(liquiduty_provider_1());
    assert(eth_value_after_transfer == eth_value_before_transfer - deposit_value  , 'deposit is not decremented');
}


#[test]
#[available_gas(10000000)]
fn test_unallocated_token_count() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    let tokens:u256 = vaultdispatcher.get_unallocated_token_count();    
    assert(tokens == deposit_value, 'should equal to deposited');

}

#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity() {
 
    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    let success:bool  = vaultdispatcher.withdraw_liquidity(deposit_value);
    assert(success == true, 'should be able to withdraw');

}

#[test]
#[available_gas(10000000)]
fn test_settle_before_expiry() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;
    
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vaultdispatcher.start_auction(option_params);
    
    set_contract_address(option_bidder_buyer_1());
    vaultdispatcher.bid(unit_amount, unit_price);

    set_contract_address(vault_manager());
    vaultdispatcher.end_auction();

    set_block_timestamp(option_params.expiry_time - 10000);
    let success = vaultdispatcher.settle();
    assert(success == false, 'no settle before expiry');
}


#[test]
#[available_gas(10000000)]
fn test_withdraw_liquidity_after_snapshot() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;

    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);

    set_contract_address(vault_manager());
    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());

    set_contract_address(vault_manager());
    vaultdispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    vaultdispatcher.bid(unit_amount, unit_price); // lets assume this bid is successfull

    set_contract_address(vault_manager());
    vaultdispatcher.end_auction();

    let success:bool  = vaultdispatcher.withdraw_liquidity(deposit_value);
    assert(success == false, 'should not be able to withdraw');
}

#[test]
#[available_gas(10000000)]
fn test_withdrawal_after_premium() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;

    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);

    set_contract_address(vault_manager());
    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    vaultdispatcher.start_auction(option_params);

    let unallocated_token_before_premium = vaultdispatcher.get_unallocated_token_count();

    set_contract_address(option_bidder_buyer_1());
    vaultdispatcher.bid(unit_amount, unit_price); // lets assume this bid is successfull
    
    set_contract_address(vault_manager());
    vaultdispatcher.end_auction();

    let unallocated_token_after_premium = vaultdispatcher.get_unallocated_token_count();
    assert(unallocated_token_before_premium < unallocated_token_after_premium, 'premium should have paid out');
}

#[test]
#[available_gas(10000000)]
fn test_bid_below_reserve_price() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);

    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    set_contract_address(vault_manager());
    vaultdispatcher.start_auction(option_params);
    // bid below reserve price
    let bid_below_reserve :u128 =  option_params.reserve_price - 1;

    set_contract_address(option_bidder_buyer_1());
    let success = vaultdispatcher.bid(2, bid_below_reserve.into() );
    assert(success == false, 'should not be able to bid');
}

#[test]
#[available_gas(10000000)]
fn test_bid_before_auction_start() {

    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_value:u256 = 50;
    let unit_amount = 50;
    let unit_price = 2;

    set_contract_address(liquiduty_provider_1());
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(option_bidder_buyer_1());
    let success = vaultdispatcher.bid(unit_amount, unit_price);
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(10000000)]
fn test_total_tokens_after_allocation() {
    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquiduty_provider_1());
    let success:bool = vaultdispatcher.deposit_liquidity(1000000);
    let success:bool = vaultdispatcher.withdraw_liquidity(100);
    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vaultdispatcher.start_auction(option_params);
    
    set_contract_address(option_bidder_buyer_1());
    vaultdispatcher.bid(999900,1); // lets assume the reserve price is one
    
    set_contract_address(vault_manager());
    vaultdispatcher.end_auction();

    let allocated_tokens = vaultdispatcher.get_allocated_token_count();
    let unallocated_token = vaultdispatcher.get_unallocated_token_count();
  
    assert( allocated_tokens == 999900, 'all tokens should be allocated');
    assert( unallocated_token == 0, 'no unallocation');
}

#[test]
#[available_gas(10000000)]
fn test_option_count() {
    let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquiduty_provider_1());
    let success:bool = vaultdispatcher.deposit_liquidity(1000000);
    let option_params: OptionParams = vaultdispatcher.generate_option_params(timestamp_start_month(), timestamp_end_month());
    
    set_contract_address(vault_manager());
    vaultdispatcher.start_auction(option_params);

    set_contract_address(option_bidder_buyer_1());
    vaultdispatcher.bid(10,20);

    set_contract_address(vault_manager());
    vaultdispatcher.end_auction();

    let allocated_tokens = vaultdispatcher.get_allocated_token_count();
    let unallocated_token = vaultdispatcher.get_unallocated_token_count();
  
    assert( allocated_tokens == 999900, 'all tokens should be allocated');
    assert( unallocated_token == 0, 'no unallocation');
}


// #[test]
// #[available_gas(10000000)]
// fn test_withdraw_liquidity_after_snapshot() {

//     let (vaultdispatcher, ethDispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_value:u256 = 50;
//     let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
//     assert(success == true, 'cannot deposit');

//     vaultdispatcher.generate_option_params();
//     vaultdispatcher.start_auction();
//     vaultdispatcher.bid(2,50);
//     vaultdispatcher.end_auction();

//     let success:bool  = vaultdispatcher.withdraw_liquidity(deposit_value);
//     assert(success == false, 'should not be able to withdraw');
// }


