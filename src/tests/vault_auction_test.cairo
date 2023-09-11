

use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;

use openzeppelin::utils::serde::SerializedAppend;
use openzeppelin::token::erc20::interface::{
    IERC20,
    IERC20Dispatcher,
    IERC20DispatcherTrait,
    IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait};
use pitch_lake_starknet::option_round::{IOptionRound, IOptionRoundDispatcher, IOptionRoundDispatcherTrait, IOptionRoundSafeDispatcher, IOptionRoundSafeDispatcherTrait, OptionRoundParams};
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{setup, deployVault, allocated_pool_address, unallocated_pool_address, timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2, option_bidder_buyer_1, option_bidder_buyer_2, vault_manager, weth_owner};

use result::ResultTrait;
use starknet::{
    ClassHash,
    ContractAddress,
    contract_address_const,
    deploy_syscall,
    Felt252TryIntoContractAddress,
    get_contract_address,
    get_block_timestamp, testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;

use traits::Into;
use traits::TryInto;


#[test]
#[available_gas(10000000)]
fn test_bid_after_expiry() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();
    
    set_contract_address(liquidity_provider_1());
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(option_params.expiry_time );
    round_dispatcher.end_auction();
    let success = round_dispatcher.bid(option_amount, option_price);

    assert(success == false, 'no bid after expiry');
}


#[test]
#[available_gas(10000000)]
fn test_withdrawal_after_premium() {

    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    let deposit_amount_wei:u256 = 50 * vault_dispatcher.decimals().into();
    let option_amount = 50;
    let option_price = 2 * vault_dispatcher.decimals().into();

    set_contract_address(liquidity_provider_1());
    let success:bool  = vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    
    let unallocated_wei_before_premium = vault_dispatcher.total_unallocated_liquidity();
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(option_amount, option_params.reserve_price); 
    round_dispatcher.settle(option_params.strike_price - 100 , ArrayTrait::new()); // means there is no payout.
    round_dispatcher.end_auction();
    let unallocated_wei_after_premium = vault_dispatcher.total_unallocated_liquidity();
    assert(unallocated_wei_before_premium < unallocated_wei_after_premium, 'premium should have paid out');
}
#[test]
#[available_gas(10000000)]
fn test_clearing_price_1() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);
    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == option_params.reserve_price, 'clear price equal reserve price');
}


#[test]
#[available_gas(10000000)]
fn test_clearing_price_2() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1 : u256 = option_params.reserve_price;
    let bid_price_user_2 : u256 = option_params.reserve_price + 10;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, bid_price_user_1 );
    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count,  bid_price_user_2);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   

#[test]
#[available_gas(10000000)]
fn test_clearing_price_3() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count_user_1: u256 = option_params.total_options_available - 20;
    let bid_count_user_2: u256 = 20;

    let bid_price_user_1 : u256 = option_params.reserve_price + 100;
    let bid_price_user_2 : u256 = option_params.reserve_price ;

    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count_user_1, bid_price_user_1 );

    set_contract_address(option_bidder_buyer_2());
    round_dispatcher.bid(bid_count_user_2,  bid_price_user_2);

    round_dispatcher.end_auction();
 
    let clearing_price: u256 = round_dispatcher.get_auction_clearing_price();
    assert(clearing_price == bid_price_user_2, 'clear price equal reserve price');
}   


#[test]
#[available_gas(10000000)]
fn test_lock_of_bid_funds() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    // let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    // let bid_count: u256 = 2;
    // set_contract_address(option_bidder_buyer_1());
    // let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    // round_dispatcher.bid(bid_count, option_params.reserve_price);
    // let eth_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    // assert(eth_balance_before_bid == eth_balance_after_bid + (bid_count * option_params.reserve_price), 'bid amounts should be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_eth_unused_for_rejected_bids() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = 2;
    set_contract_address(option_bidder_buyer_1());

    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price - 100);
    let eth_balance_after_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());

    assert(eth_balance_before_bid == eth_balance_after_bid, 'bid should not be locked up');
}

#[test]
#[available_gas(10000000)]
fn test_eth_refund_for_unused_bids() {
    let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei:u256 = 1000000 * vault_dispatcher.decimals().into();
    vault_dispatcher.deposit_liquidity(deposit_amount_wei);
    // start_new_option_round will also start the auction
    let (option_params, round_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.start_new_option_round(timestamp_start_month(), timestamp_end_month());

    let bid_count: u256 = option_params.total_options_available + 10;
    set_contract_address(option_bidder_buyer_1());
    let eth_balance_before_bid :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    round_dispatcher.bid(bid_count, option_params.reserve_price);

    round_dispatcher.end_auction();
    let eth_balance_after_auction :u256 = eth_dispatcher.balance_of(option_bidder_buyer_1());
    assert(eth_balance_before_bid == eth_balance_after_auction + ((bid_count - option_params.total_options_available) * option_params.reserve_price), 'bid amounts should be locked up');
} 



