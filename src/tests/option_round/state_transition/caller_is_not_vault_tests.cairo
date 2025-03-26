use starknet::{
    get_block_timestamp, ContractAddress, contract_address_const,
    testing::{set_contract_address, set_block_timestamp}
};
use pitch_lake::{
    vault::contract::Vault, vault::contract::Vault::Errors as vErrors,
    option_round::contract::OptionRound::Errors,
    fossil_client::interface::{L1Data, JobRequest, FossilResult},
    fossil_client::contract::FossilClient::Errors as fErrors, option_round::interface::PricingData,
    library::pricing_utils,
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom,
                    accelerate_to_settled, clear_event_logs
                },
                setup::{FOSSIL_PROCESSOR, setup_facade, deploy_vault, deploy_eth},
                event_helpers::{assert_fossil_callback_success_event}, general_helpers::{to_gwei},
                event_helpers::{assert_event_pricing_data_set},
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
                fossil_client_facade::{FossilClientFacade, FossilClientFacadeTrait},
            },
        },
    }
};

const salt: u64 = 0x123;
const err: felt252 = Errors::CallerIsNotVault;

fn not_vault() -> ContractAddress {
    contract_address_const::<'not vault'>()
}

// Test that only the vault can start an auction
#[test]
#[available_gas(50000000)]
fn test_start_auction_caller_is_not_the_vault() {
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
fn test_end_auction_caller_is_not_the_vault() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    vault.place_bid(100, current_round.get_reserve_price(), option_bidder_buyer_1());
    set_block_timestamp(current_round.get_auction_end_date());

    set_contract_address(not_vault());
    current_round.end_auction_expect_error(err);
}

// Test that only the vault can settle an option round
#[test]
#[available_gas(50000000)]
fn test_settle_option_round_caller_is_not_the_vault() {
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
fn test_update_round_params_caller_is_not_the_vault() {
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
fn test_place_bid_caller_is_not_the_vault() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);

    set_contract_address(not_vault());
    current_round
        .place_bid_expect_error(
            100, current_round.get_reserve_price(), option_bidder_buyer_1(), err
        );
}

#[test]
#[available_gas(50000000)]
fn test_update_bid_caller_is_not_the_vault() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    let bid = vault.place_bid(100, current_round.get_reserve_price(), option_bidder_buyer_1());

    set_contract_address(not_vault());
    current_round.update_bid_expect_error(bid.bid_id, to_gwei(1), option_bidder_buyer_1(), err);
}

#[test]
#[available_gas(50000000)]
fn test_refund_unused_bids_caller_is_not_the_vault() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    vault.place_bid(100, current_round.get_reserve_price(), option_bidder_buyer_1());
    accelerate_to_running(ref vault);

    set_contract_address(not_vault());
    current_round.refund_bid_expect_error(option_bidder_buyer_1(), err);
}

#[test]
#[available_gas(50000000)]
fn test_mint_options_caller_is_not_the_vault() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    vault.place_bid(100, current_round.get_reserve_price(), option_bidder_buyer_1());
    accelerate_to_running(ref vault);

    set_contract_address(not_vault());
    current_round.mint_options_expect_error(option_bidder_buyer_1(), err);
}

#[test]
#[available_gas(50000000)]
fn test_exercise_options_caller_is_not_the_vault() {
    let (mut vault, _) = setup_facade();
    let mut current_round = vault.get_current_round();
    accelerate_to_auctioning(ref vault);
    vault.place_bid(100, current_round.get_reserve_price(), option_bidder_buyer_1());
    accelerate_to_running(ref vault);
    accelerate_to_settled(ref vault, 1);

    set_contract_address(not_vault());
    current_round.exercise_options_expect_error(option_bidder_buyer_1(), err);
}
