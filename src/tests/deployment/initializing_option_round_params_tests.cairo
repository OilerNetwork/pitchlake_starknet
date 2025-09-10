use openzeppelin_token::erc20::interface::ERC20ABIDispatcherTrait;
use pitch_lake::library::pricing_utils::calculate_strike_price;
use pitch_lake::option_round::interface::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake::tests::utils::facades::option_round_facade::{
    OptionRoundFacade, OptionRoundFacadeImpl, OptionRoundFacadeTrait,
};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::accelerators::{
    accelerate_to_auctioning, accelerate_to_running, accelerate_to_settled,
};
use pitch_lake::tests::utils::helpers::event_helpers::{assert_no_events_left, pop_log};
use pitch_lake::tests::utils::helpers::setup::{
    deploy_eth, deploy_vault, setup_facade, setup_facade_custom,
};
use pitch_lake::tests::utils::lib::test_accounts::{
    bystander, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1,
    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
};
use pitch_lake::vault::contract::Vault;
use pitch_lake::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use starknet::syscalls::deploy_syscall;
use starknet::testing::{set_block_timestamp, set_contract_address};
use starknet::{ClassHash, ContractAddress, get_block_timestamp, get_contract_address};


fn to_gwei(amount: u256) -> u256 {
    1000 * 1000 * 1000 * amount
}


#[test]
#[available_gas(50000000)]
fn test_calculated_strike_price() {
    let twap = to_gwei(100);

    let atm_k = 0;
    let itm_k = -333;
    let otm_k = 333;

    let strike_atm = calculate_strike_price(atm_k, twap);
    let strike_itm = calculate_strike_price(itm_k, twap);
    let strike_otm = calculate_strike_price(otm_k, twap);

    assert(strike_atm == twap, 'otm strike wrong');
    assert(strike_itm == to_gwei(9667) / 100, 'itm strike wrong');
    assert(strike_otm == to_gwei(10333) / 100, 'otm strike wrong');
}

#[test]
#[available_gas(50000000)]
fn test_calculated_strike_price_2() {
    let twap = to_gwei(100);

    let atm_k = 0;
    let itm_k = -1039;
    let otm_k = 1039;

    let strike_atm = calculate_strike_price(atm_k, twap);
    let strike_itm = calculate_strike_price(itm_k, twap);
    let strike_otm = calculate_strike_price(otm_k, twap);

    assert(strike_atm == twap, 'otm strike wrong');
    assert(strike_itm == to_gwei(8961) / 100, 'itm strike wrong');
    assert(strike_otm == to_gwei(11039) / 100, 'otm strike wrong');
}

#[test]
#[available_gas(50000000)]
fn test_vault_strike_levels_atm() {
    let k_atm = 0;
    let mut vault_atm = setup_facade_custom(3333, k_atm);

    accelerate_to_auctioning(ref vault_atm);
    accelerate_to_running(ref vault_atm);
    accelerate_to_settled(ref vault_atm, to_gwei(100));

    let mut atm_round = vault_atm.get_current_round();
    let atm_strike = atm_round.get_strike_price();

    assert(atm_strike == to_gwei(100), 'atm strike wrong');
}
#[test]
#[available_gas(50000000)]
fn test_vault_strike_levels_itm() {
    let k_itm = -1_039; // -10.39%
    let mut vault_itm = setup_facade_custom(3333, k_itm);
    let s_price = to_gwei(100);

    accelerate_to_auctioning(ref vault_itm);
    accelerate_to_running(ref vault_itm);
    accelerate_to_settled(ref vault_itm, s_price);

    let mut itm_round = vault_itm.get_current_round();
    let itm_strike = itm_round.get_strike_price();

    assert_eq!(itm_strike, ((10_000 - 1039) * s_price) / 10000);
}

#[test]
#[available_gas(50000000)]
fn test_vault_strike_levels_otm() {
    let k_otm = 10_007; // + 100.07%
    let mut vault_otm = setup_facade_custom(3333, k_otm);
    let s_price = to_gwei(100);

    accelerate_to_auctioning(ref vault_otm);
    accelerate_to_running(ref vault_otm);
    accelerate_to_settled(ref vault_otm, s_price);

    let mut otm_round = vault_otm.get_current_round();
    let otm_strike = otm_round.get_strike_price();

    assert_eq!(otm_strike, (10_000 + 10_007) * s_price / 10000);
}
//#[test]
//#[available_gas(50000000)]
//fn test_calculated_strike_ITM_high_vol() {
//    let avg_basefee = to_gwei(100);
//    let volatility = 20000; // 200.00%
//    let strike_itm = calculate_strike_price(VaultType::InTheMoney, avg_basefee, volatility);
//
//    assert_eq!(strike_itm, avg_basefee / 2);
//}
//
//
//#[test]
//#[available_gas(200000000)]
//fn test_strike_prices_across_rounds_ATM() {
//    let mut vault = setup_facade_vault_type(VaultType::AtTheMoney);
//    for i in 0_u256
//        ..3 {
//            accelerate_to_auctioning(ref vault);
//            accelerate_to_running(ref vault);
//
//            let k_0 = to_gwei(i + 100);
//            accelerate_to_settled(ref vault, k_0);
//            let mut current_round = vault.get_current_round();
//            let k_1 = current_round.get_strike_price();
//
//            assert_eq!(k_0, k_1);
//        };
//}
//
//
//// Test that the strike price is set correctly based on the vault type
//#[test]
//#[available_gas(50000000)]
//#[ignore]
//fn test_strike_price_based_on_vault_types() {
//    // Deploy different vault types
//    let mut vault_atm = setup_facade_vault_type(VaultType::AtTheMoney);
//    let mut _vault_itm = setup_facade_vault_type(VaultType::InTheMoney);
//    let mut _vault_otm = setup_facade_vault_type(VaultType::OutOfMoney);
//
//    // LP deposits into each round 1 because a round cannot start auctioning without liquidity
//    let deposit = to_gwei(1000);
//    vault_atm.deposit(deposit, liquidity_provider_1());
//    _vault_itm.deposit(deposit, liquidity_provider_1());
//    _vault_otm.deposit(deposit, liquidity_provider_1());
//
//    // Start the rounds
//    let settlement_price = to_gwei(100);
//    accelerate_to_settled(ref vault_atm, settlement_price);
//    accelerate_to_settled(ref _vault_itm, settlement_price);
//    accelerate_to_settled(ref _vault_otm, settlement_price);
//
//    // Get each round 1 dispatcher
//    let mut atm_round = vault_atm.get_current_round();
//    let mut _itm_round = _vault_itm.get_current_round();
//    let mut _otm_round = _vault_otm.get_current_round();
//
//    // Check the strike price of each vault's round 1
//    let atm_strike_price = atm_round.get_strike_price();
//    let _itm_strike_price = _itm_round.get_strike_price();
//    let _otm_strike_price = _otm_round.get_strike_price();
//
//    assert(settlement_price == atm_strike_price, 'ATM stike wrong');
//    //assert(itm_strike_price > itm_avg_basefee, 'ITM stike wrong');
////assert(otm_strike_price < otm_avg_basefee, 'OTM stike wrong');
//}
//// @note Add tests for other init params. Reserve price, cap levels etc.
//// @note Add test that option round params are logical (auction start time < auction end time <
//// option settlement time)


