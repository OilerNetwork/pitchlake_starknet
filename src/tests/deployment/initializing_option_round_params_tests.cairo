use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}, contract_address::ContractAddressZeroable
};
use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;

use pitch_lake::{
    library::eth::Eth, types::Consts::BPS,
    fact_registry::interface::{IFactRegistryDispatcher, IFactRegistryDispatcherTrait},
    vault::{contract::Vault, interface::{VaultType, IVaultDispatcher, IVaultDispatcherTrait},},
    option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    tests::{
        utils::{
            helpers::{
                setup::{deploy_eth, decimals, setup_facade, setup_facade_vault_type, deploy_vault,},
                event_helpers::{pop_log, assert_no_events_left},
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled
                }
            },
            lib::test_accounts::{
                liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
                option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4, bystander,
            },
            facades::{
                option_round_facade::{
                    OptionRoundFacade, OptionRoundFacadeTrait, OptionRoundFacadeImpl
                },
                vault_facade::{VaultFacade, VaultFacadeTrait},
                fact_registry_facade::{FactRegistryFacade, FactRegistryFacadeTrait}
            },
        },
    },
    library::pricing_utils::calculate_strike_price
};
use debug::PrintTrait;


fn to_gwei(amount: u256) -> u256 {
    1000 * 1000 * 1000 * amount
}


#[test]
#[available_gas(50000000)]
fn test_calculated_strike_price() {
    let avg_basefee = to_gwei(100);
    let volatility = 333; // 3.33%

    let strike_itm = calculate_strike_price(VaultType::InTheMoney, avg_basefee, volatility);
    let strike_atm = calculate_strike_price(VaultType::AtTheMoney, avg_basefee, volatility);
    let strike_otm = calculate_strike_price(VaultType::OutOfMoney, avg_basefee, volatility);

    let adjusted_avg_basefee: u256 = (volatility.into() * avg_basefee.into()) / 10000;

    assert_eq!(strike_atm, avg_basefee);
    assert_eq!(strike_itm, avg_basefee - adjusted_avg_basefee);
    assert_eq!(strike_otm, avg_basefee + adjusted_avg_basefee);
}


#[test]
#[available_gas(50000000)]
fn test_calculated_strike_price_2() {
    let avg_basefee = to_gwei(100);
    let volatility = 10033; // 100.33%

    let strike_itm = calculate_strike_price(VaultType::InTheMoney, avg_basefee, volatility);
    let strike_atm = calculate_strike_price(VaultType::AtTheMoney, avg_basefee, volatility);
    let strike_otm = calculate_strike_price(VaultType::OutOfMoney, avg_basefee, volatility);

    assert_eq!(strike_atm, avg_basefee);
    assert_eq!(strike_itm, avg_basefee / 2);
    assert_eq!(strike_otm, (BPS.into() + volatility.into()) * avg_basefee / BPS.into());
    // @note Return to this test when 0 strike is discussed
}

// @note Return to this test when 0 strike is discussed
#[test]
#[available_gas(50000000)]
fn test_calculated_strike_ITM_high_vol() {
    let avg_basefee = to_gwei(100);
    let volatility = 20000; // 200.00%
    let strike_itm = calculate_strike_price(VaultType::InTheMoney, avg_basefee, volatility);

    assert_eq!(strike_itm, avg_basefee / 2);
}


#[test]
#[available_gas(200000000)]
fn test_strike_prices_across_rounds_ATM() {
    let (mut vault, _) = setup_facade_vault_type(VaultType::AtTheMoney);
    for i in 0_u256
        ..3 {
            accelerate_to_auctioning(ref vault);
            accelerate_to_running(ref vault);

            let k_0 = to_gwei(i + 100);
            accelerate_to_settled(ref vault, k_0);
            let mut current_round = vault.get_current_round();
            let k_1 = current_round.get_strike_price();

            assert_eq!(k_0, k_1);
        };
}


// Test that the strike price is set correctly based on the vault type
#[test]
#[available_gas(50000000)]
#[ignore]
fn test_strike_price_based_on_vault_types() {
    // Deploy different vault types
    let (mut vault_atm, _) = setup_facade_vault_type(VaultType::AtTheMoney);
    let (mut _vault_itm, _) = setup_facade_vault_type(VaultType::InTheMoney);
    let (mut _vault_otm, _) = setup_facade_vault_type(VaultType::OutOfMoney);

    // LP deposits into each round 1 because a round cannot start auctioning without liquidity
    let deposit = to_gwei(1000);
    vault_atm.deposit(deposit, liquidity_provider_1());
    _vault_itm.deposit(deposit, liquidity_provider_1());
    _vault_otm.deposit(deposit, liquidity_provider_1());

    // Start the rounds
    let settlement_price = to_gwei(100);
    accelerate_to_settled(ref vault_atm, settlement_price);
    accelerate_to_settled(ref _vault_itm, settlement_price);
    accelerate_to_settled(ref _vault_otm, settlement_price);

    // Get each round 1 dispatcher
    let mut atm_round = vault_atm.get_current_round();
    let mut _itm_round = _vault_itm.get_current_round();
    let mut _otm_round = _vault_otm.get_current_round();

    // Check the strike price of each vault's round 1
    let atm_strike_price = atm_round.get_strike_price();
    let _itm_strike_price = _itm_round.get_strike_price();
    let _otm_strike_price = _otm_round.get_strike_price();

    assert(settlement_price == atm_strike_price, 'ATM stike wrong');
    //assert(itm_strike_price > itm_avg_basefee, 'ITM stike wrong');
//assert(otm_strike_price < otm_avg_basefee, 'OTM stike wrong');
}
// @note Add tests for other init params. Reserve price, cap levels etc.
// @note Add test that option round params are logical (auction start time < auction end time <
// option settlement time)


