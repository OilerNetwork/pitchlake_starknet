use array::ArrayTrait;
use result::ResultTrait;
use option::OptionTrait;
use traits::TryInto;
use starknet::ContractAddress;
use starknet::Felt252TryIntoContractAddress;

use pitchlake_starknet::pitchlake::IHelloStarknetSafeDispatcher;
use pitchlake_starknet::pitchlake::IHelloStarknet;
use pitchlake_starknet::pitchlake::HelloStarknet;
use pitchlake_starknet::pitchlake::IHelloStarknetSafeDispatcherTrait;
use starknet::{
    get_contract_address, deploy_syscall, ClassHash, contract_address_const
};

fn deploy() -> IHelloStarknetSafeDispatcher {
    let mut constructor_args: Array<felt252> = ArrayTrait::new();
    let (address, _) = deploy_syscall(
        HelloStarknet::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_args.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IHelloStarknetSafeDispatcher { contract_address: address };
}

#[test]
#[available_gas(3000000)]
fn test_increase_balance() {
    let safe_dispatcher = deploy();

    let balance_before = safe_dispatcher.get_balance().unwrap();
    assert(balance_before == 0, 'Invalid balance');

    safe_dispatcher.increase_balance(42).unwrap();

    let balance_after = safe_dispatcher.get_balance().unwrap();
    assert(balance_after == 42, 'Invalid balance');
}

#[test]
#[available_gas(3000000)]
fn test_cannot_increase_balance_with_zero_value() {
    let safe_dispatcher = deploy();

    let balance_before = safe_dispatcher.get_balance().unwrap();
    assert(balance_before == 0, 'Invalid balance');

    match safe_dispatcher.increase_balance(0) {
        Result::Ok(_) => panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
        }
    };
}
