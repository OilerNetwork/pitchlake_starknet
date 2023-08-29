use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::IDepositVaultSafeDispatcher;
use pitch_lake_starknet::vault::Vault;
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

fn deploy() -> (IERC20SafeDispatcher, IDepositVaultSafeDispatcher) {
    let mut calldata = array![];

    calldata.append_serde(NAME);
    calldata.append_serde(SYMBOL);
    calldata.append_serde(SUPPLY);
    calldata.append_serde(OWNER());

    let (address, _) = deploy_syscall(
        Vault::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return (IERC20SafeDispatcher { contract_address: address }, IDepositVaultSafeDispatcher{contract_address: address});
}

#[test]
#[available_gas(1000000)]
fn test_name() {
    let (erc20dispatcher, vaultdispatcher) = deploy();
    let name: felt252 = erc20dispatcher.name().unwrap();
    assert(name == NAME, 'invalid name');
}

