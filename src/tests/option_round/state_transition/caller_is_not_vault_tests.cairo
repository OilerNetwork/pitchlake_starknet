use starknet::{
    get_block_timestamp, ContractAddress, contract_address_const,
    testing::{set_contract_address, set_block_timestamp}
};
use pitch_lake::{
    vault::contract::Vault, option_round::contract::OptionRound::Errors,
    vault::interface::{FossilDataPoints, PricingDataPoints, VaultType},
    fact_registry::interface::{JobRequest, JobRequestParams, JobRange}, library::pricing_utils,
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    accelerate_to_settled
                },
                setup::{setup_facade, deploy_vault, deploy_eth, deploy_fact_registry},
                general_helpers::{to_gwei},
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
                fact_registry_facade::{FactRegistryFacade, FactRegistryFacadeTrait},
            },
        },
    }
};

const salt: u64 = 0x123;
const err: felt252 = Errors::CallerIsNotVault;

fn create_job_request(to: u64) -> JobRequest {
    let JobRange { twap_range, volatility_range, reserve_price_range } = Vault::EXPECTED_JOB_RANGE;

    JobRequest {
        identifiers: array![selector!("PITCH_LAKE_V1")].span(),
        params: JobRequestParams {
            twap: (to - twap_range, to),
            volatility: (to - volatility_range, to),
            reserve_price: (to - reserve_price_range, to),
        }
    }
}

fn not_vault() -> ContractAddress {
    contract_address_const::<'not vault'>()
}

// Test that only the vault can start an auction
#[test]
#[available_gas(50000000)]
fn test_only_vault_can_start_auction() {
    let (mut vault, _) = setup_facade();
    let mut round_to_start = vault.get_current_round();
    vault.deposit(100 * decimals(), liquidity_provider_1());

    set_contract_address(not_vault());
    round_to_start.start_auction_expect_error(1, err)
}

// @note Modify to check the Result of the function to be Result::Err(e)
// Test that only the vault can end an auction
#[test]
#[available_gas(50000000)]
fn test_only_vault_can_end_auction() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    current_round.place_bid(100, current_round.get_reserve_price(), option_bidder_buyer_1());
    set_block_timestamp(current_round.get_auction_end_date());

    set_contract_address(not_vault());
    current_round.end_auction_expect_error(err);
}

// Test that only the vault can settle an option round
#[test]
#[available_gas(50000000)]
fn test_only_vault_can_settle_option_round() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    accelerate_to_running(ref vault);
    set_block_timestamp(current_round.get_option_settlement_date());

    set_contract_address(not_vault());
    current_round.settle_option_round_expect_error(0x123, err);
}

fn get_random_pricing_data_points() -> PricingDataPoints {
    PricingDataPoints {
        twap: to_gwei(123),
        strike_price: to_gwei(5829),
        reserve_price: to_gwei(482745),
        cap_level: 20084,
        volatility: 12345,
    }
}

#[test]
#[available_gas(50000000)]
fn test_only_vault_can_update_round_params() {
    let (mut vault, _) = setup_facade();
    let mut round = vault.get_current_round();
    let data = get_random_pricing_data_points();

    set_contract_address(not_vault());
    round.update_round_params_expect_error(data, err);
}

#[test]
#[available_gas(50000000)]
fn test_update_round_params_on_round() {
    let (mut vault, _) = setup_facade();
    let mut round = vault.get_current_round();

    let reserve_price0 = round.get_reserve_price();
    let cap_level0 = round.get_cap_level();
    let strike_price0 = round.get_strike_price();

    let random_pricing_data = get_random_pricing_data_points();
    set_contract_address(vault.contract_address());
    round.update_params(random_pricing_data, '0xDoesntMatter');

    let reserve_price = round.get_reserve_price();
    let cap_level = round.get_cap_level();
    let strike_price = round.get_strike_price();

    // Check params change
    assert(reserve_price != reserve_price0, 'reserve price did not change');
    assert(cap_level != cap_level0, 'cap level did not change');
    assert(strike_price != strike_price0, 'strike price did not change');
    // Check params are changed correctly
    assert_eq!(reserve_price, random_pricing_data.reserve_price);
    assert_eq!(cap_level, random_pricing_data.cap_level);
    assert_eq!(strike_price, random_pricing_data.strike_price);
}

#[test]
#[available_gas(50000000)]
fn test_first_round_cannot_start_until_fact_set() {
    let eth = deploy_eth();
    let fact_registry = deploy_fact_registry();
    let vault_dispatcher = deploy_vault(
        VaultType::AtTheMoney, eth.contract_address, fact_registry.contract_address
    );
    let mut vault: VaultFacade = VaultFacade { vault_dispatcher };

    vault.start_auction_expect_error(Errors::PricingDataPointsNotSet);
}

#[test]
#[available_gas(50000000)]
fn test_setting_first_round_params() {
    set_block_timestamp(123456789);
    let eth = deploy_eth();
    let fact_registry = deploy_fact_registry();
    let vault_dispatcher = deploy_vault(
        VaultType::AtTheMoney, eth.contract_address, fact_registry.contract_address
    );
    let mut vault: VaultFacade = VaultFacade { vault_dispatcher };
    let mut current_round = vault.get_current_round();

    let auction_start_date = current_round.get_auction_start_date();
    let to = auction_start_date - 1;
    let JobRange { twap_range, volatility_range, reserve_price_range } = Vault::EXPECTED_JOB_RANGE;

    let job_request: JobRequest = JobRequest {
        identifiers: array![selector!("PITCH_LAKE_V1")].span(),
        params: JobRequestParams {
            twap: (to - twap_range, to),
            volatility: (to - volatility_range, to),
            reserve_price: (to - reserve_price_range, to),
        }
    };
    // Mock verify the fact in the registry
    let data = FossilDataPoints {
        twap: to_gwei(10), volatility: 5000, reserve_price: to_gwei(123),
    };

    fact_registry.set_fact(job_request, data);
    vault.refresh_round_pricing_data(job_request);

    let exp_strike_price = pricing_utils::calculate_strike_price(
        VaultType::AtTheMoney, to_gwei(10), 5000
    );
    let exp_cap_level = pricing_utils::calculate_cap_level(123, 5000);
    let exp_reserve_price = to_gwei(123);

    let reserve_price = current_round.get_reserve_price();
    let strike_price = current_round.get_strike_price();
    let cap_level = current_round.get_cap_level();

    assert_eq!(reserve_price, exp_reserve_price);
    assert_eq!(strike_price, exp_strike_price);
    assert_eq!(cap_level, exp_cap_level);

    vault.start_auction_expect_error(Errors::PricingDataPointsNotSet);
}

#[test]
#[available_gas(1_000_000_000)]
fn test_refreshing_consequtive_round_refreshing() {
    let (mut vault, _) = setup_facade();

    for _ in 0
        ..2_usize {
            accelerate_to_auctioning(ref vault);
            accelerate_to_running(ref vault);
            accelerate_to_settled(ref vault, to_gwei(10));

            let mut next_round = vault.get_current_round();
            let auction_start_date = next_round.get_auction_start_date();
            let to = auction_start_date - 1;

            // Mock verify the fact in the registry
            let job_request = create_job_request(to);

            // Refresh with new data
            let exp_twap = to_gwei(666);
            let exp_volatility = 1234;
            let exp_reserve_price = to_gwei(123);
            let data = FossilDataPoints {
                twap: exp_twap, volatility: exp_volatility, reserve_price: exp_reserve_price,
            };

            vault.get_fact_registry_facade().set_fact(job_request, data);
            vault.refresh_round_pricing_data(job_request);

            let (cap_level, strike_price, reserve_price) = {
                (
                    next_round.get_cap_level(),
                    next_round.get_strike_price(),
                    next_round.get_reserve_price()
                )
            };

            assert_eq!(cap_level, pricing_utils::calculate_cap_level(123, exp_volatility));
            assert_eq!(reserve_price, exp_reserve_price);
            assert_eq!(
                strike_price,
                pricing_utils::calculate_strike_price(
                    VaultType::AtTheMoney, exp_twap, exp_volatility
                )
            );

            // Refresh with new data
            let exp_twap2 = to_gwei(777);
            let exp_volatility2 = 6789;
            let exp_reserve_price2 = to_gwei(333);
            let data2 = FossilDataPoints {
                twap: exp_twap2, volatility: exp_volatility2, reserve_price: exp_reserve_price2,
            };

            vault.get_fact_registry_facade().set_fact(job_request, data2);
            vault.refresh_round_pricing_data(job_request);

            let (cap_level2, strike_price2, reserve_price2) = {
                (
                    next_round.get_cap_level(),
                    next_round.get_strike_price(),
                    next_round.get_reserve_price()
                )
            };

            assert_eq!(cap_level2, pricing_utils::calculate_cap_level(123, exp_volatility2));
            assert_eq!(reserve_price2, exp_reserve_price2);
            assert_eq!(
                strike_price2,
                pricing_utils::calculate_strike_price(
                    VaultType::AtTheMoney, exp_twap2, exp_volatility2
                )
            );
        }
}

