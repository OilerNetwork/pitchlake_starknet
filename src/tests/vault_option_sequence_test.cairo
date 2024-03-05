use array::ArrayTrait;
use debug::PrintTrait;
use option::OptionTrait;
use openzeppelin::token::erc20::interface::{
    IERC20, IERC20Dispatcher, IERC20DispatcherTrait, IERC20SafeDispatcher,
    IERC20SafeDispatcherTrait,
};

use pitch_lake_starknet::vault::{
    IVaultDispatcher, IVaultSafeDispatcher, IVaultDispatcherTrait, Vault, IVaultSafeDispatcherTrait,
    OptionRoundCreated
};
use pitch_lake_starknet::option_round::{OptionRoundParams};

use result::ResultTrait;
use starknet::{
    ClassHash, ContractAddress, contract_address_const, deploy_syscall,
    Felt252TryIntoContractAddress, get_contract_address, get_block_timestamp,
    testing::{set_block_timestamp, set_contract_address}
};

use starknet::contract_address::ContractAddressZeroable;
use openzeppelin::utils::serde::SerializedAppend;

use traits::Into;
use traits::TryInto;
use pitch_lake_starknet::eth::Eth;
use pitch_lake_starknet::tests::utils::{
    setup, decimals, deploy_vault, allocated_pool_address, unallocated_pool_address,
    timestamp_start_month, timestamp_end_month, liquidity_provider_1, liquidity_provider_2,
    option_bidder_buyer_1, option_bidder_buyer_2, option_bidder_buyer_3, option_bidder_buyer_4,
    zero_address, vault_manager, weth_owner, option_round_contract_address, mock_option_params,
    pop_log, assert_no_events_left, month_duration
};
use pitch_lake_starknet::option_round::{IOptionRoundDispatcher, IOptionRoundDispatcherTrait};
use pitch_lake_starknet::tests::mock_market_aggregator::{
    MockMarketAggregator, IMarketAggregatorSetter, IMarketAggregatorSetterDispatcher,
    IMarketAggregatorSetterDispatcherTrait
};


/// helpers
fn assert_event_option_created(
    prev_round: ContractAddress,
    new_round: ContractAddress,
    collaterized_amount: u256,
    option_round_params: OptionRoundParams
) {
    let event = pop_log::<OptionRoundCreated>(zero_address()).unwrap();
    assert(event.prev_round == prev_round, 'Invalid prev_round');
    assert(event.new_round == new_round, 'Invalid new_round');
    assert(event.collaterized_amount == collaterized_amount, 'Invalid collaterized_amount');
    assert(event.option_round_params == option_round_params, 'Invalid option_round_params');
    assert_no_events_left(zero_address());
}


/// tests
#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'auction expired, cannot auction_place_bid',))]
fn test_bid_after_expiry() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    let deposit_amount_wei = 50 * decimals();
    set_contract_address(option_bidder_buyer_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (round_id, params): (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Place bid after auction expiry
    let option_amount = 50;
    let option_price = 2 * decimals();
    let bid_amount = option_amount * option_price;
    set_contract_address(option_bidder_buyer_1());
    set_block_timestamp(params.option_expiry_time + 10);
    round_dispatcher.auction_place_bid(bid_amount, option_price);
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'auction cannot settle before due time',))]
fn test_settle_auction_before_due_time() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    let deposit_amount_wei = 50 * decimals();
    set_contract_address(option_bidder_buyer_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    set_block_timestamp(params.auction_end_time - 10);
    round_dispatcher.settle_auction();
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('Some error', 'multiple parallel rounds not allowed'))]
fn test_multiple_parallel_rounds_failure() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    let deposit_amount_wei = 50 * decimals();
    set_contract_address(option_bidder_buyer_1());
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (round_id, params): (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

    // Try to again before current round is settled
    let (round_id, params): (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();
}


#[test]
#[available_gas(10000000)]
fn test_current_round_round_is_new_round() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 10000 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, option_round_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (curr_round_id, curr_option_params) = vault_dispatcher.current_option_round();

    assert(option_round_id == option_round_id, 'current round is new round');
    assert(option_round_params == curr_option_params, 'current round is new round');
}

// was already commented out, circle back once finished updating curr tests
// #[test]
// #[available_gas(10000000)]
// fn test_settled_and_new_round_sets_prev_round() {

//     let (vault_dispatcher, eth_dispatcher):(IVaultDispatcher, IERC20Dispatcher) = setup();
//     let deposit_amount_wei:u256 = 50 * decimals();

//     set_contract_address(liquidity_provider_1());
//     let lp_id : u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);
//     // start_new_option_round will also starts the auction
//     let (option_round_id, option_params) : (u256, OptionRoundParams) = vault_dispatcher.start_new_option_round();

//     let bid_count: u256 = option_params.total_options_available;
//     let bid_price_user_1 : u256 = option_params.reserve_price;
//     let bid_amount: u256 = bid_count * bid_price_user_1;

//     set_contract_address(option_bidder_buyer_1());
//     vault_dispatcher.auction_place_bid(bid_amount, bid_price_user_1 );

//     set_block_timestamp(option_params.auction_end_time + 1);
//     vault_dispatcher.settle_auction();
//     set_block_timestamp(option_params.option_expiry_time + 1);

//     let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher = IMarketAggregatorSetterDispatcher{contract_address:vault_dispatcher.get_market_aggregator().contract_address};
//     mock_maket_aggregator_setter.set_current_base_fee(option_params.reserve_price + 10);    

//     vault_dispatcher.settle_option_round(); 

//     let new_option_params : OptionRoundParams = vault_dispatcher.generate_option_round_params( timestamp_end_month() +  month_duration()  );
//     let unallocated_amount_before_second_round_start: u256 = vault_dispatcher.total_unallocated_liquidity();
//     let new_vault_dispatcher: IOptionRoundDispatcher = vault_dispatcher.start_new_option_round(new_option_params);
//     let (previous_option_params, previous_vault_dispatcher): (OptionRoundParams, IOptionRoundDispatcher) = vault_dispatcher.previous_option_round();

//     assert(previous_option_params == option_params, 'curr round = prev round ');
//     assert_event_option_created(vault_dispatcher.contract_address, new_vault_dispatcher.contract_address, unallocated_amount_before_second_round_start, new_option_params);
// }

#[test]
#[available_gas(10000000)]
fn test_new_round_after_settle() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 50 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Place bid
    let bid_count: u256 = option_params.total_options_available;
    let bid_price_user_1: u256 = option_params.reserve_price;
    let bid_amount: u256 = bid_count * bid_price_user_1;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, bid_price_user_1);

    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();
    set_block_timestamp(option_params.option_expiry_time + 1);

    let mock_maket_aggregator_setter: IMarketAggregatorSetterDispatcher =
        IMarketAggregatorSetterDispatcher {
        contract_address: round_dispatcher.get_market_aggregator().contract_address
    };
    mock_maket_aggregator_setter.set_current_base_fee(option_params.reserve_price + 10);

    // Start new option round should not throw an exception
    round_dispatcher.settle_option_round();

    let unallocated_amount_before_second_round_start: u256 = vault_dispatcher
        .total_unallocated_liquidity();

    vault_dispatcher.start_new_option_round();
// should not throw an exception, TODO better way to check vault_dispatcher is valid
// matt: should current/next round be updated here, or should we just check that liq/premiums roll over 
// assert_event_option_created(vault_dispatcher.contract_address, new_vault_dispatcher.contract_address, unallocated_amount_before_second_round_start, new_option_params);
}


#[test]
#[available_gas(10000000)]
fn test_settle_before_expiry() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 50 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Place bid
    let option_amount: u256 = 50;
    let option_price: u256 = 2 * decimals();
    let bid_amount: u256 = option_amount * option_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_price);

    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle option round before expiry
    set_block_timestamp(option_params.option_expiry_time - 10000);
    let success = round_dispatcher.settle_option_round();
    assert(success == false, 'no settle before expiry');
}

#[test]
#[available_gas(10000000)]
#[should_panic(expected: ('some error', 'no settle before auction end'))]
fn test_settle_before_end_auction() {
    let (vault_dispatcher, _): (IVaultDispatcher, IERC20Dispatcher) = setup();

    // Add liq. to current round
    set_contract_address(liquidity_provider_1());
    let deposit_amount_wei = 50 * decimals();
    let lp_id: u256 = vault_dispatcher.open_liquidity_position(deposit_amount_wei);

    // Start the option round
    let (option_round_id, option_params): (u256, OptionRoundParams) = vault_dispatcher
        .start_new_option_round();

    // OptionRoundDispatcher
    let (round_id, option_params) = vault_dispatcher.current_option_round();
    let round_dispatcher: IOptionRoundDispatcher = IOptionRoundDispatcher {
        contract_address: vault_dispatcher.option_round_addresses(round_id)
    };

    // Place bid
    let option_amount: u256 = 50;
    let option_price: u256 = 2 * decimals();
    let bid_amount: u256 = option_amount * option_price;
    set_contract_address(option_bidder_buyer_1());
    round_dispatcher.auction_place_bid(bid_amount, option_price);

    // Settle auction
    set_block_timestamp(option_params.auction_end_time + 1);
    round_dispatcher.settle_auction();

    // Settle option round before expiry
    set_block_timestamp(option_params.option_expiry_time);
    let success = round_dispatcher.settle_option_round();
    assert(success == false, 'no settle before expiry');
}
