use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IDepositVaultDispatcher, IDepositVaultSafeDispatcher, IDepositVaultDispatcherTrait, Vault, IDepositVaultSafeDispatcherTrait};
use result::ResultTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,

};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;


const NAME: felt252 = 'VAULT';
const SYMBOL: felt252 = 'VLT';
const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 2000;
const VALUE: u256 = 300;


fn ALLOCATED_POOL_ADDRESS() -> ContractAddress {
    contract_address_const::<10>()
}

fn UN_ALLOCATED_POOL_ADDRESS() -> ContractAddress {
    contract_address_const::<100>()
}

fn OWNER() -> ContractAddress {
    contract_address_const::<1000>()
}

fn SPENDER() -> ContractAddress {
    contract_address_const::<20>()
}

fn RECIPIENT() -> ContractAddress {
    contract_address_const::<30>()
}

fn OPERATOR() -> ContractAddress {
    contract_address_const::<40>()
}

fn deployVault() ->  IDepositVaultDispatcher {
    let mut calldata = array![];

    calldata.append_serde(ALLOCATED_POOL_ADDRESS());
    calldata.append_serde(UN_ALLOCATED_POOL_ADDRESS());

    let (address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IDepositVaultDispatcher{contract_address: address};
}

#[test]
#[available_gas(1000000)]
fn test_deploy_liquidity() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');
    let tokens:u256 = vaultdispatcher.get_unallocated_tokens();    
    assert(tokens == deposit_value, 'should equal to deposited');
}

#[test]
#[available_gas(1000000)]
fn test_withdraw_liquidity() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');
    let success:bool  = vaultdispatcher.withdraw_liquidity(deposit_value);
    assert(success == true, 'should be able to withdraw');
}


#[test]
#[available_gas(1000000)]
fn test_settle_before_expiry() {

    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

    let optns = vaultdispatcher.generate_option_params();
    vaultdispatcher.start_auction();
    vaultdispatcher.bid(2,50);
    vaultdispatcher.end_auction();

    let success = vaultdispatcher.settle();
    assert(success == false, 'no settle before expiry');
}


#[test]
#[available_gas(1000000)]
fn test_withdraw_liquidity_after_snapshot() {

    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

    vaultdispatcher.generate_option_params();
    vaultdispatcher.start_auction();
    vaultdispatcher.bid(2,50);
    vaultdispatcher.end_auction();

    let success:bool  = vaultdispatcher.withdraw_liquidity(deposit_value);
    assert(success == false, 'should not be able to withdraw');
}


#[test]
#[available_gas(1000000)]
fn test_bid_below_reserve_price() {

    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

    let optns = vaultdispatcher.generate_option_params();
    vaultdispatcher.start_auction();
    // bid below reserve price
    let bid_below_reserve :u128 =  optns.reserve_price - 1;
    let success = vaultdispatcher.bid(2, bid_below_reserve.into() );
    assert(success == false, 'should not be able to bid');
}

#[test]
#[available_gas(1000000)]
fn test_settle_before_expiry() {

    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

    vaultdispatcher.generate_option_params();
    let success = vaultdispatcher.bid(2,50);
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(1000000)]
fn test_bid_without_start_auction() {

    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');

    vaultdispatcher.generate_option_params();
    let success = vaultdispatcher.bid(2,50);
    assert(success == false, 'should not be able to bid');
}

#[test]
#[available_gas(1000000)]
fn test_start_auction() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let success:bool  = vaultdispatcher.start_auction();
    assert(success == false, 'no liquidity, cannot start');
}

#[test]
#[available_gas(1000000)]
fn test_total_tokens_after_allocation() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();

    let success:bool = vaultdispatcher.deposit_liquidity(1000000);
    let success:bool = vaultdispatcher.withdraw_liquidity(100);

    let success:bool  = vaultdispatcher.start_auction();
    let allocated_tokens = vaultdispatcher.get_allocated_tokens();
    let unallocated_token = vaultdispatcher.get_unallocated_tokens();
  
    assert( allocated_tokens == 999900, 'all tokens should be allocated');
    assert( unallocated_token == 0, 'no unallocation');
}

// #[test]
// #[available_gas(1000000)]
// fn test_withdraw_liquidity_after_snapshot() {

//     let vaultdispatcher : IDepositVaultDispatcher = deployVault();
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


