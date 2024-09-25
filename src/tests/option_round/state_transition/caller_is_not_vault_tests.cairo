use starknet::{
    get_block_timestamp, ContractAddress, contract_address_const,
    testing::{set_contract_address, set_block_timestamp}
};
use pitch_lake::{
    vault::contract::Vault, option_round::contract::OptionRound::Errors,
    tests::{
        utils::{
            helpers::{
                accelerators::{
                    accelerate_to_auctioning, accelerate_to_running, accelerate_to_running_custom
                },
                setup::{setup_facade},
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


#[test]
#[available_gas(50000000)]
fn test_only_vault_can_update_round_params() {
    let (mut vault, _) = setup_facade();
    let mut round = vault.get_current_round();

    set_contract_address(not_vault());
    round.update_round_params_expect_error(err);
}

#[test]
#[available_gas(50000000)]
fn test_update_round_params_on_round() {
    let (mut vault, _) = setup_facade();
    let mut round = vault.get_current_round();

    let reserve_price0 = round.get_reserve_price();
    let cap_level0 = round.get_cap_level();
    let strike_price0 = round.get_strike_price();

    set_contract_address(vault.contract_address());
    round.update_params(1, 2, 3);

    let reserve_price = round.get_reserve_price();
    let cap_level = round.get_cap_level();
    let strike_price = round.get_strike_price();

    assert_eq!(reserve_price, 1);
    assert_eq!(cap_level, 2);
    assert_eq!(strike_price, 3);
    assert(reserve_price != reserve_price0, 'reserve price did not change');
    assert(cap_level != cap_level0, 'cap level did not change');
    assert(strike_price != strike_price0, 'strike price did not change');
}
//#[test]
//#[available_gas(50000000)]
//fn test_update_round_params_on_vault() {
//    let (mut vault, _) = setup_facade();
//    let mut round = vault.get_current_round();
//
//    let reserve_price0 = round.get_reserve_price();
//    let cap_level0 = round.get_cap_level();
//    let strike_price0 = round.get_strike_price();
//    let mk_agg = vault.get_market_aggregator_facade();
//    let volatility0 = mk_agg
//        .get_volatility_for_round(vault.contract_address(), round.get_round_id())
//        .unwrap();
//
//    // Mock values on mk agg
//    let new_reserve_price = 1;
//    let new_cap_level = 2;
//    let new_strike_price = 3;
//    let new_volatility = 4;
//
//    mk_agg
//        .set_reserve_price_for_round(
//            vault.contract_address(), round.get_round_id(), new_reserve_price
//        );
//    mk_agg.set_cap_level_for_round(vault.contract_address(), round.get_round_id(), new_cap_level);
//    mk_agg.set_volatility_for_round(vault.contract_address(), round.get_round_id(),
//    new_volatility);
//
//    let to = round.get_auction_start_date();
//    let from = to - Vault::TWAP_DURATION;
//    // @note Only works because vautl is default ATM
//    mk_agg.set_TWAP_for_time_period(from, to, new_strike_price);
//
//    vault.update_round_params();
//
//    let reserve_price = round.get_reserve_price();
//    let cap_level = round.get_cap_level();
//    let strike_price = round.get_strike_price();
//    let volatility = mk_agg
//        .get_volatility_for_round(vault.contract_address(), round.get_round_id())
//        .unwrap();
//
//    assert_eq!(reserve_price, new_reserve_price);
//    assert_eq!(cap_level, new_cap_level);
//    assert_eq!(strike_price, new_strike_price);
//    assert_eq!(volatility, new_volatility);
//    assert(reserve_price != reserve_price0, 'reserve price did not change');
//    assert(cap_level != cap_level0, 'cap level did not change');
//    assert(strike_price != strike_price0, 'strike price did not change');
//    assert(volatility != volatility0, 'volatility did not change');
//}


