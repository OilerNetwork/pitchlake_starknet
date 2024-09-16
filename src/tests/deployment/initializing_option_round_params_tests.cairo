use pitch_lake_starknet::tests::utils::facades::option_round_facade::OptionRoundFacadeTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}, contract_address::ContractAddressZeroable
};
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcherTrait,};

use pitch_lake_starknet::{
    library::eth::Eth,
    market_aggregator::interface::{
        IMarketAggregatorMockDispatcher, IMarketAggregatorMockDispatcherTrait
    },
    vault::{contract::Vault, interface::{IVaultDispatcher, IVaultDispatcherTrait},},
    option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait},
    contracts::{
        pitch_lake::{
            IPitchLakeDispatcher, IPitchLakeSafeDispatcher, IPitchLakeDispatcherTrait, PitchLake,
            IPitchLakeSafeDispatcherTrait
        },
    },
    tests::{
        utils::{
            helpers::{
                setup::{
                    decimals, setup_facade, setup_facade_vault_type, deploy_vault, deploy_pitch_lake
                },
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
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeImpl},
                vault_facade::{VaultFacade, VaultFacadeTrait},
                market_aggregator_facade::{MarketAggregatorFacade, MarketAggregatorFacadeTrait}
            },
        },
    },
    types::VaultType, library::utils::{calculate_strike_price}
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
    let volatility = 10000; // 100.33%

    let strike_itm = calculate_strike_price(VaultType::InTheMoney, avg_basefee, volatility);
    let strike_atm = calculate_strike_price(VaultType::AtTheMoney, avg_basefee, volatility);
    let strike_otm = calculate_strike_price(VaultType::OutOfMoney, avg_basefee, volatility);

    assert_eq!(strike_atm, avg_basefee);
    assert_eq!(strike_otm, 2 * avg_basefee);
    // @note Return to this test when 0 strike is discussed
    assert_eq!(strike_itm, avg_basefee);
}

// @note Return to this test when 0 strike is discussed
#[test]
#[available_gas(50000000)]
fn test_calculated_strike_ITM_high_vol() {
    let avg_basefee = to_gwei(100);
    let volatility = 20000; // 200.00%
    let strike_itm = calculate_strike_price(VaultType::InTheMoney, avg_basefee, volatility);

    assert_eq!(strike_itm, avg_basefee);
}


#[test]
#[available_gas(200000000)]
fn test_strike_prices_across_rounds_ATM() {
    let (mut vault, _) = setup_facade_vault_type(VaultType::AtTheMoney);
    let mut round1 = vault.get_current_round();

    let k1 = round1.get_strike_price();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    let s1 = to_gwei(20);
    accelerate_to_settled(ref vault, s1);
// let mut round2 = vault.get_current_round();
// let k2 = round2.get_strike_price();
// accelerate_to_auctioning(ref vault);
// accelerate_to_running(ref vault);
// let s2 = to_gwei(40);
// accelerate_to_settled(ref vault, s2);

// let mut round3 = vault.get_current_round();
// let k3 = round3.get_strike_price();
// println!("k1: {}, k2: {}, k3: {}", k1, k2, k3);

// assert_eq!(k2, s1);
// assert_eq!(k3, s2);
}

#[test]
#[available_gas(200000000)]
fn test_strike_prices_across_rounds_ITM() {
    let (vault, mk_agg) = setup_facade_vault_type(VaultType::InTheMoney);
}


// Test that the strike price is set correctly based on the vault type
#[test]
#[available_gas(50000000)]
#[ignore]
fn test_strike_price_based_on_vault_types() {
    // Deploy pitch lake
    let pitch_lake_dispatcher: IPitchLakeDispatcher = deploy_pitch_lake();
    // Fetch vaults as facades
    let mut vault_dispatcher_at_the_money = VaultFacade {
        vault_dispatcher: pitch_lake_dispatcher.at_the_money_vault()
    };
    let mut vault_dispatcher_in_the_money = VaultFacade {
        vault_dispatcher: pitch_lake_dispatcher.in_the_money_vault()
    };
    let mut vault_dispatcher_out_the_money = VaultFacade {
        vault_dispatcher: pitch_lake_dispatcher.out_the_money_vault()
    };

    // LP deposits into each round 1 because a round cannot start auctioning without liquidity
    let deposit_amount_wei: u256 = 100 * decimals();
    vault_dispatcher_at_the_money.deposit(deposit_amount_wei, liquidity_provider_1());
    vault_dispatcher_in_the_money.deposit(deposit_amount_wei, liquidity_provider_1());
    vault_dispatcher_out_the_money.deposit(deposit_amount_wei, liquidity_provider_1());

    // Get each round 1 dispatcher
    let mut atm = vault_dispatcher_at_the_money.get_current_round();
    let mut itm = vault_dispatcher_in_the_money.get_current_round();
    let mut otm = vault_dispatcher_out_the_money.get_current_round();

    // Check the strike price of each vault's round 1
    let atm_strike_price = atm.get_strike_price();
    let itm_strike_price = itm.get_strike_price();
    let otm_strike_price = otm.get_strike_price();
//let atm_avg_basefee = atm.get_current_average_basefee();
//let itm_avg_basefee = itm.get_current_average_basefee();
//let otm_avg_basefee = otm.get_current_average_basefee();

//assert(atm_strike_price == atm_avg_basefee, 'ATM stike wrong');
//assert(itm_strike_price > itm_avg_basefee, 'ITM stike wrong');
//assert(otm_strike_price < otm_avg_basefee, 'OTM stike wrong');
}
// @note Add tests for other init params. Reserve price, cap levels etc.
// @note Add test that option round params are logical (auction start time < auction end time < option settlement time)


