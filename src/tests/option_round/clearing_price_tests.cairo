
// use array::ArrayTrait;
// use debug::PrintTrait;
// use option::OptionTrait;

// use openzeppelin::utils::serde::SerializedAppend;
// use openzeppelin::token::erc20::interface::{
//     IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
//     IERC20SafeDispatcherTrait,
// };

// use pitch_lake_starknet::vault::{
//     IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
// };
// use pitch_lake_starknet::option_round::{OptionRoundParams};
// use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup_facade, decimals, liquidity_provider_1, option_bidder_buyer_1, assert_event_auction_bid,
    option_bidder_buyer_2, option_bidder_buyer_3
// , deploy_vault, allocated_pool_address, unallocated_pool_address,
// timestamp_start_month, timestamp_end_month, liquidity_provider_2,
// option_bidder_buyer_1, option_bidder_buyer_4
// , option_bidder_buyer_6, vault_manager, weth_owner, mock_option_params,
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
fn test_clearing_price_1() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round_facade.get_params();
    // Make bid for 2 options at the reserve price
    let bid_count: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Settle auction
    let clearing_price: u256 = vault_facade.timeskip_and_end_auction();
    assert(
        clearing_price == current_round_facade.get_auction_clearing_price(),
        'clearing price not set'
    );
    assert(clearing_price == params.reserve_price, 'clearing price wrong');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount, params.reserve_price);
}


#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round_facade.get_params();
    // Two OBs bid for all options with different prices
    let bid_count: u256 = params.total_options_available;
    let bid_price_user_1: u256 = params.reserve_price;
    let bid_price_user_2: u256 = params.reserve_price + 10;
    let bid_amount_user_1: u256 = bid_count * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count * bid_price_user_2 * decimals();
    current_round_facade.place_bid(bid_amount_user_1, bid_price_user_1, option_bidder_buyer_1());
    current_round_facade.place_bid(bid_amount_user_2, bid_price_user_2, option_bidder_buyer_2());
    // Settle auction
    let clearing_price: u256 = vault_facade.timeskip_and_end_auction();
    // OB 2's price should be the clearing price since all options can be sold to OB2
    assert(clearing_price == bid_price_user_2, 'clearing price wrong');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade:OptionRoundFacade=vault_facade.get_current_round();
    let params: OptionRoundParams = current_round_facade.get_params();
    // Two OBs bid for the combined total amount of options, OB 1 outbids OB 2
    let bid_count_user_1: u256 = params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;
    let bid_price_user_1: u256 = params.reserve_price + 100;
    let bid_price_user_2: u256 = params.reserve_price;
    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2 * decimals();
    current_round_facade.place_bid(bid_amount_user_1, bid_price_user_1, option_bidder_buyer_1());
    current_round_facade.place_bid(bid_amount_user_2, bid_price_user_2, option_bidder_buyer_2());
    // Settle auction
    let clearing_price: u256 = vault_facade.timeskip_and_end_auction();
    // OB 2's price should be the clearing price as it will be included to sell all the options
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
}


#[test]
#[available_gas(10000000)]
fn test_clearing_price_4() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Three OBs bid for the combined amount of options, OB 1 outbids 2, who outbids 3  
    let bid_count_user_1: u256 = params.total_options_available / 3;
    let bid_count_user_2: u256 = params.total_options_available / 2;
    let bid_count_user_3: u256 = params.total_options_available / 3;
    let bid_price_user_1: u256 = params.reserve_price + 100;
    let bid_price_user_2: u256 = params.reserve_price + 5;
    let bid_price_user_3: u256 = params.reserve_price;
    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1;
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2;
    let bid_amount_user_3: u256 = bid_count_user_3 * bid_price_user_3;
    round_facade.place_bid(bid_amount_user_1, bid_price_user_1, option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_user_2, bid_price_user_2, option_bidder_buyer_2());
    round_facade.place_bid(bid_amount_user_3, bid_price_user_3, option_bidder_buyer_3());
    // End the auction
    
    // OB3's price will be the clearing price since we need to include all 3
    let clearing_price: u256 = vault_facade.timeskip_and_end_auction();
    assert(clearing_price == bid_price_user_3, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
    assert_event_auction_bid(option_bidder_buyer_3(), bid_amount_user_3, bid_price_user_3);
}


#[test]
#[available_gas(10000000)]
fn test_clearing_price_5() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Three OBs bid for the options. OB 1 and 2 bid for all of the options, outbidding OB3
    let bid_count_user_1: u256 = params.total_options_available / 2;
    let bid_count_user_2: u256 = params.total_options_available / 2;
    let bid_count_user_3: u256 = params.total_options_available / 3;
    let bid_price_user_1: u256 = params.reserve_price + 100;
    let bid_price_user_2: u256 = params.reserve_price + 5;
    let bid_price_user_3: u256 = params.reserve_price;
    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1;
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2;
    let bid_amount_user_3: u256 = bid_count_user_3 * bid_price_user_3;
    round_facade.place_bid(bid_amount_user_1, bid_price_user_1, option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_user_2, bid_price_user_2, option_bidder_buyer_2());
    round_facade.place_bid(bid_amount_user_3, bid_price_user_3, option_bidder_buyer_3());
    // End the auction
    
    // We can sell all options for a higher price if we clear with OB2's price
    // OB3's bid is not needed to sell all the options
    let clearing_price: u256 = vault_facade.timeskip_and_end_auction();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');

// Test that auction clearing price is 0 pre auction end
#[test]
#[available_gas(10000000)]
fn test_option_round_clearing_price_is_0_before_auction_end() {
    let (mut vault_facade, _) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10 * decimals();
    vault_facade.deposit(deposit_amount_wei, liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    // Get the current auctioning roun
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    // Make bid 
    let option_params: OptionRoundParams = current_round_facade.get_params();
    let bid_count: u256 = option_params.total_options_available;
    let bid_price: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price, option_bidder_buyer_1());
    // Check that clearing price is 0 pre auction settlement
    let clearing_price = current_round_facade.get_auction_clearing_price();
    assert(clearing_price == 0, 'should be 0 pre auction end');

}

