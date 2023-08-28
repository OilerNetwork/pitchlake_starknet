use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};
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

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;

fn deploy() -> IERC20SafeDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    let (address, _) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IERC20SafeDispatcher { contract_address: address };
}

#[test]
#[available_gas(1000000)]
fn test_name() {
    let safe_dispatcher = deploy();
    let name: felt252 = safe_dispatcher.name().unwrap();
    assert(name == 'ETH', 'invalid name');
}

#[test]
#[available_gas(1000000)]
fn test_symbol() {
    let safe_dispatcher = deploy();
    let symbol: felt252 = safe_dispatcher.symbol().unwrap();
    assert(symbol == 'ETH', 'invalid symbol');
}

#[test]
#[available_gas(1000000)]
fn test_decimals() {
    let safe_dispatcher = deploy();
    let decimals: u8 = safe_dispatcher.decimals().unwrap();
    assert(decimals == 18, 'invalid decimals');
}

#[test]
#[available_gas(1000000)]
fn test_balanceOf() {
    let safe_dispatcher = deploy();
    let account: ContractAddress = ContractAddressZeroable::zero();
    let balance: u256 = safe_dispatcher.balance_of(account).unwrap();
    assert(balance == 0, 'invalid balance');
}

#[test]
#[available_gas(1000000)]
fn test_allowance() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let allowance: u256 = safe_dispatcher.allowance(owner, spender).unwrap();
    assert(allowance == 0, 'invalid allowance');
}

#[test]
#[available_gas(1000000)]
fn test_transfer_zero() {
    let safe_dispatcher = deploy();
    let recipient: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 0;
    let result: bool = safe_dispatcher.transfer(recipient, amount).unwrap();
    assert(result == true, 'transfer failed');
}

#[test]
#[available_gas(1000000)]
fn test_transfer_insufficient_balance() {
    let safe_dispatcher = deploy();
    let recipient: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.transfer(recipient, amount).unwrap();
    assert(result == false, 'transfer should have failed');
}

#[test]
#[available_gas(1000000)]
fn test_transfer_from_zero() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 0;
    let result: bool = safe_dispatcher.transfer_from(owner, spender, amount).unwrap();
    assert(result == true, 'transfer from failed');
}

#[test]
#[available_gas(1000000)]
fn test_transfer_from_insufficient_allowance() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.transfer_from(owner, spender, amount).unwrap();
    assert(result == false, 'should have failed');
}

#[test]
#[available_gas(1000000)]
fn test_transfer_from_insufficient_balance() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.transfer_from(owner, spender, amount).unwrap();
    assert(result == false, 'should have failed');
}

#[test]
#[available_gas(1000000)]
fn test_approve() {
    let safe_dispatcher = deploy();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.approve(spender, amount).unwrap();
    assert(result == true, 'approve failed');
}

#[test]
#[available_gas(1000000)]
fn test_approve_update() {
    let safe_dispatcher = deploy();
    let spender: ContractAddress = ContractAddressZeroable::zero();

    let caller_address = contract_address_const::<1>();
    let caller_account: ContractAddress = caller_address.into();
    starknet::testing::set_contract_address(caller_address);

    let mut allowance_amount = safe_dispatcher.allowance(caller_account, spender).unwrap();
    assert(allowance_amount == 0, 'invalid allowance 0');
    let amount1: u256 = 1;
    let result1: bool = safe_dispatcher.approve(spender, amount1).unwrap();
    assert(result1 == true, 'approve 1 failed');
    allowance_amount = safe_dispatcher.allowance(caller_account, spender).unwrap();
    assert(allowance_amount == 1, 'invalid allowance 1');
    let amount2: u256 = 2;
    let result2: bool = safe_dispatcher.approve(spender, amount2).unwrap();
    assert(result2 == true, 'approve 2 failed');
    allowance_amount = safe_dispatcher.allowance(caller_account, spender).unwrap();
    assert(allowance_amount == 2, 'invalid allowance 2');
}