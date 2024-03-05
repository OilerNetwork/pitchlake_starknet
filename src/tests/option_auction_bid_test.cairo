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
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    option_bidder_buyer_5, option_bidder_buyer_6, vault_manager, weth_owner, mock_option_params,
    month_duration, assert_event_auction_bid
};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;

use traits::Into;
use traits::TryInto;

#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price(option_round_id);
    assert(clearing_price == option_params.reserve_price, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount, option_params.reserve_price);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_price_user_2: u256 = option_params.reserve_price + 10;

    let bid_amount_user_1: u256 = bid_count * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count * bid_price_user_2 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);
    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, bid_price_user_2);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price(option_round_id);
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count_user_1: u256 = option_params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;

    let bid_price_user_1: u256 = option_params.reserve_price + 100;
    let bid_price_user_2: u256 = option_params.reserve_price;

    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, bid_price_user_2);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price(option_round_id);
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_4() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count_user_1: u256 = option_params.total_options_available / 3;
    let bid_count_user_2: u256 = option_params.total_options_available / 2;
    let bid_count_user_3: u256 = option_params.total_options_available / 3;

    let bid_price_user_1: u256 = option_params.reserve_price + 100;
    let bid_price_user_2: u256 = option_params.reserve_price + 5;
    let bid_price_user_3: u256 = option_params.reserve_price;

    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2 * decimals();
    let bid_amount_user_3: u256 = bid_count_user_3 * bid_price_user_3 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, bid_price_user_2);

    set_contract_address(option_bidder_buyer_3());
    vault_dispatcher.auction_place_bid(bid_amount_user_3, bid_price_user_3);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price(option_round_id);
    assert(clearing_price == bid_price_user_3, 'clear price equal reserve price');
    assert_event_auction_bid(option_bidder_buyer_1(), bid_amount_user_1, bid_price_user_1);
    assert_event_auction_bid(option_bidder_buyer_2(), bid_amount_user_2, bid_price_user_2);
    assert_event_auction_bid(option_bidder_buyer_3(), bid_amount_user_3, bid_price_user_3);
}

#[test]
#[available_gas(10000000)]
fn test_clearing_price_5() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count_user_1: u256 = option_params.total_options_available / 2;
    let bid_count_user_2: u256 = option_params.total_options_available / 2;
    let bid_count_user_3: u256 = option_params.total_options_available / 3;

    let bid_price_user_1: u256 = option_params.reserve_price + 100;
    let bid_price_user_2: u256 = option_params.reserve_price + 5;
    let bid_price_user_3: u256 = option_params.reserve_price;

    let bid_amount_user_1: u256 = bid_count_user_1 * bid_price_user_1 * decimals();
    let bid_amount_user_2: u256 = bid_count_user_2 * bid_price_user_2 * decimals();
    let bid_amount_user_3: u256 = bid_count_user_3 * bid_price_user_3 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_user_1);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, bid_price_user_2);

    set_contract_address(option_bidder_buyer_3());
    vault_dispatcher.auction_place_bid(bid_amount_user_3, bid_price_user_3);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let clearing_price: u256 = vault_dispatcher.get_auction_clearing_price(option_round_id);
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}


#[test]
#[available_gas(10000000)]
fn test_bid_below_reserve_price() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 50 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();
    // auction_place_bid below reserve price
    let bid_below_reserve: u256 = option_params.reserve_price - 1;

    set_contract_address(option_bidder_buyer_1());
    let success = vault_dispatcher.auction_place_bid(10 * decimals(), bid_below_reserve);
    assert(success == false, 'should not be able to bid');
}


#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    let wei_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(
        wei_balance_before_bid == wei_balance_after_bid + bid_amount,
        'bid amounts should be locked up'
    );
}


#[test]
#[available_gas(10000000)]
fn test_zero_bid_count() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(0, option_params.reserve_price);
    let wei_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid, 'balance should match');
}

#[test]
#[available_gas(10000000)]
fn test_zero_bid_price() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, 0);
    let wei_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid, 'balance should match');
}

#[test]
#[available_gas(10000000)]
fn test_eth_unused_for_rejected_bids() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());

    let wei_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price - 100);
    let wei_balance_after_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(wei_balance_before_bid == wei_balance_after_bid, 'bid should not be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_eth_lockup_for_unused_bids() { // accepted but still unused bids
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_after_auction: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(
        wei_balance_before_bid == wei_balance_after_auction + bid_amount,
        'bid amounts should be locked up'
    );
    assert(bid_count > option_params.total_options_available, 'bid count cannot be > total opt');
}

#[test]
#[available_gas(10000000)]
fn test_eth_transfer_for_unused_bids_after_claim() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei: u256 = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());
    let wei_balance_before_bid: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let wei_balance_before_claim: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    let amount_transferred: u256 = vault_dispatcher
        .refund_unused_bid_deposit(option_round_id, option_bidder_buyer_1());
    let wei_balance_after_claim: u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(
        wei_balance_after_claim == wei_balance_before_claim + amount_transferred,
        'bid amounts should be locked up'
    );
    assert(
        amount_transferred == (bid_count - option_params.total_options_available)
            * vault_dispatcher.get_auction_clearing_price(option_round_id),
        'amount transfered shd match'
    );
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_1() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count_1: u256 = option_params.total_options_available / 2 + 1;
    let bid_count_2: u256 = option_params.total_options_available / 2;
    let bid_amount_1: u256 = bid_count_1 * option_params.reserve_price * decimals();
    let bid_amount_2: u256 = bid_count_2 * option_params.reserve_price * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_2, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let options_created_count = vault_dispatcher.total_options_sold();
    assert(options_created_count == option_params.total_options_available, 'option shd match up');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_2() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();
    let bid_option_count_user_1: u256 = (option_params.total_options_available / 2) + 1;
    let bid_option_count_user_2: u256 = (option_params.total_options_available / 2);

    let bid_amount_user_1: u256 = bid_option_count_user_1
        * option_params.reserve_price
        * decimals();
    let bid_amount_user_2: u256 = bid_option_count_user_2
        * (option_params.reserve_price - 10)
        * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, option_params.reserve_price - 10);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let options_created_count = vault_dispatcher.total_options_sold();
    assert(options_created_count == bid_option_count_user_1, 'options shd match');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_3() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let options_created = vault_dispatcher.total_options_sold();
    assert(options_created == bid_count, 'options equal successful bids');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_4() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = 2;
    let bid_amount: u256 = bid_count * (option_params.reserve_price - 1) * decimals();
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price - 1);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let options_created = vault_dispatcher.total_options_sold();
    assert(options_created == 0, 'options equal successful bids');
}

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_5() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei: u256 = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_count: u256 = option_params.total_options_available + 10;
    let bid_amount: u256 = bid_count * option_params.reserve_price * decimals();
    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount, option_params.reserve_price);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let options_created = vault_dispatcher.total_options_sold();
    assert(
        options_created == option_params.total_options_available, 'options equal successful bids'
    );
}

/// matt: added this test to test options sold count when 2 users bid for all >options

#[test]
#[available_gas(10000000)]
fn test_total_options_after_auction_6() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();
    let bid_option_count_user_1: u256 = (option_params.total_options_available / 2) + 1;
    let bid_option_count_user_2: u256 = (option_params.total_options_available / 2);

    let bid_amount_user_1: u256 = bid_option_count_user_1
        * option_params.reserve_price
        * decimals();
    let bid_amount_user_2: u256 = bid_option_count_user_2
        * (option_params.reserve_price + 10)
        * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, option_params.reserve_price);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, option_params.reserve_price + 10);
    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let options_created_count: u256 = vault_dispatcher.total_options_sold();
    assert(options_created_count == option_params.total_options_available, 'options shd match');
// todo matt: test refunded bids? (== 1 for user 1)
}

///////////////////// tests below are based on auction_reference_size_is_max_amount.py results/////////////////////////

#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_1() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 10000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();

    let bid_option_count_user_1: u256 = (option_params.total_options_available / 3);
    let bid_price_per_unit_user_1: u256 = option_params.reserve_price + 1;
    let bid_amount_user_1: u256 = bid_option_count_user_1 * bid_price_per_unit_user_1 * decimals();

    let bid_option_count_user_2: u256 = (option_params.total_options_available / 3);
    let bid_price_per_unit_user_2: u256 = option_params.reserve_price + 2;
    let bid_amount_user_2: u256 = bid_option_count_user_2 * bid_price_per_unit_user_2 * decimals();

    let bid_option_count_user_3: u256 = (option_params.total_options_available / 3);
    let bid_price_per_unit_user_3: u256 = option_params.reserve_price + 3;
    let bid_amount_user_3: u256 = bid_option_count_user_3 * bid_price_per_unit_user_3 * decimals();

    let bid_option_count_user_4: u256 = (option_params.total_options_available / 3);
    let bid_price_per_unit_user_4: u256 = option_params.reserve_price + 4;
    let bid_amount_user_4: u256 = bid_option_count_user_4 * bid_price_per_unit_user_4 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_amount_user_1, bid_price_per_unit_user_1);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_amount_user_2, bid_price_per_unit_user_2);

    set_contract_address(option_bidder_buyer_3());
    vault_dispatcher.auction_place_bid(bid_amount_user_3, bid_price_per_unit_user_3);

    set_contract_address(option_bidder_buyer_4());
    vault_dispatcher.auction_place_bid(bid_amount_user_4, bid_price_per_unit_user_4);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let total_options_created_count: u256 = vault_dispatcher.total_options_sold();
    let options_created_user_1_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_1());
    let options_created_user_2_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_2());
    let options_created_user_3_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_3());
    let options_created_user_4_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_4());

    assert(
        total_options_created_count == option_params.total_options_available, 'options shd match'
    );
    assert(options_created_user_1_count == bid_option_count_user_1, 'options shd match');
    assert(options_created_user_2_count == bid_option_count_user_2, 'options shd match');
    assert(options_created_user_3_count == bid_option_count_user_3, 'options shd match');
    assert(
        options_created_user_4_count == total_options_created_count
            - (bid_price_per_unit_user_1 + bid_option_count_user_2 + bid_option_count_user_3),
        'options shd match'
    );
// matt: shouldnt it be 0, 1/3, 1/3, 1/3 ? and also the above is using a per_unit + count + count
}


// test where the total options available have not been exhausted 
#[test]
#[available_gas(10000000)]
fn test_option_balance_per_bidder_after_auction_2() {
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 100000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction

    let (option_round_id, mut option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();
    option_params.total_options_available = 300; //TODO  need a better to mock this
    option_params.reserve_price = 2 * decimals();

    let bid_option_amount_user_1: u256 = 50 * decimals();
    let bid_price_per_unit_user_1: u256 = 20 * decimals();

    let bid_option_amount_user_2: u256 = 142 * decimals();
    let bid_price_per_unit_user_2: u256 = 11 * decimals();

    let bid_option_amount_user_3: u256 = 235 * decimals();
    let bid_price_per_unit_user_3: u256 = 11 * decimals();

    let bid_option_amount_user_4: u256 = 222 * decimals();
    let bid_price_per_unit_user_4: u256 = 2 * decimals();

    let bid_option_amount_user_5: u256 = 75 * decimals();
    let bid_price_per_unit_user_5: u256 = 1 * decimals();

    let bid_option_amount_user_6: u256 = 35 * decimals();
    let bid_price_per_unit_user_6: u256 = 1 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_1, bid_price_per_unit_user_1);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_2, bid_price_per_unit_user_2);

    set_contract_address(option_bidder_buyer_3());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_3, bid_price_per_unit_user_3);

    set_contract_address(option_bidder_buyer_4());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_4, bid_price_per_unit_user_4);

    set_contract_address(option_bidder_buyer_5());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_5, bid_price_per_unit_user_5);

    set_contract_address(option_bidder_buyer_6());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_6, bid_price_per_unit_user_6);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let total_options_created_count: u256 = vault_dispatcher.total_options_sold();
    let options_created_user_1_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_1());
    let options_created_user_2_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_2());
    let options_created_user_3_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_3());
    let options_created_user_4_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_4());
    let options_created_user_5_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_5());
    let options_created_user_6_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_6());

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
    let (vault_dispatcher, eth_dispatcher): (IVaultDispatcher, IERC20Dispatcher) = setup();

    let deposit_amount_wei = 100000 * decimals();
    set_contract_address(liquidity_provider_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
    // start_new_option_round will also starts the auction
    let (option_round_id, mut option_params, _): (u256, OptionRoundParams, ContractAddress) =
        vault_dispatcher
        .start_new_option_round();
    option_params.total_options_available = 200; //TODO  need a better to mock this
    option_params.reserve_price = 2 * decimals();

    let bid_option_amount_user_1: u256 = 50 * decimals();
    let bid_price_per_unit_user_1: u256 = 20 * decimals();

    let bid_option_amount_user_2: u256 = 142 * decimals();
    let bid_price_per_unit_user_2: u256 = 11 * decimals();

    let bid_option_amount_user_3: u256 = 235 * decimals();
    let bid_price_per_unit_user_3: u256 = 11 * decimals();

    let bid_option_amount_user_4: u256 = 422 * decimals();
    let bid_price_per_unit_user_4: u256 = 2 * decimals();

    let bid_option_amount_user_5: u256 = 75 * decimals();
    let bid_price_per_unit_user_5: u256 = 1 * decimals();

    let bid_option_amount_user_6: u256 = 35 * decimals();
    let bid_price_per_unit_user_6: u256 = 1 * decimals();

    set_contract_address(option_bidder_buyer_1());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_1, bid_price_per_unit_user_1);

    set_contract_address(option_bidder_buyer_2());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_2, bid_price_per_unit_user_2);

    set_contract_address(option_bidder_buyer_3());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_3, bid_price_per_unit_user_3);

    set_contract_address(option_bidder_buyer_4());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_4, bid_price_per_unit_user_4);

    set_contract_address(option_bidder_buyer_5());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_5, bid_price_per_unit_user_5);

    set_contract_address(option_bidder_buyer_6());
    vault_dispatcher.auction_place_bid(bid_option_amount_user_6, bid_price_per_unit_user_6);

    set_block_timestamp(option_params.auction_end_time + 1);
    vault_dispatcher.settle_auction();

    let total_options_created_count: u256 = vault_dispatcher.total_options_sold();
    let options_created_user_1_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_1());
    let options_created_user_2_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_2());
    let options_created_user_3_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_3());
    let options_created_user_4_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_4());
    let options_created_user_5_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_5());
    let options_created_user_6_count: u256 = vault_dispatcher
        .option_balance_of(option_bidder_buyer_6());

    let unused_bid_amount_user_3: u256 = vault_dispatcher
        .unused_bid_deposit_balance_of(option_bidder_buyer_3());

    assert(
        total_options_created_count == option_params.total_options_available, 'options shd match'
    );
    assert(options_created_user_1_count == 25, 'options shd match');
    assert(options_created_user_2_count == 71, 'options shd match');
    assert(options_created_user_3_count == 104, 'options shd match');
    assert(options_created_user_4_count == 0, 'options shd match');
    assert(options_created_user_5_count == 0, 'options shd match');
    assert(options_created_user_6_count == 0, 'options shd match');
    assert(unused_bid_amount_user_3 == 27 * decimals(), 'unused bid amount shd match');
}
