use array::ArrayTrait;
use option::OptionTrait;
use pitchlake_starknet::pitchlake::{
    IHelloStarknet,
    IHelloStarknetSafeDispatcher,
    IHelloStarknetSafeDispatcherTrait,
    HelloStarknet,
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
use traits::TryInto;

// TODO:
// underlying
// setting expiry
// setting strike price
// collateralization
// settlement
// premium
// batch auction
// historical volatility
// liquidity provision
// option minting
// liquidity roll-over
// reserve price (this will be difficult?)
// liquidity cap
// fossil

// test 3 participants, 9 blocks?
// 0. collect liquidity
// 1. calculate volatility
// 2. get average basefee last month
// 3. calculate strike price for the next month
// 4. calculate premium for the reserve price
// 5. calculate collateral requirements 
// 6. calculate cap
// 7. run batch auction
// 8. resolve batch auction
// 9. distribute options
// 10. calculate settlement price
// 11. calculate remaining liquidity
// 12. roll forward liquidity
// 13. allow for claims
// 14. allow liuqidity redemption

// product
// define schedule for roll forwards / liquidity redemptions / liquidity collection
// define Fossil usage
// define Fossil payments

// silly simple things (1)
// deploy ETH liquidity
//  * soooo
//  * you need to remember the round at which you deployed liquidity
//  * for each round a unit premium should be stored
//  * so I can eploy 1 unit over three rounds where
//  * it may be +0.01 +0.02 -0.1
//   * so -1.00 is all liq deployed and full payout? (no premium?)
//   * -0.0x is partial liquidity deployed or partial payout?
//   * -0.xy is sth like full payout, full liq but premium there
// redeem ETH liquidity

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
