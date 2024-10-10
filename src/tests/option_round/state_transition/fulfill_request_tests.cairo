use starknet::{
    get_block_timestamp, ContractAddress, contract_address_const,
    testing::{set_contract_address, set_block_timestamp}
};
use pitch_lake::{
    vault::contract::Vault, vault::contract::Vault::Errors as vErrors,
    option_round::contract::OptionRound::Errors,
    vault::interface::{L1Data, L1DataRequest, L1Result, VaultType},
    option_round::interface::PricingData, library::pricing_utils,
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    accelerate_to_settled, clear_event_logs, timeskip_past_option_expiry_date,
                },
                setup::{get_fossil_address, setup_facade, deploy_vault, deploy_eth},
                general_helpers::{to_gwei}, event_helpers::{assert_event_pricing_data_set},
            },
            lib::{
                test_accounts::{
                    liquidity_provider_1, option_bidder_buyer_1, option_bidder_buyer_2,
                    option_bidder_buyer_3, option_bidder_buyer_4, option_bidders_get,
                },
                variables::{decimals},
            },
            facades::{
                vault_facade::{VaultFacade, VaultFacadeTrait},
                option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait},
            },
        },
    }
};

const err: felt252 = vErrors::CallerNotWhitelisted;

#[test]
#[available_gas(1_000_000_000)]
fn test_only_fossil_can_fulfill_request() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, to_gwei(10));

    let fossil = get_fossil_address();

    set_contract_address(fossil);
    let request = vault.get_request_to_start_auction();
    let result = L1Result {
        proof: array![].span(),
        data: L1Data { twap: to_gwei(666), volatility: 1234, reserve_price: to_gwei(123) }
    };
    vault.fulfill_request(request, result);
    set_contract_address(contract_address_const::<'not fossil'>());
    vault.fulfill_request_expect_error(request, result, err);
}

#[test]
#[available_gas(1_000_000_000)]
fn test_request_must_fulfill_to_start_auction() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, to_gwei(10));

    vault.start_auction_expect_error(Errors::PricingDataNotSet);
}
// timeskip_past_option_expiry_data

#[test]
#[available_gas(1_000_000_000)]
fn test_request_must_fulfill_to_settle_round() {
    let (mut vault, _) = setup_facade();

    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    timeskip_past_option_expiry_date(ref vault);

    vault.settle_option_round_expect_error(Errors::PricingDataNotSet);
}

#[test]
#[available_gas(1_000_000_000)]
fn test_set_pricing_data_events() {
    let (mut vault, _) = setup_facade();

    for _ in 0
        ..3_usize {
            accelerate_to_auctioning(ref vault);
            accelerate_to_running(ref vault);
            accelerate_to_settled(ref vault, to_gwei(10));

            let mut current_round = vault.get_current_round();
            clear_event_logs(array![current_round.contract_address()]);
            let request = vault.get_request_to_start_auction();
            let twap = to_gwei(10);
            let volatility = 3333;
            let reserve_price = to_gwei(3);
            let response = L1Result {
                proof: array![].span(), data: L1Data { twap, volatility, reserve_price }
            };
            set_contract_address(get_fossil_address());
            vault.fulfill_request(request, response);

            assert_event_pricing_data_set(
                current_round.contract_address(), twap, volatility, reserve_price
            );
        }
}

#[test]
#[available_gas(1_000_000_000)]
fn test_fulfilling_multiple_request() {
    let (mut vault, _) = setup_facade();

    for _ in 0
        ..3_usize {
            accelerate_to_auctioning(ref vault);
            accelerate_to_running(ref vault);
            accelerate_to_settled(ref vault, to_gwei(10));

            // Refresh data
            let exp_twap0 = to_gwei(666);
            let exp_volatility0 = 1234;
            let exp_reserve_price0 = to_gwei(123);
            let exp_cap_level0 = pricing_utils::calculate_cap_level(0, exp_volatility0);
            let exp_strike_price0 = pricing_utils::calculate_strike_price(
                VaultType::AtTheMoney, exp_twap0, exp_cap_level0
            );

            let request = vault.get_request_to_start_auction();
            let response = L1Result {
                proof: array![].span(),
                data: L1Data {
                    twap: exp_twap0, volatility: exp_volatility0, reserve_price: exp_reserve_price0
                }
            };
            set_contract_address(get_fossil_address());
            vault.fulfill_request(request, response);

            let mut current_round = vault.get_current_round();
            let strike_price0 = current_round.get_strike_price();
            let cap_level0 = current_round.get_cap_level();
            let reserve_price0 = current_round.get_reserve_price();

            // Check pricing data updates as expected
            assert_eq!(cap_level0, exp_cap_level0);
            assert_eq!(reserve_price0, exp_reserve_price0);
            assert_eq!(strike_price0, exp_strike_price0);

            // Refresh data again
            let exp_twap1 = to_gwei(777);
            let exp_volatility1 = 6789;
            let exp_reserve_price1 = to_gwei(333);
            let exp_cap_level1 = pricing_utils::calculate_cap_level(123, exp_volatility1);
            let exp_strike_price1 = pricing_utils::calculate_strike_price(
                VaultType::AtTheMoney, exp_twap1, exp_cap_level1
            );

            let request = vault.get_request_to_start_auction();
            let response = L1Result {
                proof: array![].span(),
                data: L1Data {
                    twap: exp_twap1, volatility: exp_volatility1, reserve_price: exp_reserve_price1
                }
            };
            set_contract_address(get_fossil_address());
            vault.fulfill_request(request, response);

            let strike_price1 = current_round.get_strike_price();
            let cap_level1 = current_round.get_cap_level();
            let reserve_price1 = current_round.get_reserve_price();

            // Check pricing data updates as expected
            assert_eq!(cap_level1, exp_cap_level1);
            assert_eq!(reserve_price1, exp_reserve_price1);
            assert_eq!(strike_price1, exp_strike_price1);
        }
}
// @note todo add test for request timestamp out of bounds (high and low for both fulfillment types
// (auction start/round settle))
// @note todo add test for setting default values then starting auction/settling round


