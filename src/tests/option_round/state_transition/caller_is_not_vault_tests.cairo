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
                    accelerate_to_settled, clear_event_logs,
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

const salt: u64 = 0x123;

const err: felt252 = Errors::CallerIsNotVault;
const err2: felt252 = vErrors::CallerNotWhitelisted;

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

fn get_random_pricing_data_points() -> PricingData {
    PricingData { strike_price: to_gwei(5829), cap_level: 20084, reserve_price: to_gwei(482745), }
}

#[test]
#[available_gas(50000000)]
fn test_only_vault_can_update_round_params() {
    let (mut vault, _) = setup_facade();
    let mut round = vault.get_current_round();
    let data = get_random_pricing_data_points();

    set_contract_address(not_vault());
    round.set_pricing_data_expect_err(data, err);
}

#[test]
#[available_gas(50000000)]
fn test_set_pricing_data_on_round() {
    let (mut vault, _) = setup_facade();
    let mut round = vault.get_current_round();

    let reserve_price0 = round.get_reserve_price();
    let cap_level0 = round.get_cap_level();
    let strike_price0 = round.get_strike_price();

    let random_pricing_data = get_random_pricing_data_points();
    set_contract_address(vault.contract_address());
    round.set_pricing_data(random_pricing_data.clone());

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
fn test_setting_first_round_params_updates_from_default() {
    set_block_timestamp(123456789);
    let eth = deploy_eth();
    let vault_dispatcher = deploy_vault(VaultType::AtTheMoney, eth.contract_address);
    let mut vault: VaultFacade = VaultFacade { vault_dispatcher };
    let mut current_round = vault.get_current_round();

    let strike_price0 = current_round.get_strike_price();
    let cap_level0 = current_round.get_cap_level();
    let reserve_price0 = current_round.get_reserve_price();

    let request = vault.get_request_to_start_auction();
    let result = L1Result {
        proof: array![].span(),
        data: L1Data { twap: to_gwei(10), volatility: 5000, reserve_price: to_gwei(123), }
    };

    set_contract_address(get_fossil_address());
    vault.fulfill_request(request, result);

    let strike_price = current_round.get_strike_price();
    let cap_level = current_round.get_cap_level();
    let reserve_price = current_round.get_reserve_price();

    assert_eq!(reserve_price0, 0);
    assert_eq!(strike_price0, 0);
    assert_eq!(cap_level0, 0);

    let ex_cap_level = pricing_utils::calculate_cap_level(0, 5000);
    let ex_strike_price = pricing_utils::calculate_strike_price(
        VaultType::AtTheMoney, to_gwei(10), 5000
    );

    assert_eq!(reserve_price, to_gwei(123));
    assert_eq!(cap_level, ex_cap_level);
    assert_eq!(strike_price, ex_strike_price);
}
