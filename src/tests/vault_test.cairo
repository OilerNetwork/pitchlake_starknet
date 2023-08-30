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

// fn deploy() -> (IERC20SafeDispatcher, IDepositVaultDispatcher) {
//     let mut calldata = array![];

//     calldata.append_serde(ALLOCATED_POOL_ADDRESS());
//     calldata.append_serde(UN_ALLOCATED_POOL_ADDRESS());
//     // calldata.append_serde(SUPPLY);
//     // calldata.append_serde(OWNER());

//     let (address, _) = deploy_syscall(
//         Vault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
//     )
//         .expect('DEPLOY_AD_FAILED');
//     return (IERC20SafeDispatcher { contract_address: address }, IDepositVaultDispatcher{contract_address: address});
// }

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

// #[test]
// #[available_gas(1000000)]
// fn test_name() {
//     let (erc20dispatcher, vaultdispatcher) = deploy();
//     let name: felt252 = erc20dispatcher.name().unwrap();
//     assert(name == NAME, 'invalid name');
// }

#[test]
#[available_gas(1000000)]
fn test_deploy_liquidity() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let deposit_value:u256 = 50;
    let success:bool  = vaultdispatcher.deposit_liquidity(deposit_value);
    assert(success == true, 'cannot deposit');
}

#[test]
#[available_gas(1000000)]
fn test_withdraw_liquidity() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let withdraw_value:u256 = 50;
    let success:bool  = vaultdispatcher.withdraw_liquidity(withdraw_value);
    assert(success == true, 'cannot withdraw');
}

#[test]
#[available_gas(1000000)]
fn test_generate_params() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let success:bool  = vaultdispatcher.generate_params_start_auction();
}

#[test]
#[available_gas(1000000)]
fn test_get_k() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let success:u128  = vaultdispatcher.get_k();
}

#[test]
#[available_gas(1000000)]
fn test_total_tokens_after_allocation() {
    let vaultdispatcher : IDepositVaultDispatcher = deployVault();
    let success:bool = vaultdispatcher.deposit_liquidity(1000000);
    let success:bool = vaultdispatcher.withdraw_liquidity(100);
    let success:bool  = vaultdispatcher.generate_params_start_auction();
    let allocated_tokens = vaultdispatcher.get_allocated_tokens();
    let unallocated_token = vaultdispatcher.get_unallocated_tokens();
    // assert( allocated_tokens == 999900, 'all tokens should be allocated');
    // assert( unallocated_token == 0, 'no unallocation');

}

