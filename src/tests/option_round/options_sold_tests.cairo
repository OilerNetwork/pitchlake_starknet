// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;

// use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

// use pitch_lake_starknet::vault::{
//     IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
// };
// use pitch_lake_starknet::option_round::{OptionRoundParams};
// use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, liquidity_provider_1, option_bidder_buyer_1, assert_event_auction_bid,
    option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4, option_bidder_buyer_5,
    option_bidder_buyer_6, vault_manager, accelerate_to_auctioning, accelerate_to_running_custom,
    option_bidders_get, accelerate_to_running
// , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// option_bidder_buyer_1
// , option_bidder_buyer_6, weth_owner, mock_option_params,
// month_duration
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

// use result::ResultTrait;
use starknet::testing::{set_block_timestamp, set_contract_address};

use pitch_lake_starknet::tests::{
    vault_facade::{VaultFacade, VaultFacadeTrait},
    option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait}
};
// use starknet::contract_address::ContractAddressZeroable;

// use traits::Into;
// use traits::TryInto;

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_1() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // OB 1 and 2 bid for > the total options available at the reserve price
    let option_bidders = option_bidders_get(2);
    let bid_count_1: u256 = params.total_options_available / 2 + 1;
    let bid_count_2: u256 = params.total_options_available / 2;
    let bid_price = params.reserve_price;
    let bid_amount_1: u256 = bid_count_1 * bid_price;
    let bid_amount_2: u256 = bid_count_2 * bid_price;

    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![bid_amount_1, bid_amount_2].span(),
        array![bid_price, bid_price].span()
    );

    // Check total options sold is the total options available
    assert(
        params.total_options_available == round_facade.total_options_sold(), 'options sold wrong'
    );
}


#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_2() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // OB 1 and 2 bid for > the total options available at the reserve price
    let option_bidders = option_bidders_get(2);
    let bid_count_1: u256 = params.total_options_available / 2 + 1;
    let bid_count_2: u256 = params.total_options_available / 2;
    let bid_price_1 = params.reserve_price;
    let bid_price_2 = params.reserve_price + 1;
    let bid_amount_1: u256 = bid_count_1 * bid_price_1;
    let bid_amount_2: u256 = bid_count_2 * bid_price_2;

    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![bid_amount_1, bid_amount_2].span(),
        array![bid_price_1, bid_price_2].span()
    );

    // Check total options sold is the total options available
    assert(
        params.total_options_available == round_facade.total_options_sold(), 'options sold wrong'
    );
}


#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_3() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // place bid and end the auction
    accelerate_to_running(ref vault_facade);
    let bid_count = 2;
    assert(bid_count == round_facade.total_options_sold(), 'options sold wrong');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_4() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // Make no bids
    // Settle auction
    vault_facade.timeskip_and_end_auction();

    // Check no options were sold if no bids
    assert(0 == round_facade.total_options_sold(), 'no options should sell');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_5() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // place bid and end the auction
    accelerate_to_running(ref vault_facade);

    // Check all options sell
    assert(
        params.total_options_available == round_facade.total_options_sold(),
        'max options should sell'
    );
}


#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_1() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // Make bids
    let option_bidders = option_bidders_get(4);

    let bid_option_count_user_1: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_1: u256 = params.reserve_price + 1;
    let bid_amount_user_1: u256 = bid_option_count_user_1 * bid_price_per_unit_user_1;

    let bid_option_count_user_2: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_2: u256 = params.reserve_price + 2;
    let bid_amount_user_2: u256 = bid_option_count_user_2 * bid_price_per_unit_user_2;

    let bid_option_count_user_3: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_3: u256 = params.reserve_price + 3;
    let bid_amount_user_3: u256 = bid_option_count_user_3 * bid_price_per_unit_user_3;

    let bid_option_count_user_4: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_4: u256 = params.reserve_price + 4;
    let bid_amount_user_4: u256 = bid_option_count_user_4 * bid_price_per_unit_user_4;

    // place bids and end the auction
    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![bid_amount_user_1, bid_amount_user_2, bid_amount_user_3, bid_amount_user_4].span(),
        array![
            bid_price_per_unit_user_1,
            bid_price_per_unit_user_2,
            bid_price_per_unit_user_3,
            bid_price_per_unit_user_4
        ]
            .span()
    );

    // Test that each user gets the correct amount of options
    // @dev Using erc20 dispatcher since the option balances are the same as
    // erc20::balance_of()
    let round_facade_erc20 = IERC20Dispatcher { contract_address: round_facade.contract_address() };
    let total_options_created_count: u256 = round_facade.total_options_sold();

    // @dev: getting ENTRYPOINT_NOT_FOUND for this, check
    let options_created_user_1_count: u256 = round_facade_erc20.balance_of(*option_bidders[0]);
    let options_created_user_2_count: u256 = round_facade_erc20.balance_of(*option_bidders[1]);
    let options_created_user_3_count: u256 = round_facade_erc20.balance_of(*option_bidders[2]);
    let options_created_user_4_count: u256 = round_facade_erc20.balance_of(*option_bidders[3]);

    // OB 1 should get 0, since price is OB 2's price
    // All other OBs should get their share of options (1/3 total)
    assert(total_options_created_count == params.total_options_available, 'options shd match');
    assert(options_created_user_1_count == 0, 'options shd match');
    assert(options_created_user_2_count == bid_option_count_user_2, 'options shd match');
    assert(options_created_user_3_count == bid_option_count_user_3, 'options shd match');
    assert(options_created_user_4_count == bid_option_count_user_4, 'options shd match');
}


// test where the total options available have not been exhausted
#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_2() {
    let (mut vault_facade, _) = setup_facade();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let mut params: OptionRoundParams = round_facade.get_params();

    // Deposit liquidity and start the auction
    accelerate_to_auctioning(ref vault_facade);

    // Make bids
    let option_bidders = option_bidders_get(6);

    params.total_options_available = 300; //TODO need a better way to mock this
    params.reserve_price = 2;

    let bid_option_amount_user_1: u256 = 50;
    let bid_price_per_unit_user_1: u256 = 20;

    let bid_option_amount_user_2: u256 = 142;
    let bid_price_per_unit_user_2: u256 = 11;

    let bid_option_amount_user_3: u256 = 235;
    let bid_price_per_unit_user_3: u256 = 11;

    let bid_option_amount_user_4: u256 = 222;
    let bid_price_per_unit_user_4: u256 = 2;

    let bid_option_amount_user_5: u256 = 75;
    let bid_price_per_unit_user_5: u256 = 1;

    let bid_option_amount_user_6: u256 = 35;
    let bid_price_per_unit_user_6: u256 = 1;

    accelerate_to_running_custom(
        ref vault_facade,
        option_bidders.span(),
        array![
            bid_option_amount_user_1,
            bid_option_amount_user_2,
            bid_option_amount_user_3,
            bid_option_amount_user_4,
            bid_option_amount_user_5,
            bid_option_amount_user_6
        ]
            .span(),
        array![
            bid_price_per_unit_user_1,
            bid_price_per_unit_user_2,
            bid_price_per_unit_user_3,
            bid_price_per_unit_user_4,
            bid_price_per_unit_user_5,
            bid_price_per_unit_user_6
        ]
            .span()
    );

    let round_facade_erc20 = IERC20Dispatcher { contract_address: round_facade.contract_address() };
    let total_options_created_count: u256 = round_facade.total_options_sold();
    let options_created_user_1_count: u256 = round_facade_erc20.balance_of(*option_bidders[0]);
    let options_created_user_2_count: u256 = round_facade_erc20.balance_of(*option_bidders[1]);
    let options_created_user_3_count: u256 = round_facade_erc20.balance_of(*option_bidders[2]);
    let options_created_user_4_count: u256 = round_facade_erc20.balance_of(*option_bidders[3]);
    let options_created_user_5_count: u256 = round_facade_erc20.balance_of(*option_bidders[4]);
    let options_created_user_6_count: u256 = round_facade_erc20.balance_of(*option_bidders[5]);

    assert(total_options_created_count == 275, 'options shd match');
    assert(options_created_user_1_count == 25, 'options shd match');
    assert(options_created_user_2_count == 71, 'options shd match');
    assert(options_created_user_3_count == 117, 'options shd match');
    assert(options_created_user_4_count == 86, 'options shd match');
    assert(options_created_user_5_count == 0, 'options shd match');
    assert(options_created_user_6_count == 0, 'options shd match');
}

// Test that options sold is 0 pre auction end
#[test]
#[available_gas(10000000)]
fn test_option_round_options_sold_before_auction_end_is_0() {
    let (mut vault_facade, _) = setup_facade();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let option_params: OptionRoundParams = current_round_facade.get_params();

    // Deposit liquidity and start the auction
    set_contract_address(vault_manager());
    accelerate_to_auctioning(ref vault_facade);

    // Make bid
    set_contract_address(option_bidder_buyer_1());
    accelerate_to_running(ref vault_facade);

    // Check that options_sold is 0 pre auction settlement
    let options_sold: u256 = current_round_facade.total_options_sold();
    // Should be zero as auction has not ended
    assert(options_sold == 0, 'options_sold should be 0');
}
