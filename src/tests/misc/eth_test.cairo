use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address,
};
use debug::PrintTrait;

use pitch_lake_starknet::eth::Eth;
const NAME: felt252 = 111;
const SYMBOL: felt252 = 222;
const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 2000;
const VALUE: u256 = 300;


fn OWNER() -> ContractAddress {
    contract_address_const::<10>()
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

fn deploy() -> ERC20SafeDispatcher {
    let mut calldata = array![];

    calldata.append_serde(NAME);
    calldata.append_serde(SYMBOL);
    calldata.append_serde(SUPPLY);
    calldata.append_serde(OWNER());

    let (address, _) = deploy_syscall(
        Eth::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return ERC20ABIDispatcher { contract_address: address };
}

#[test]
#[available_gas(50000000)]
fn test_name() {
    let safe_dispatcher = deploy();
    let name: felt252 = safe_dispatcher.name().unwrap();
    assert(name == NAME, 'invalid name');
}

#[test]
#[available_gas(50000000)]
fn test_symbol() {
    let safe_dispatcher = deploy();
    let symbol: felt252 = safe_dispatcher.symbol().unwrap();
    assert(symbol == SYMBOL, 'invalid symbol');
}

#[test]
#[available_gas(50000000)]
fn test_decimals() {
    let safe_dispatcher = deploy();
    let decimals: u8 = safe_dispatcher.decimals().unwrap();
    assert(decimals == 18, 'invalid decimals');
}

#[test]
#[available_gas(50000000)]
fn test_balanceOf() {
    let safe_dispatcher = deploy();
    let account: ContractAddress = ContractAddressZeroable::zero();
    let balance: u256 = safe_dispatcher.balance_of(account).unwrap();
    assert(balance == 0, 'invalid balance');
}

#[test]
#[available_gas(50000000)]
fn test_allowance() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let allowance: u256 = safe_dispatcher.allowance(owner, spender).unwrap();
    assert(allowance == 0, 'invalid allowance');
}

#[test]
#[available_gas(50000000)]
fn test_transfer_zero() {
    let safe_dispatcher = deploy();
    let recipient: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 0;
    let result: bool = safe_dispatcher.transfer(RECIPIENT(), amount).unwrap();
    assert(result == true, 'transfer failed');
}

#[test]
#[available_gas(50000000)]
fn test_transfer_insufficient_balance() {
    let safe_dispatcher = deploy();
    let recipient: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: starknet::SyscallResult<bool> = safe_dispatcher.transfer(recipient, amount);
    //  result.unwrap()
    let result: bool = result.unwrap();
}

#[test]
#[available_gas(50000000)]
fn test_transfer_from_zero() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 0;
    let result: bool = safe_dispatcher.transfer_from(owner, spender, amount).unwrap();
    assert(result == true, 'transfer from failed');
}

#[test]
#[available_gas(50000000)]
fn test_transfer_from_insufficient_allowance() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.transfer_from(owner, spender, amount).unwrap();
    assert(result == false, 'should have failed');
}

#[test]
#[available_gas(50000000)]
fn test_transfer_from_insufficient_balance() {
    let safe_dispatcher = deploy();
    let owner: ContractAddress = ContractAddressZeroable::zero();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.transfer_from(owner, spender, amount).unwrap();
    assert(result == false, 'should have failed');
}

#[test]
#[available_gas(50000000)]
fn test_approve() {
    let safe_dispatcher = deploy();
    let spender: ContractAddress = ContractAddressZeroable::zero();
    let amount: u256 = 1;
    let result: bool = safe_dispatcher.approve(spender, amount).unwrap();
    assert(result == true, 'approve failed');
}

#[test]
#[available_gas(50000000)]
fn test_approve_update() {
    let safe_dispatcher = deploy();
    let spender: ContractAddress = ContractAddressZeroable::zero();

    let caller_address = contract_address_const::<1>();
    let caller_account: ContractAddress = caller_address;
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
