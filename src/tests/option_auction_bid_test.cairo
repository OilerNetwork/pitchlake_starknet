use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait
};
use pitch_lake_starknet::option_round::{OptionRoundParams};
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup, setup_facade, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    option_bidder_buyer_5, option_bidder_buyer_6, vault_manager, weth_owner, mock_option_params,
    month_duration, assert_event_auction_bid
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};
use pitch_lake_starknet::tests::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake_starknet::tests::option_round_facade::{OptionRoundFacade, OptionRoundFacadeTrait};
use starknet::contract_address::ContractAddressZeroable;

use traits::Into;
use traits::TryInto;

#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = current_round_facade.get_params();
    // Make bid for 2 options at the reserve price
    let bid_count: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price;
    current_round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
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
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
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
    current_round_facade.place_bid(bid_amount_user_1, bid_price_user_1,option_bidder_buyer_1());
    current_round_facade.place_bid(bid_amount_user_2, bid_price_user_2,option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
    // OB 2 should win the auction
    assert(clearing_price == bid_price_user_2, 'clearing price wrong');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut current_round_facade: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_facade
            .get_option_round_address(vault_facade.current_option_round_id())
    };
    let params: OptionRoundParams = current_round_facade.get_params();
    // Two OBs bid for the combined total amount of options, OB 1 outbids OB 2
    let bid_count_user_1: u256 = params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;
    let bid_price_user_1: u256 = params.reserve_price + 100;
    let bid_price_user_2: u256 = params.reserve_price;
    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2 * decimals();
    set_contract_address(option_bidder_buyer_1());
    current_round_facade.place_bid(bid_amount_user_1, bid_price_user_1);
    set_contract_address(option_bidder_buyer_2());
    current_round_facade.place_bid(bid_amount_user_2, bid_price_user_2);
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    let clearing_price: u256 = vault_facade.end_auction();
    // OB 2's price should be the clearing price so that we sell all options 
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_4() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
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
    round_facade.place_bid(bid_amount_user_1, bid_price_user_1,option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_user_2, bid_price_user_2,option_bidder_buyer_2());
    round_facade.place_bid(bid_amount_user_3, bid_price_user_3,option_bidder_buyer_3());
    // End the auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // The only price we can sell all options is OB3's. Anything > would sell < total_options_available
    let clearing_price: u256 = round_facade.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_3, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
    assert_event_auction_bid(option_bidder_buyer_3(), bid_amount_user_3, bid_price_user_3);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_5() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
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
    round_facade.place_bid(bid_amount_user_1, bid_price_user_1,option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_user_2, bid_price_user_2,option_bidder_buyer_2());
    round_facade.place_bid(bid_amount_user_3, bid_price_user_3,option_bidder_buyer_3());
    // End the auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // We can sell all options for a higher price if we clear with OB2's price
    // OB3's price will sell them all, but make less in premium
    let clearing_price: u256 = round_facade.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid is below reserve price', 'ENTRYPOINT_FAILED',))]
fn test_bid_below_reserve_price() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 50 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Place bid below reserve price
    let bid_count: u256 = 10;
    let bid_price: u256 = params.reserve_price - 1;
    let bid_amount: u256 = bid_count * bid_price;
    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
}

#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Make bid
    let bid_count: u256 = 2;
    let bid_price: u256 = params.reserve_price;
    let bid_amount: u256 = bid_count * bid_count;
    let ob_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_before_bid: u256 = eth_dispatcher
        .balance_of(round_facade.contract_address());
    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    let ob_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let round_balance_after_bid: u256 = eth_dispatcher
        .balance_of(round_facade.contract_address());
    // Check bids went to the round
    assert(
        ob_balance_after_bid - bid_amount == ob_balance_before_bid, 'bid did not leave obs account'
    );
    assert(
        round_balance_before_bid + bid_amount == round_balance_after_bid, 'bid did not reach round'
    );
}


#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid amount must be > 0', 'ENTRYPOINT_FAILED',))]
fn test_bid_zero_amount_failure() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Try to bid 0 amount
    round_facade.place_bid(0, params.reserve_price,option_bidder_buyer_1());
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Bid price must be >= reserve price', 'ENTRYPOINT_FAILED',))]
fn test_bid_price_below_reserve_price_failure() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Try to bid 0 price
    round_facade.place_bid(2, params.reserve_price - 1,option_bidder_buyer_1());
}

#[test]
#[available_gas(10000000)]
fn test_unused_bids_for_ob_while_auctioning() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Make bid
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;
    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    // Check entire bid is 'unused' while still auctioning
    let ob_unused_bid_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
}

//@note add test for bidding for more than total options ? or irrelevant exceses is refunable ? 

#[test]
#[available_gas(10000000)]
fn test_unused_bids_for_ob_after_auctioning() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_2, bid_price_2,option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // Check OB 1's unused bid is their entire bid, and OB 2's is 0
    let ob_unused_bid_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    let ob_unused_bid_amount_2 = round_facade.get_unused_bids_for(option_bidder_buyer_2());
    assert(ob_unused_bid_amount == bid_amount, 'unused bids wrong');
    assert(ob_unused_bid_amount_2 == 0, 'unused bids wrong');
}


#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_after_auction_end_success() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();

    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;

    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());

    round_facade.place_bid(bid_amount_2, bid_price_2,option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // OB 1 collects their unused bids
    let unused_amount = round_facade.get_unused_bids_for(option_bidder_buyer_1());
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect + unused_amount == ob_balance_after_collect, 'refund fail');
    assert(
        round_facade.get_unused_bids_for(option_bidder_buyer_1()) == 0,
        'collect amount should be 0'
    );
}


#[test]
#[available_gas(10000000)]
fn test_collect_unused_bids_none_left() {
    let (mut vault_facade, eth_dispatcher): (VaultFacade, IERC20Dispatcher) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 2 outbids OB 1 for all the options
    let bid_count = params.total_options_available;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price + 1;
    let bid_amount = bid_count * bid_price;
    let bid_amount_2 = bid_count * bid_price_2;
    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    round_facade.place_bid(bid_amount_2, bid_price_2,option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // OB 1 collects their unused bids
    round_facade.refund_bid(option_bidder_buyer_1());
    // OB 1 collects again
    let ob_balance_before_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_facade.refund_bid(option_bidder_buyer_1());
    let ob_balance_after_collect = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // Check OB gets their refunded depost and their amount updates to 0
    assert(ob_balance_before_collect == ob_balance_after_collect, 'balance should not change');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_1() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();

    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 1 and 2 bid for > the total options available at the reserve price
    let bid_count_1: u256 = params.total_options_available / 2 + 1;
    let bid_count_2: u256 = params.total_options_available / 2;
    let bid_price = params.reserve_price;
    let bid_amount_1: u256 = bid_count_1 * bid_price;
    let bid_amount_2: u256 = bid_count_2 * bid_price;

    round_facade.place_bid(bid_amount_1, bid_price,option_bidder_buyer_1());

    round_facade.place_bid(bid_amount_2, bid_price,option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();

    // Check total options sold is the total options available
    assert(
        params.total_options_available == round_facade.total_options_sold(),
        'options sold wrong'
    );
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_2() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 1 and 2 bid for > the total options available at the reserve price
    let bid_count_1: u256 = params.total_options_available / 2 + 1;
    let bid_count_2: u256 = params.total_options_available / 2;
    let bid_price = params.reserve_price;
    let bid_price_2 = bid_price - 1;
    let bid_amount_1: u256 = bid_count_1 * bid_price;
    let bid_amount_2: u256 = bid_count_2 * bid_price;

    round_facade.place_bid(bid_amount_1, bid_price,option_bidder_buyer_1());

    round_facade.place_bid(bid_amount_2, bid_price_2,option_bidder_buyer_2());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();

    // Check total options sold is the total options available
    assert(bid_count_1 == round_facade.total_options_sold(), 'options sold wrong');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_3() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // OB 1 and 2 bid for > the total options available at the reserve price
    let bid_count = 2;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;

    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();

    // Check total options sold is successful bids count
    assert(bid_count == round_facade.total_options_sold(), 'options sold wrong');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_4() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Make no bids
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // Check no options were sold if no bids 
    assert(0 == round_facade.total_options_sold(), 'no options should sell');
}

// this test is similar to one of the above test, maybe change their names and regroup closer together
#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_5() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Make bids for > total options
    let bid_count = params.total_options_available + 10;
    let bid_price = params.reserve_price;
    let bid_amount = bid_count * bid_price;

    round_facade.place_bid(bid_amount, bid_price,option_bidder_buyer_1());
    // Settle auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // Check all options sell
    assert(
        params.total_options_available == round_facade.total_options_sold(),
        'max options should sell'
    );
}

///////////////////// tests below are based on auction_reference_size_is_max_amount.py results/////////////////////////

#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_1() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let params: OptionRoundParams = round_facade.get_params();
    // Make bids
    let bid_option_count_user_1: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_1: u256 = params.reserve_price + 1;
    let bid_amount_user_1: u256 = bid_option_count_user_1 * bid_price_per_unit_user_1;
    round_facade.place_bid(bid_amount_user_1, bid_price_per_unit_user_1,option_bidder_buyer_1());
    let bid_option_count_user_2: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_2: u256 = params.reserve_price + 2;
    let bid_amount_user_2: u256 = bid_option_count_user_2 * bid_price_per_unit_user_2;
    round_facade.place_bid(bid_amount_user_2, bid_price_per_unit_user_2,option_bidder_buyer_2());
    let bid_option_count_user_3: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_3: u256 = params.reserve_price + 3;
    let bid_amount_user_3: u256 = bid_option_count_user_3 * bid_price_per_unit_user_3;
    round_facade.place_bid(bid_amount_user_3, bid_price_per_unit_user_3,option_bidder_buyer_3());
    let bid_option_count_user_4: u256 = (params.total_options_available / 3);
    let bid_price_per_unit_user_4: u256 = params.reserve_price + 4;
    let bid_amount_user_4: u256 = bid_option_count_user_4 * bid_price_per_unit_user_4;
    round_facade.place_bid(bid_amount_user_4, bid_price_per_unit_user_4,option_bidder_buyer_4());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // Test that each user gets the correct amount of options
    // @dev Using erc20 dispatcher since the option balances are the same as 
    // erc20::balance_of()
    let round_facade_erc20 = IERC20Dispatcher {
        contract_address: round_facade.contract_address()
    };
    let total_options_created_count: u256 = round_facade.total_options_sold();
    let options_created_user_1_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_1());
    let options_created_user_2_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_2());
    let options_created_user_3_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_3());
    let options_created_user_4_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_4());
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
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let mut params: OptionRoundParams = round_facade.get_params();
    // Make bids
    params.total_options_available = 300; //TODO need a better way to mock this
    params.reserve_price = 2;
    let bid_option_amount_user_1: u256 = 50;
    let bid_price_per_unit_user_1: u256 = 20;

    round_facade.place_bid(bid_option_amount_user_1, bid_price_per_unit_user_1,option_bidder_buyer_1());

    let bid_option_amount_user_2: u256 = 142;
    let bid_price_per_unit_user_2: u256 = 11;

    round_facade.place_bid(bid_option_amount_user_2, bid_price_per_unit_user_2,option_bidder_buyer_2());

    let bid_option_amount_user_3: u256 = 235;
    let bid_price_per_unit_user_3: u256 = 11;

    round_facade.place_bid(bid_option_amount_user_3, bid_price_per_unit_user_3,option_bidder_buyer_3());

    let bid_option_amount_user_4: u256 = 222;
    let bid_price_per_unit_user_4: u256 = 2;

    round_facade.place_bid(bid_option_amount_user_4, bid_price_per_unit_user_4,option_bidder_buyer_4());

    let bid_option_amount_user_5: u256 = 75;
    let bid_price_per_unit_user_5: u256 = 1;
    round_facade.place_bid(bid_option_amount_user_5, bid_price_per_unit_user_5,option_bidder_buyer_5());

    let bid_option_amount_user_6: u256 = 35;
    let bid_price_per_unit_user_6: u256 = 1;

    round_facade.place_bid(bid_option_amount_user_6, bid_price_per_unit_user_6,option_bidder_buyer_6());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();

    let round_facade_erc20 = IERC20Dispatcher {
        contract_address: round_facade.contract_address()
    };
    let total_options_created_count: u256 = round_facade.total_options_sold();
    let options_created_user_1_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_1());
    let options_created_user_2_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_2());
    let options_created_user_3_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_3());
    let options_created_user_4_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_4());
    let options_created_user_5_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_5());
    let options_created_user_6_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_6());

    assert(total_options_created_count == 275, 'options shd match');
    assert(options_created_user_1_count == 25, 'options shd match');
    assert(options_created_user_2_count == 71, 'options shd match');
    assert(options_created_user_3_count == 117, 'options shd match');
    assert(options_created_user_4_count == 86, 'options shd match');
    assert(options_created_user_5_count == 0, 'options shd match');
    assert(options_created_user_6_count == 0, 'options shd match');
}

// test where the total options available have all been sold and there are unused bids which are locked up and can be claimed by the bidders

#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_3() {
    let (mut vault_facade,_) = setup_facade();
    // LP deposits (into round 1)
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    vault_facade.deposit(deposit_amount_wei,liquidity_provider_1());
    // Start auction
    vault_facade.start_auction();
    let mut round_facade:OptionRoundFacade = vault_facade.get_current_round();
    let mut params: OptionRoundParams = round_facade.get_params();
    // Make bids
    params.total_options_available = 200; //TODO  need a better to mock this
    params.reserve_price = 2;
    let bid_option_amount_user_1: u256 = 50;
    let bid_price_per_unit_user_1: u256 = 20;

    round_facade.place_bid(bid_option_amount_user_1, bid_price_per_unit_user_1,option_bidder_buyer_1());

    let bid_option_amount_user_2: u256 = 142;
    let bid_price_per_unit_user_2: u256 = 11;

    round_facade.place_bid(bid_option_amount_user_2, bid_price_per_unit_user_2,option_bidder_buyer_2());

    let bid_option_amount_user_3: u256 = 235;
    let bid_price_per_unit_user_3: u256 = 11;

    round_facade.place_bid(bid_option_amount_user_3, bid_price_per_unit_user_3,option_bidder_buyer_3());

    let bid_option_amount_user_4: u256 = 422;
    let bid_price_per_unit_user_4: u256 = 2;
    round_facade.place_bid(bid_option_amount_user_4, bid_price_per_unit_user_4,option_bidder_buyer_4());

    let bid_option_amount_user_5: u256 = 75;
    let bid_price_per_unit_user_5: u256 = 1;
    round_facade.place_bid(bid_option_amount_user_5, bid_price_per_unit_user_5,option_bidder_buyer_5());

    let bid_option_amount_user_6: u256 = 35;
    let bid_price_per_unit_user_6: u256 = 1;
    round_facade.place_bid(bid_option_amount_user_6, bid_price_per_unit_user_6,option_bidder_buyer_6());
    // End auction
    set_block_timestamp(params.auction_end_time + 1);
    round_facade.end_auction();
    // Get options distrubution and OB 3's refund amount
    let round_facade_erc20 = IERC20Dispatcher {
        contract_address: round_facade.contract_address()
    };
    let total_options_created_count: u256 = round_facade.total_options_sold();
    let options_created_user_1_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_1());
    let options_created_user_2_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_2());
    let options_created_user_3_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_3());
    let options_created_user_4_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_4());
    let options_created_user_5_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_5());
    let options_created_user_6_count: u256 = round_facade_erc20
        .balance_of(option_bidder_buyer_6());
    let unused_bid_amount_user_3: u256 = round_facade
        .get_unused_bids_for(option_bidder_buyer_3());
    // Check correct values
    assert(total_options_created_count == params.total_options_available, 'options shd match');
    assert(options_created_user_1_count == 25, 'options shd match');
    assert(options_created_user_2_count == 71, 'options shd match');
    assert(options_created_user_3_count == 104, 'options shd match');
    assert(options_created_user_4_count == 0, 'options shd match');
    assert(options_created_user_5_count == 0, 'options shd match');
    assert(options_created_user_6_count == 0, 'options shd match');
    assert(unused_bid_amount_user_3 == 27, 'unused bid amount shd match');
}
