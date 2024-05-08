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
// 14. allow liquidity redemption

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

// questions on ETH liq
// how to accept and store information on incoming ETH transfer
// need to read info on value transferred (ETH)
// ETH contract transfer
// will need approval for transfer in ERC20
// approve and transfer?
// storage access
// let us lock some ETH soon
// will need to interact with another contract here? (ETH ERC20)
// a) allow only if liq deployments are being accepted
// b) record current liq deployment round, address and total liquidity
// bb) allow top ups
// c) when redeeming, need to define the round to redeem?
// cc) remodel later, no need to be smart here
// events: liq deployed addr round amount
// events: liq redeemed addr round amount (base, reward)

use array::ArrayTrait;
use option::OptionTrait;
use pitch_lake_starknet::pitch_lake::{
    IPitchLake, IPitchLakeDispatcher, IPitchLakeDispatcherTrait, IPitchLakeSafeDispatcher,
    IPitchLakeSafeDispatcherTrait, PitchLake,
};

use pitch_lake_starknet::vault::{
    IVault, IVaultDispatcher, IVaultDispatcherTrait, IVaultSafeDispatcher,
    IVaultSafeDispatcherTrait, Vault, VaultType
};
use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address,
};
use traits::TryInto;
use openzeppelin::utils::serde::SerializedAppend;
use starknet::contract_address::ContractAddressZeroable;


fn deploy() -> IPitchLakeDispatcher {
    let mut calldata = array![];

    calldata.append_serde(ContractAddressZeroable::zero());

    calldata.append_serde(ContractAddressZeroable::zero()); // vaults address, update later
    calldata.append_serde(ContractAddressZeroable::zero());
    calldata.append_serde(ContractAddressZeroable::zero());
    let (address, _) = deploy_syscall(
        PitchLake::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), true
    )
        .expect('DEPLOY_AD_FAILED');
    return IPitchLakeDispatcher { contract_address: address };
}

// @note move to vault/vault_tests
#[test]
#[available_gas(10000000)]
fn test_vault_type() {
    let pitch_lake_dispatcher: IPitchLakeDispatcher = deploy();
    let in_the_money_vault: IVaultDispatcher = pitch_lake_dispatcher.in_the_money_vault();
    let out_the_money_vault: IVaultDispatcher = pitch_lake_dispatcher.out_the_money_vault();
    let at_the_money_vault: IVaultDispatcher = pitch_lake_dispatcher.at_the_money_vault();

    assert(in_the_money_vault.vault_type() == VaultType::InTheMoney, 'ITM vault wrong');
    assert(out_the_money_vault.vault_type() == VaultType::OutOfMoney, 'OTM vault wrong');
    assert(at_the_money_vault.vault_type() == VaultType::AtTheMoney, 'ATM vault wrong');
}
